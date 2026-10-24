import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { isSupersededClientOperation, runClientOperation } from "./lib/clientOperations";
import { assertStartedOnNotInFuture } from "./lib/coupleDays";
import { getByUuid, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { submitDailyAnswer, updateDailyAnswerText } from "./lib/dailyAnswers";
import {
  assertFirstDayDraftAllowed,
  ensureFirstDayDraft,
  findFirstDayDraft,
  findPairedFirstDayQuestion,
  firstDayDraftJson,
  firstDayDrawingPath,
  pickFirstDayQuestionVersion,
} from "./lib/firstDay";
import { optionalDateArg, timestampArg, uuidArg } from "./lib/ids";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { btrim, charLength } from "./lib/text";
import { nowIso } from "./lib/time";
import {
  isUsableWidgetPayloadAsset,
  parseWidgetDrawingPayload,
  widgetDrawingPayloadArgs,
  widgetDrawingPayloadHashFields,
} from "./lib/widgetDrawings";

/**
 * The inviter's first day, before their partner joins: the start date, an answer to the
 * couple's first daily question, and the first widget drawing. Everything waits in the caller's `first_day_drafts`
 * row until `pairing:accept_pairing_invite` turns it into couple content (lib/firstDay.ts).
 * Every write refuses a user who already has an active couple.
 */

/**
 * Creates the caller's draft and picks its question once. Returns what `get_first_day_draft`
 * returns.
 */
export const start_first_day_draft = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertFirstDayDraftAllowed(ctx, userId, { entitled: false });
    const draft = await ensureFirstDayDraft(ctx, userId);
    if (draft.question_version_id !== undefined) return await firstDayDraftJson(ctx, draft);
    await ctx.db.patch(draft._id, withUpdatedAt({ question_version_id: await pickFirstDayQuestionVersion(ctx) }));
    return await firstDayDraftJson(ctx, (await ctx.db.get(draft._id))!);
  },
});

/**
 * The caller's draft: `{ started_on, question, drawing, updated_at }`, or null before
 * the first write. `question` has the prompt and the saved answer, null before it is picked.
 * `drawing` is `{ media_asset_id, revision_id, saved_at, bounds }`. The widget extension shows
 * it while the caller has no couple.
 */
export const get_first_day_draft = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const draft = await findFirstDayDraft(ctx, userId);
    return draft ? await firstDayDraftJson(ctx, draft) : null;
  },
});

/** Saves when the couple got together, or clears it with null. Works before the paywall. */
export const set_first_day_started_on = mutation({
  args: { p_started_on: v.union(v.null(), v.string()), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const startedOn = optionalDateArg(args.p_started_on);
    if (startedOn !== undefined) await assertStartedOnNotInFuture(ctx, userId, startedOn);
    const input = toClientOperation(args, {
      kind: "set_first_day_started_on",
      scope: `first_day_draft:${userId}:started_on`,
      request: { kind: "set_first_day_started_on", started_on: startedOn ?? "unset" },
    });
    await runClientOperation(ctx, userId, input, async () => {
      await assertFirstDayDraftAllowed(ctx, userId, { entitled: false });
      if (await isSupersededClientOperation(ctx, userId, input)) return null;
      const draft = await ensureFirstDayDraft(ctx, userId);
      await ctx.db.patch(draft._id, withUpdatedAt({ started_on: startedOn }));
      return null;
    });
    return null;
  },
});

/**
 * Saves or replaces the caller's written answer to the draft's question. Once the partner has
 * joined, the draft is gone and its question is the couple's first day, so the answer goes to
 * that question instead, the same way a daily answer does.
 */
