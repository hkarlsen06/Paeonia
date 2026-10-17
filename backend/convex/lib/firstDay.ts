import type { Doc } from "../_generated/dataModel";
import { findCurrentCouple, userHasDirectEntitlement } from "./access";
import { assertNoPendingAccountDeletion } from "./accountDeletion";
import { getOrCreateCoupleDayAt } from "./coupleDays";
import { insertDailyAnswer } from "./dailyAnswers";
import {
  DAILY_QUESTION_SLOTS,
  QuestionContentReader,
  ensureDailyChallengeSlots,
  insertDailyQuestionInstance,
  loadAnsweredQuestions,
  pickQuestionVersion,
} from "./dailyQuestions";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, orNull, requireByUuid, withUpdatedAt } from "./db";
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
 * exists once the partner accepts the invite, so the start date, the first answers, and the
 * first widget drawing wait in `first_day_drafts`, and `accept_pairing_invite` turns them into
 * couple content with `materializeFirstDayDrafts`.
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
    question_version_ids: [],
    answers: [],
    created_at: now,
    updated_at: now,
  });
  return (await ctx.db.get(docId))!;
}

/** Before pairing there is no partner to pick, and the first day offers written answers only. */
function firstDayAnswerKinds(kinds: string[]): boolean {
  return kinds.includes("text") && !kinds.includes("partner_choice");
}

/** One version per daily slot, each of a different question, by the daily selection rules. */
export async function pickFirstDayQuestionVersions(ctx: ReaderCtx, userId: string): Promise<string[]> {
  const answered = await loadAnsweredQuestions(ctx, userId);
  const excludedQuestionIds = new Set<string>();
  const versionIds: string[] = [];
  for (let slot = 1; slot <= DAILY_QUESTION_SLOTS; slot += 1) {
    const versionId = await pickQuestionVersion(ctx, userId, {
      excludedQuestionIds,
      answered,
      acceptsKinds: firstDayAnswerKinds,
    });
    versionIds.push(versionId);
    excludedQuestionIds.add((await requireByUuid(ctx, "question_versions", versionId)).question_id);
  }
  return versionIds;
}

/** The `get_first_day_draft` result. */
export async function firstDayDraftJson(ctx: ReaderCtx, draft: Draft) {
  const reader = new QuestionContentReader(ctx);
  const questions = [];
  for (const [index, versionId] of draft.question_version_ids.entries()) {
    const content = await reader.get(versionId);
    if (!content) continue;
    const answer = draft.answers.find((item) => item.question_version_id === versionId);
    questions.push({
      slot_number: index + 1,
      question_version_id: versionId,
      question_key: content.question.key,
      prompt_en: content.en.prompt,
      prompt_nb: content.nb.prompt,
      short_prompt_en: content.en.short_prompt,
      short_prompt_nb: content.nb.short_prompt,
      answer_text: answer?.body ?? null,
      answered_at: answer?.answered_at ?? null,
    });
  }
  return {
    started_on: orNull(draft.started_on),
    questions,
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

  if (drafts.some((draft) => draft.question_version_ids.length > 0)) {
    const dayId = await getOrCreateCoupleDayAt(ctx, input.coupleId, now);
    const seeded: { draft: Draft; versionId: string; instanceId: string }[] = [];
    for (const draft of drafts) {
      for (const [index, versionId] of draft.question_version_ids.entries()) {
        if (!(await getByUuid(ctx, "question_versions", versionId))) continue;
        const instanceId = await insertDailyQuestionInstance(ctx, {
          couple_day_id: dayId,
          question_version_id: versionId,
          seeded_for_user_id: draft.user_id,
          slot_number: index + 1,
        });
        seeded.push({ draft, versionId, instanceId });
      }
    }
    // Fills the remaining slots and the challenge rows, which the answers below complete.
    await ensureDailyChallengeSlots(ctx, dayId);
    const day = (await getByUuid(ctx, "couple_days", dayId))!;
    const reader = new QuestionContentReader(ctx);
    for (const { draft, versionId, instanceId } of seeded) {
      const answer = draft.answers.find((item) => item.question_version_id === versionId);
      if (!answer || !(await reader.get(versionId))?.answer_kinds.includes("text")) continue;
      await insertDailyAnswer(ctx, {
        userId: draft.user_id,
        instance: (await getByUuid(ctx, "daily_question_instances", instanceId))!,
        day,
        answerId: newUuid(),
        textBody: answer.body,
        selectedPartnerUserId: null,
        mediaAssetIds: [],
        notifyPartner: false,
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
