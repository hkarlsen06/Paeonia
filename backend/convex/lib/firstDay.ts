import type { Doc } from "../_generated/dataModel";
import { findCurrentCouple, userHasDirectEntitlement } from "./access";
import { assertNoPendingAccountDeletion } from "./accountDeletion";
import { findCoupleDayAt, getOrCreateCoupleDayAt } from "./coupleDays";
import { insertDailyAnswer } from "./dailyAnswers";
import { QuestionContentReader, insertDailyQuestionInstance, pickQuestionVersion } from "./dailyQuestions";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, orNull, withUpdatedAt } from "./db";
import { fail } from "./errors";
import { newUuid } from "./ids";
import { queueOrphanedMediaAssetForDelete } from "./mediaOrphans";
import { nowIso } from "./time";
import {
  getOrCreateWidgetCanvas,
  insertWidgetDrawingRevision,
  isUsableWidgetPayloadAsset,
  type WidgetDrawingPayload,
} from "./widgetDrawings";

/**
 * First day drafts: what the inviter makes while they wait for their partner. A couple only
 * exists once the partner accepts the invite, so the start date, the answer to the couple's
 * first question, and the first widget drawing wait in `first_day_drafts`, and
 * `accept_pairing_invite` turns them into couple content with `materializeFirstDayDrafts`.
 */

type Draft = Doc<"first_day_drafts">;
type DraftDrawing = NonNullable<Draft["drawing"]>;

/** Where a first day drawing upload is stored. The couple's canvas does not exist yet. */
export function firstDayDrawingPath(userId: string, revisionId: string, extension: string): string {
  return `drafts/${userId}/revisions/${revisionId}/drawing.${extension}`;
}

/**
 * A draft write needs a user without an active couple and without a pending account deletion.
 * `entitled` also asks for the user's own subscription or grant.
 */
export async function assertFirstDayDraftAllowed(ctx: ReaderCtx, userId: string, options: { entitled: boolean }): Promise<void> {
  await assertNoPendingAccountDeletion(ctx, userId);
  if (await findCurrentCouple(ctx, userId)) {
    fail("23505", "user already has an active couple");
  }
  if (options.entitled && !(await userHasDirectEntitlement(ctx, userId))) {
    fail("42501", "direct entitlement is required for first day content");
  }
}

/**
 * The question of the couple's current day that the first day question became when the partner
 * joined, found by its question version. Null without a couple or without that question today.
 */
export async function findPairedFirstDayQuestion(
  ctx: ReaderCtx,
  userId: string,
  questionVersionId: string,
): Promise<Doc<"daily_question_instances"> | null> {
  const couple = await findCurrentCouple(ctx, userId);
  const day = couple ? await findCoupleDayAt(ctx, couple.id, nowIso()) : null;
  if (!day) return null;
  const instances = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_day_id_question_version_id", (q) =>
      q.eq("couple_day_id", day.id).eq("question_version_id", questionVersionId),
    )
    .collect();
  return instances.find((instance) => instance.status === "active") ?? null;
}

export async function findFirstDayDraft(ctx: ReaderCtx, userId: string): Promise<Draft | null> {
  return await ctx.db
    .query("first_day_drafts")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
}

export async function ensureFirstDayDraft(ctx: WriterCtx, userId: string): Promise<Draft> {
  const existing = await findFirstDayDraft(ctx, userId);
  if (existing) return existing;
  const now = nowIso();
  const docId = await ctx.db.insert("first_day_drafts", {
    user_id: userId,
    created_at: now,
    updated_at: now,
  });
  return (await ctx.db.get(docId))!;
}

/** Before pairing there is no partner to pick, and the first day offers written answers only. */
function firstDayAnswerKinds(kinds: string[]): boolean {
  return kinds.includes("text") && !kinds.includes("partner_choice");
}

/** The couple's first question, by the daily selection rules. A new couple has no history yet. */
export async function pickFirstDayQuestionVersion(ctx: ReaderCtx): Promise<string> {
  return await pickQuestionVersion(ctx, {
    coupleId: null,
    excludedQuestionIds: new Set(),
    history: new Map(),
    acceptsKinds: firstDayAnswerKinds,
  });
}

/** The `get_first_day_draft` result. */
export async function firstDayDraftJson(ctx: ReaderCtx, draft: Draft) {
  const content = draft.question_version_id ? await new QuestionContentReader(ctx).get(draft.question_version_id) : null;
  return {
    started_on: orNull(draft.started_on),
    question: content
      ? {
          question_version_id: content.version.id,
          question_key: content.question.key,
          prompt_en: content.en.prompt,
          prompt_nb: content.nb.prompt,
          short_prompt_en: content.en.short_prompt,
          short_prompt_nb: content.nb.short_prompt,
          answer_text: draft.answer?.body ?? null,
          answered_at: draft.answer?.answered_at ?? null,
        }
      : null,
    drawing: draft.drawing
      ? {
          media_asset_id: draft.drawing.media_asset_id,
          revision_id: draft.drawing.revision_id,
          saved_at: draft.drawing.saved_at,
          bounds: orNull(draft.drawing.bounds),
        }
      : null,
    updated_at: draft.updated_at,
  };
}

/** Deletes a user's draft and queues its drawing for deletion. Account deletion calls it. */
export async function deleteFirstDayDraft(ctx: WriterCtx, userId: string): Promise<void> {
  const draft = await findFirstDayDraft(ctx, userId);
  if (!draft) return;
  await ctx.db.delete(draft._id);
  await queueOrphanedMediaAssetForDelete(ctx, draft.drawing?.media_asset_id);
}