export const save_first_day_answer = mutation({
  args: { p_question_version_id: v.string(), p_text: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const versionId = uuidArg(args.p_question_version_id);
    const body = btrim(args.p_text);
    if (body === "") fail("23514", "answer text is required");
    if (charLength(body) > 2000) fail("23514", "answer text is too long");
    const pairedQuestion = await findPairedFirstDayQuestion(ctx, userId, versionId);
    if (pairedQuestion) {
      const operation = {
        clientOperationId: uuidArg(args.p_client_operation_id),
        clientId: uuidArg(args.p_client_id),
        clientSequence: args.p_client_sequence,
        localCreatedAt: timestampArg(args.p_local_created_at),
      };
      const ownAnswer = await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", pairedQuestion.id).eq("user_id", userId))
        .unique();
      if (ownAnswer) {
        await updateDailyAnswerText(ctx, userId, pairedQuestion.id, body, operation);
      } else {
        await submitDailyAnswer(ctx, userId, pairedQuestion.id, { text: body }, operation);
      }
      return null;
    }
    const input = toClientOperation(args, {
      kind: "save_first_day_answer",
      scope: `first_day_draft:${userId}:answer:${versionId}`,
      request: { kind: "save_first_day_answer", question_version_id: versionId, text: body },
    });
    await runClientOperation(ctx, userId, input, async () => {
      await assertFirstDayDraftAllowed(ctx, userId, { entitled: true });
      if (await isSupersededClientOperation(ctx, userId, input)) return null;
      const draft = await findFirstDayDraft(ctx, userId);
      if (!draft || draft.question_version_id !== versionId) {
        return fail("22023", "first day question was not found");
      }
      await ctx.db.patch(draft._id, withUpdatedAt({ answer: { body, answered_at: nowIso() } }));
      return null;
    });
    return null;
  },
});

/**
 * Saves the caller's first widget drawing, replacing an earlier one. The payload is a
 * `widget_drawing_payload` upload reserved with `p_path_context: { first_day_draft: true }`
 * and no couple. Its reserved parent id is the revision id the drawing keeps on the couple's
 * canvas. Returns `{ revision_id, media_asset_id, saved_at }`.
 */
export const save_first_day_drawing = mutation({
  args: { ...widgetDrawingPayloadArgs, ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const assetId = uuidArg(args.p_payload_media_asset_id);
    const payload = parseWidgetDrawingPayload(args);
    const input = toClientOperation(args, {
      kind: "save_first_day_drawing",
      scope: `first_day_draft:${userId}:drawing`,
      request: ["save_first_day_drawing", assetId, ...widgetDrawingPayloadHashFields(payload)],
    });
    return await runClientOperation(ctx, userId, input, async () => {
      await assertFirstDayDraftAllowed(ctx, userId, { entitled: true });
      const current = (await findFirstDayDraft(ctx, userId))?.drawing;
      if (current && (await isSupersededClientOperation(ctx, userId, input))) {
        return { revision_id: current.revision_id, media_asset_id: current.media_asset_id, saved_at: current.saved_at };
      }
      const asset = await getByUuid(ctx, "media_assets", assetId);
      if (!asset) return fail("22023", "widget drawing payload asset was not found");
      const revisionId = asset.reserved_parent_id;
      const storagePath = firstDayDrawingPath(userId, revisionId, "pkdrawing");
      if (!isUsableWidgetPayloadAsset(asset, { ownerUserId: userId, coupleId: undefined, storagePath, payload })) {
        fail("23514", "widget drawing payload asset is not usable");
      }
      const draft = await ensureFirstDayDraft(ctx, userId);
      const previousAssetId = draft.drawing?.media_asset_id;
      const savedAt = nowIso();
      await ctx.db.patch(
        draft._id,
        withUpdatedAt({
          drawing: {
            media_asset_id: asset.id,
            revision_id: revisionId,
            payload_bytes: payload.payloadBytes,
            uncompressed_bytes: payload.uncompressedBytes,
            compression: payload.compression,
            stroke_count: payload.strokeCount,
            point_count: payload.pointCount,
            bounds: payload.bounds,
            sha256: payload.sha256,
            client_decode_validated_at: payload.validatedAt,
            client_renderer_version: payload.rendererVersion,
            client_validation_version: payload.validationVersion,
            saved_at: savedAt,
          },
        }),
      );
      if (previousAssetId !== undefined && previousAssetId !== asset.id) {
        await queueOrphanedMediaAssetForDelete(ctx, previousAssetId);
      }
      return { revision_id: revisionId, media_asset_id: asset.id, saved_at: savedAt };
    });
  },
});