function drawingPayload(drawing: DraftDrawing): WidgetDrawingPayload {
  return {
    payloadBytes: drawing.payload_bytes,
    uncompressedBytes: drawing.uncompressed_bytes,
    compression: drawing.compression,
    strokeCount: drawing.stroke_count,
    pointCount: drawing.point_count,
    bounds: drawing.bounds,
    sha256: drawing.sha256,
    validatedAt: drawing.client_decode_validated_at,
    rendererVersion: drawing.client_renderer_version,
    validationVersion: drawing.client_validation_version,
  };
}

/** True when the draft's drawing became the couple's active revision. */
async function materializeDrawing(ctx: WriterCtx, coupleId: string, draft: Draft, drawing: DraftDrawing): Promise<boolean> {
  const asset = await getByUuid(ctx, "media_assets", drawing.media_asset_id);
  const payload = drawingPayload(drawing);
  if (
    !asset ||
    asset.reserved_parent_id !== drawing.revision_id ||
    !isUsableWidgetPayloadAsset(asset, {
      ownerUserId: draft.user_id,
      coupleId: undefined,
      storagePath: firstDayDrawingPath(draft.user_id, drawing.revision_id, "pkdrawing"),
      payload,
    }) ||
    (await getByUuid(ctx, "widget_drawing_revisions", drawing.revision_id))
  ) {
    return false;
  }
  // The asset keeps its drafts path. Media reads check the couple and the revision, not the path.
  await ctx.db.patch(asset._id, withUpdatedAt({ couple_id: coupleId }));
  const canvas = await getOrCreateWidgetCanvas(ctx, coupleId);
  await insertWidgetDrawingRevision(ctx, canvas, {
    id: drawing.revision_id,
    authorUserId: draft.user_id,
    parentRevisionId: canvas.active_revision_id,
    payloadMediaAssetId: asset.id,
    payload,
    // The partner sees it in the app while they join.
    alert: false,
  });
  return true;
}

/**
 * Turns both members' drafts into couple content and deletes them. Runs inside
 * `accept_pairing_invite` after the couple and its members exist. The joining partner is in
 * the app, so they get no visible pushes for this content. Streak activity still counts.
 */
export async function materializeFirstDayDrafts(
  ctx: WriterCtx,
  input: { coupleId: string; creatorUserId: string; partnerUserId: string },
): Promise<void> {
  const creatorDraft = await findFirstDayDraft(ctx, input.creatorUserId);
  const partnerDraft = await findFirstDayDraft(ctx, input.partnerUserId);
  // The partner's draft goes first, so the creator's drawing ends up as the active revision.
  const drafts = [partnerDraft, creatorDraft].filter((draft): draft is Draft => draft !== null);
  if (drafts.length === 0) return;
  const now = nowIso();

  const couple = await getByUuid(ctx, "couples", input.coupleId);
  const startedOn = creatorDraft?.started_on ?? partnerDraft?.started_on;
  if (couple && couple.started_on === undefined && startedOn !== undefined) {
    await ctx.db.patch(couple._id, withUpdatedAt({ started_on: startedOn }));
  }

  // A couple day has one question. The creator's answered draft question becomes today's,
  // then the partner's. When both answered different questions, the partner's becomes the
  // next day's question with their answer on it, so no saved answer is lost.
  const reader = new QuestionContentReader(ctx);
  const usable: (Draft & { question_version_id: string })[] = [];
  for (const draft of [creatorDraft, partnerDraft]) {
    if (draft?.question_version_id && (await reader.get(draft.question_version_id))) {
      usable.push({ ...draft, question_version_id: draft.question_version_id });
    }
  }
  const answered = usable.filter((draft) => draft.answer !== undefined);
  const versionIds: string[] = [];
  for (const draft of [...answered, ...usable]) {
    if (!versionIds.includes(draft.question_version_id)) versionIds.push(draft.question_version_id);
  }
  // A question after the first only gets a day when it holds an answer.
  const daysOfQuestions = versionIds.filter(
    (versionId, index) => index === 0 || answered.some((draft) => draft.question_version_id === versionId),
  );
  let dayStart = now;
  for (const versionId of daysOfQuestions) {
    const dayId = await getOrCreateCoupleDayAt(ctx, input.coupleId, dayStart);
    dayStart = (await getByUuid(ctx, "couple_days", dayId))!.ends_at;
    const instanceId = await insertDailyQuestionInstance(ctx, { couple_day_id: dayId, question_version_id: versionId });
    const instance = (await getByUuid(ctx, "daily_question_instances", instanceId))!;
    for (const draft of usable) {
      if (draft.question_version_id !== versionId || !draft.answer) continue;
      if (!(await reader.get(versionId))?.answer_kinds.includes("text")) continue;
      await insertDailyAnswer(ctx, {
        userId: draft.user_id,
        instance,
        answerId: newUuid(),
        textBody: draft.answer.body,
        selectedPartnerUserId: null,
        selectedOption: null,
        mediaAssetIds: [],
        notifyPartner: false,
        answeredAt: now,
      });
    }
  }

  for (const draft of drafts) {
    const used = draft.drawing ? await materializeDrawing(ctx, input.coupleId, draft, draft.drawing) : false;
    await ctx.db.delete(draft._id);
    if (draft.drawing && !used) {
      await queueOrphanedMediaAssetForDelete(ctx, draft.drawing.media_asset_id);
    }
  }
}
