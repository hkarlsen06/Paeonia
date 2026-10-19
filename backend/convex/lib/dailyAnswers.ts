import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, isActiveCoupleMember } from "./access";
import { runClientOperation } from "./clientOperations";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { checkViolation, fail, uniqueViolation } from "./errors";
import { newUuid, uuidArg } from "./ids";
import { jsonbByteLength, jsonbText } from "./json";
import { enqueuePartnerAnsweredNotification, enqueuePartnerNotification } from "./notifications";
import { tombstoneReportTargets } from "./reports";
import { applyCoupleActivity } from "./streaks";
import { nowIso } from "./time";
import {
  DAILY_QUESTION_SLOTS,
  ensureDailyChallengeSlots,
  instanceDay,
  isTopicInstance,
  isVisibleAnswer,
  visibleAnswersOf,
} from "./dailyQuestions";

/**
 * Daily answers: reveal rules, read models, and the answer writes. The reveal rule
 * (`internal.can_view_daily_answer`) used to live in RLS policies, so every read
 * here applies it: an answer is visible to its author, and to the partner only
 * after the partner has a visible answer on the same instance.
 */

export type DailyAnswerDetailRow = {
  couple_day_id: string;
  instance_id: string;
  seeded_for_user_id: string;
  slot_number: number;
  answer_user_id: string;
  answer_id: string;
  answered_at: string;
  is_own_answer: boolean;
  can_view_answer: boolean;
  text_body: string | null;
  selected_user_id: string | null;
  /** The option a "pick one of two" answer picked. */
  selected_option: "a" | "b" | null;
  media_asset_ids: string[];
};

/** Remembers `can_access_couple_content` for one viewer during a read. */
export class CoupleAccessCache {
  private cache = new Map<string, boolean>();

  constructor(
    private ctx: ReaderCtx,
    readonly userId: string,
  ) {}

  async canAccess(coupleId: string): Promise<boolean> {
    let allowed = this.cache.get(coupleId);
    if (allowed === undefined) {
      allowed = await canAccessCoupleContent(this.ctx, this.userId, coupleId);
      this.cache.set(coupleId, allowed);
    }
    return allowed;
  }
}

async function viewerHasVisibleAnswer(ctx: ReaderCtx, userId: string, instanceId: string): Promise<boolean> {
  const answer = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId).eq("user_id", userId))
    .unique();
  return isVisibleAnswer(answer);
}

/** Port of `internal.can_view_daily_answer` for an answer row the caller already loaded. */
export async function canViewDailyAnswer(
  ctx: ReaderCtx,
  access: CoupleAccessCache,
  answer: Doc<"daily_question_answers">,
  day: Doc<"couple_days">,
): Promise<boolean> {
  if (!isVisibleAnswer(answer) || !(await access.canAccess(day.couple_id))) {
    return false;
  }
  return answer.user_id === access.userId || (await viewerHasVisibleAnswer(ctx, access.userId, answer.instance_id));
}

async function visibleMediaAssetIds(ctx: ReaderCtx, answerId: string): Promise<string[]> {
  const links = await ctx.db
    .query("daily_answer_media")
    .withIndex("by_answer_id_sort_order", (q) => q.eq("answer_id", answerId))
    .collect();
  const ids: string[] = [];
  for (const link of links) {
    const asset = await getByUuid(ctx, "media_assets", link.media_asset_id);
    if (
      asset &&
      asset.upload_status === "finalized" &&
      asset.storage_delete_status === "none" &&
      asset.moderation_status === "visible" &&
      asset.deleted_at === undefined
    ) {
      ids.push(asset.id);
    }
  }
  return ids;
}

export async function detailRow(
  ctx: ReaderCtx,
  userId: string,
  day: Doc<"couple_days">,
  instance: Doc<"daily_question_instances">,
  answer: Doc<"daily_question_answers">,
  canView: boolean,
): Promise<DailyAnswerDetailRow> {
  let textBody: string | null = null;
  let selectedUserId: string | null = null;
  let selectedOption: "a" | "b" | null = null;
  let mediaAssetIds: string[] = [];
  if (canView) {
    const text = await ctx.db
      .query("daily_answer_text")
      .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
      .unique();
    const choice = await ctx.db
      .query("daily_answer_partner_choice")
      .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
      .unique();
    const option = await ctx.db
      .query("daily_answer_option_choice")
      .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
      .unique();
    textBody = text?.body ?? null;
    selectedUserId = choice?.selected_user_id ?? null;
    selectedOption = option?.option ?? null;
    mediaAssetIds = await visibleMediaAssetIds(ctx, answer.id);
  }
  return {
    couple_day_id: day.id,
    instance_id: instance.id,
    seeded_for_user_id: instance.seeded_for_user_id,
    slot_number: instance.slot_number,
    answer_user_id: answer.user_id,
    answer_id: answer.id,
    answered_at: answer.created_at,
    is_own_answer: answer.user_id === userId,
    can_view_answer: canView,
    text_body: textBody,
    selected_user_id: selectedUserId,
    selected_option: selectedOption,
    media_asset_ids: mediaAssetIds,
  };
}

function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

async function instancesOfDay(ctx: ReaderCtx, coupleDayId: string): Promise<Doc<"daily_question_instances">[]> {
  return await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) => q.eq("couple_day_id", coupleDayId))
    .collect();
}

/** Port of `internal.get_daily_answer_details`: every visible answer on one couple day, with the reveal rule applied. */
export async function getDailyAnswerDetails(
  ctx: ReaderCtx,
  userId: string,
  coupleDayId: string,
): Promise<DailyAnswerDetailRow[]> {
  const day = await getByUuid(ctx, "couple_days", coupleDayId);
  const access = new CoupleAccessCache(ctx, userId);
  if (!day || !(await access.canAccess(day.couple_id))) return [];
  const rows: DailyAnswerDetailRow[] = [];
  for (const instance of await instancesOfDay(ctx, day.id)) {
    for (const answer of await visibleAnswersOf(ctx, instance.id)) {
      rows.push(await detailRow(ctx, userId, day, instance, answer, await canViewDailyAnswer(ctx, access, answer, day)));
    }
  }
  return rows.sort((a, b) => a.slot_number - b.slot_number || compareStrings(a.answered_at, b.answered_at));
}

/**
 * Port of `internal.get_daily_answer_details_for_context`. Rows come from the given
 * couple only. Content shows when the answer is the viewer's own or the viewer has
 * answered the same instance.
 */
export async function getDailyAnswerDetailsForContext(
  ctx: ReaderCtx,
  coupleDayIds: string[],
  userId: string,
  coupleId: string,
): Promise<DailyAnswerDetailRow[]> {
  const rows: { row: DailyAnswerDetailRow; startsAt: string }[] = [];
  for (const dayId of new Set(coupleDayIds)) {
    const day = await getByUuid(ctx, "couple_days", dayId);
    if (!day || day.couple_id !== coupleId) continue;
    for (const instance of await instancesOfDay(ctx, day.id)) {
      const answers = await visibleAnswersOf(ctx, instance.id);
      const viewerAnswered = answers.some((answer) => answer.user_id === userId);
      for (const answer of answers) {
        const canView = answer.user_id === userId || viewerAnswered;
        rows.push({ row: await detailRow(ctx, userId, day, instance, answer, canView), startsAt: day.starts_at });
      }
    }
  }
  return rows
    .sort(
      (a, b) =>
        compareStrings(b.startsAt, a.startsAt) ||
        a.row.slot_number - b.row.slot_number ||
        compareStrings(a.row.answered_at, b.row.answered_at) ||
        compareStrings(a.row.answer_id, b.row.answer_id),
    )
    .map((item) => item.row);
}

/** The instances the viewer has a visible answer on, in the given couple, with their couple day. */
async function viewerInstances(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
): Promise<{ day: Doc<"couple_days">; instance: Doc<"daily_question_instances"> }[]> {
  const ownAnswers = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_user_id_created_at", (q) => q.eq("user_id", userId))
    .collect();
  const found: { day: Doc<"couple_days">; instance: Doc<"daily_question_instances"> }[] = [];
  for (const answer of ownAnswers) {
    if (!isVisibleAnswer(answer)) continue;
    const instance = await getByUuid(ctx, "daily_question_instances", answer.instance_id);
    // Topic answers live only in their topic, so the daily history leaves them out.
    if (!instance || isTopicInstance(instance)) continue;
    const day = await getByUuid(ctx, "couple_days", instance.couple_day_id);
    if (day && day.couple_id === coupleId) {
      found.push({ day, instance });
    }
  }
  return found;
}

/** Port of `internal.get_daily_answer_history_details`: both partners' answers on every instance the viewer answered. */
export async function getDailyAnswerHistoryDetails(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
): Promise<DailyAnswerDetailRow[]> {
  const access = new CoupleAccessCache(ctx, userId);
  if (!(await access.canAccess(coupleId))) return [];
  const rows: { row: DailyAnswerDetailRow; startsAt: string }[] = [];
  for (const { day, instance } of await viewerInstances(ctx, userId, coupleId)) {
    for (const answer of await visibleAnswersOf(ctx, instance.id)) {
      rows.push({ row: await detailRow(ctx, userId, day, instance, answer, await canViewDailyAnswer(ctx, access, answer, day)), startsAt: day.starts_at });
    }
  }
  return rows
    .sort(
      (a, b) =>
        compareStrings(b.startsAt, a.startsAt) ||
        a.row.slot_number - b.row.slot_number ||
        compareStrings(a.row.answered_at, b.row.answered_at),
    )
    .map((item) => item.row);
}

// ---- writes ----

/** `btrim(x)`: removes spaces only, not other whitespace. */
function btrim(value: string): string {
  return value.replace(/^ +| +$/g, "");
}

function charLength(value: string): number {
  return Array.from(value).length;
}

/** `payload ->> key` for a parsed jsonb value: missing and null give '' (after `coalesce`). */
function payloadText(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "object") return jsonbText(value);
  return String(value);
}

async function answerKindsOf(ctx: ReaderCtx, versionId: string): Promise<string[]> {
  const rows = await ctx.db
    .query("question_answer_kinds")
    .withIndex("by_question_version_id_answer_kind", (q) => q.eq("question_version_id", versionId))
    .collect();
  return rows.map((row) => row.answer_kind).sort();
}

type AnswerContext = {
  instance: Doc<"daily_question_instances">;
  day: Doc<"couple_days">;
};

async function instanceContext(
  ctx: ReaderCtx,
  instanceId: string,
  shuffledMessage: string,
): Promise<AnswerContext> {
  const instance = await getByUuid(ctx, "daily_question_instances", instanceId);
  if (!instance) {
    return fail("22023", "daily question instance was not found");
  }
  if (instance.status === "shuffled") {
    return fail("23514", shuffledMessage);
  }
  const day = (await instanceDay(ctx, instance))!;
  return { instance, day };
}

/** Ports of the `assert_daily_answer_text_allowed` and `assert_daily_answer_partner_choice_allowed` triggers, then the insert. */
async function upsertAnswerText(ctx: WriterCtx, answer: Doc<"daily_question_answers">, instance: Doc<"daily_question_instances">, body: string) {
  if (!(await answerKindsOf(ctx, instance.question_version_id)).includes("text")) {
    fail("23514", "text answers are not allowed for this question");
  }
  const existing = await ctx.db
    .query("daily_answer_text")
    .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
    .unique();
  if (existing) {
    await ctx.db.patch(existing._id, { body });
  } else {
    await ctx.db.insert("daily_answer_text", { answer_id: answer.id, body });
  }
}

async function upsertAnswerPartnerChoice(
  ctx: WriterCtx,
  answer: Doc<"daily_question_answers">,
  instance: Doc<"daily_question_instances">,
  selectedUserId: string,
) {
  if (!(await answerKindsOf(ctx, instance.question_version_id)).includes("partner_choice")) {
    fail("23514", "partner choice answers are not allowed for this question");
  }
  if (!(await isActiveCoupleMember(ctx, selectedUserId, instance.couple_id))) {
    fail("23514", "partner choice must select an active couple member");
  }
  const existing = await ctx.db
    .query("daily_answer_partner_choice")
    .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
    .unique();
  if (existing) {
    await ctx.db.patch(existing._id, { selected_user_id: selectedUserId });
  } else {
    await ctx.db.insert("daily_answer_partner_choice", { answer_id: answer.id, selected_user_id: selectedUserId });
  }
}

/** Port of the `assert_daily_answer_media_allowed` trigger, then the insert. */
async function insertAnswerMedia(
  ctx: WriterCtx,
  answer: Doc<"daily_question_answers">,
  instance: Doc<"daily_question_instances">,
  mediaAssetId: string,
  sortOrder: number,
) {
  const asset = await getByUuid(ctx, "media_assets", mediaAssetId);
  const requiredKind = asset?.media_type === "image" ? "photo" : asset?.media_type === "voice" ? "voice" : null;
  if (
    !asset ||
    requiredKind === null ||
    asset.owner_user_id !== answer.user_id ||
    asset.couple_id !== instance.couple_id ||
    asset.reserved_parent_kind !== "daily_answer_media" ||
    asset.reserved_parent_id !== answer.id ||
    (asset.upload_purpose !== "daily_answer_media" && asset.upload_purpose !== "voice_note") ||
    asset.upload_status !== "finalized" ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    fail("23514", "daily answer media asset is not usable for this answer");
  }
  if (!(await answerKindsOf(ctx, instance.question_version_id)).includes(requiredKind)) {
    fail("23514", "media answer kind is not allowed for this question");
  }
  if (sortOrder < 1 || sortOrder > 10) {
    checkViolation("daily_answer_media", "daily_answer_media_sort_order_check");
  }
  const duplicate = await ctx.db
    .query("daily_answer_media")
    .withIndex("by_answer_id_media_asset_id", (q) => q.eq("answer_id", answer.id).eq("media_asset_id", mediaAssetId))
    .first();
  if (duplicate) {
    uniqueViolation("daily_answer_media_primary_key");
  }
  await ctx.db.insert("daily_answer_media", { answer_id: answer.id, media_asset_id: mediaAssetId, sort_order: sortOrder });
}

/**
 * Port of the `handle_daily_challenge_completed` trigger. Call after a user's last
 * own slot is answered. Counts the day for the streak and, with `notifyPartner`, tells the partner once.
 */
async function completeDailyChallenge(
  ctx: WriterCtx,
  coupleDayId: string,
  userId: string,
  notifyPartner: boolean,
): Promise<void> {
  const challenge = await ctx.db
    .query("daily_challenges")
    .withIndex("by_couple_day_id_user_id", (q) => q.eq("couple_day_id", coupleDayId).eq("user_id", userId))
    .unique();
  if (!challenge || challenge.completed_at !== undefined) return;
  const completedAt = nowIso();
  const day = await getByUuid(ctx, "couple_days", coupleDayId);
  let partnerNotifiedAt: string | undefined;
  if (day) {
    const dedupeKey = `daily_challenge_completed:${coupleDayId}:${userId}`;
    await applyCoupleActivity(ctx, {
      couple_id: day.couple_id,
      user_id: userId,
      couple_day_id: coupleDayId,
      activity_kind: "daily_challenge_completed",
      occurred_at: completedAt,
      dedupe_key: dedupeKey,
      metadata: { source: "daily_challenge" },
    });
    if (notifyPartner) {
      await enqueuePartnerNotification(ctx, {
        couple_id: day.couple_id,
        actor_user_id: userId,
        kind: "daily_challenge_completed",
        payload: {
          type: "daily_challenge_completed",
          couple_id: day.couple_id,
          couple_day_id: coupleDayId,
          actor_user_id: userId,
          route: "daily",
          deeplink: `paeonia://daily/today?coupleDayId=${coupleDayId}`,
        },
        dedupe_key: dedupeKey,
        redaction_level: "private",
        apns_push_type: "alert",
        apns_collapse_id: `daily:${day.couple_id}`,
        scheduled_for: completedAt,
      });
      partnerNotifiedAt = completedAt;
    }
  }
  await ctx.db.patch(challenge._id, { completed_at: completedAt, partner_notified_at: partnerNotifiedAt });
}

export type ClientOperationArgs = {
  clientOperationId: string;
  clientId: string;
  clientSequence: number;
  localCreatedAt: string;
};

const MAX_ANSWER_PAYLOAD_BYTES = 16_384;

/** The object check and size cap that run before an answer's client operation. */
export function assertAnswerPayloadShape(payload: unknown): Record<string, unknown> {
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    fail("23514", "answer payload must be an object");
  }
  // Text is at most 2000 characters (8000 bytes) and the rest are a few ids, so a bigger body is not an answer.
  if (jsonbByteLength(payload) > MAX_ANSWER_PAYLOAD_BYTES) {
    fail("23514", "answer payload is too large");
  }
  return payload as Record<string, unknown>;
}

export type ParsedAnswer = {
  answerId: string;
  textBody: string;
  selectedPartnerUserId: string | null;
  selectedOption: "a" | "b" | null;
  mediaAssetIds: string[];
};

/**
 * Checks an answer's parts against the instance's answer kinds and couple, and that the user
 * has no answer on the instance yet. Daily and topic answers share it.
 */
export async function parseAnswerPayload(
  ctx: WriterCtx,
  userId: string,
  instance: Doc<"daily_question_instances">,
  body: Record<string, unknown>,
): Promise<ParsedAnswer> {
  const allowedKinds = await answerKindsOf(ctx, instance.question_version_id);
  const providedKinds: string[] = [];

  const textBody = btrim(payloadText(body.text));
  if (textBody !== "") {
    if (charLength(textBody) > 2000) {
      fail("23514", "answer text is too long");
    }
    providedKinds.push("text");
  }

  const partnerChoiceText = payloadText(body.partner_choice_user_id);
  const selectedPartnerUserId = partnerChoiceText === "" ? null : uuidArg(partnerChoiceText);
  if (selectedPartnerUserId !== null) {
    providedKinds.push("partner_choice");
  }

  const optionText = payloadText(body.option_choice);
  if (optionText !== "" && optionText !== "a" && optionText !== "b") {
    fail("23514", "option choice must be a or b");
  }
  const selectedOption = optionText === "" ? null : (optionText as "a" | "b");
  if (selectedOption !== null) {
    providedKinds.push("either_or");
  }

  if ("media_asset_ids" in body && !Array.isArray(body.media_asset_ids)) {
    fail("23514", "media_asset_ids must be an array");
  }
  const mediaAssetIds: string[] = [];
  for (const item of (body.media_asset_ids as unknown[] | undefined) ?? []) {
    const mediaAssetId = item === null ? null : uuidArg(payloadText(item));
    const asset = mediaAssetId === null ? null : await getByUuid(ctx, "media_assets", mediaAssetId);
    const mediaKind = asset?.media_type === "image" ? "photo" : asset?.media_type === "voice" ? "voice" : null;
    if (
      !asset ||
      mediaKind === null ||
      asset.owner_user_id !== userId ||
      asset.couple_id !== instance.couple_id ||
      asset.reserved_parent_kind !== "daily_answer_media" ||
      asset.upload_status !== "finalized" ||
      asset.storage_delete_status !== "none" ||
      asset.moderation_status !== "visible" ||
      asset.deleted_at !== undefined
    ) {
      fail("23514", "daily answer media asset is not usable");
    }
    mediaAssetIds.push(asset.id);
    if (!providedKinds.includes(mediaKind)) {
      providedKinds.push(mediaKind);
    }
  }

  if (providedKinds.length === 0) {
    fail("23514", "answer payload must include at least one answer kind");
  }
  for (const kind of providedKinds) {
    if (!allowedKinds.includes(kind)) {
      fail("23514", "answer kind is not allowed for this question");
    }
  }
  // A "pick one of two" answer always picks. The why line on its own is not an answer.
  if (allowedKinds.includes("either_or") && selectedOption === null) {
    fail("23514", "option choice is required");
  }

  const answerIdText = payloadText(body.answer_id);
  const answerId = answerIdText === "" ? newUuid() : uuidArg(answerIdText);
  if (await getByUuid(ctx, "daily_question_answers", answerId)) {
    uniqueViolation("daily_question_answers_pkey");
  }
  const existingOwn = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", userId))
    .first();
  if (existingOwn) {
    uniqueViolation("daily_question_answers_instance_user_unique");
  }
  return { answerId, textBody, selectedPartnerUserId, selectedOption, mediaAssetIds };
}

/** Port of `internal.submit_daily_answer`. Returns the answer id. */
export async function submitDailyAnswer(
  ctx: WriterCtx,
  userId: string,
  instanceId: string,
  payload: unknown,
  operation: ClientOperationArgs,
): Promise<string> {
  const body = assertAnswerPayloadShape(payload);

  const result = await runClientOperation(
    ctx,
    userId,
    {
      client_operation_id: operation.clientOperationId,
      client_id: operation.clientId,
      client_sequence: operation.clientSequence,
      local_created_at: operation.localCreatedAt,
      operation_kind: "submit_daily_answer",
      idempotency_scope: "daily_challenges",
      request: { kind: "submit_daily_answer", instance_id: instanceId, payload },
    },
    async () => {
      const { instance, day } = await instanceContext(ctx, instanceId, "shuffled daily questions cannot be answered");
      if (isTopicInstance(instance)) {
        fail("23514", "topic questions are answered with submit_topic_answer");
      }

      if (
        operation.localCreatedAt < day.starts_at ||
        (userId === instance.seeded_for_user_id && operation.localCreatedAt >= day.ends_at)
      ) {
        fail("23514", "daily answer timestamp is outside the question day");
      }
      if (!(await canAccessCoupleContent(ctx, userId, day.couple_id))) {
        fail("42501", "active entitled couple access is required");
      }
      if (!(await isActiveCoupleMember(ctx, userId, day.couple_id))) {
        fail("42501", "answer user must be an active couple member");
      }
      if (userId !== instance.seeded_for_user_id) {
        const seededAnswered = (await visibleAnswersOf(ctx, instance.id)).some(
          (answer) => answer.user_id === instance.seeded_for_user_id,
        );
        if (!seededAnswered) {
          fail("42501", "partner-seeded questions can be answered after your partner answers");
        }
      }

      const parsed = await parseAnswerPayload(ctx, userId, instance, body);
      // assert_daily_question_answer_member: the author is an active member (checked above).
      await insertDailyAnswer(ctx, { userId, instance, ...parsed, notifyPartner: true });
      return { answer_id: parsed.answerId };
    },
  );
  return result.answer_id;
}

/**
 * Writes a checked answer: the answer row and its parts, the user's own instance marked
 * answered, and the day completed once every own slot is answered. The caller has checked
 * access, the answer kinds, and that the user has no answer on the instance yet.
 * `notifyPartner: false` keeps the streak effects but sends the partner no push.
 */
export async function insertDailyAnswer(
  ctx: WriterCtx,
  input: {
    userId: string;
    instance: Doc<"daily_question_instances">;
    answerId: string;
    textBody: string;
    selectedPartnerUserId: string | null;
    selectedOption: "a" | "b" | null;
    mediaAssetIds: string[];
    notifyPartner: boolean;
  },
): Promise<void> {
  const { userId, instance } = input;
  const now = nowIso();
  const answerDocId = await ctx.db.insert("daily_question_answers", {
    id: input.answerId,
    instance_id: instance.id,
    user_id: userId,
    created_at: now,
    updated_at: now,
    moderation_status: "visible",
  });
  const answer = (await ctx.db.get(answerDocId))!;
  if (input.notifyPartner) {
    await enqueuePartnerAnsweredNotification(ctx, answer);
  }

  if (input.textBody !== "") {
    await upsertAnswerText(ctx, answer, instance, input.textBody);
  }
  if (input.selectedPartnerUserId !== null) {
    await upsertAnswerPartnerChoice(ctx, answer, instance, input.selectedPartnerUserId);
  }
  if (input.selectedOption !== null) {
    await ctx.db.insert("daily_answer_option_choice", { answer_id: answer.id, option: input.selectedOption });
  }
  for (const [index, mediaAssetId] of input.mediaAssetIds.entries()) {
    await insertAnswerMedia(ctx, answer, instance, mediaAssetId, index + 1);
  }

  if (userId === instance.seeded_for_user_id) {
    if (instance.status === "active") {
      await ctx.db.patch(instance._id, { status: "answered" });
    }
    // A topic instance has no couple day, so a topic answer never completes the daily challenge.
    const coupleDayId = instance.couple_day_id;
    if (coupleDayId === undefined) return;
    const ownInstances = await ctx.db
      .query("daily_question_instances")
      .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) =>
        q.eq("couple_day_id", coupleDayId).eq("seeded_for_user_id", userId).eq("status", "answered"),
      )
      .collect();
    if (ownInstances.length === DAILY_QUESTION_SLOTS) {
      await completeDailyChallenge(ctx, coupleDayId, userId, input.notifyPartner);
    }
  }
}

type EditKind = "text" | "partner_choice";

/** Shared body of `internal.update_daily_answer_text` and `internal.update_daily_answer_partner_choice`. */
async function editDailyAnswer(
  ctx: WriterCtx,
  userId: string,
  instanceId: string,
  operation: ClientOperationArgs,
  edit: { kind: EditKind; operationKind: string; request: unknown; text?: string; selectedUserId?: string },
): Promise<string> {
  const result = await runClientOperation(
    ctx,
    userId,
    {
      client_operation_id: operation.clientOperationId,
      client_id: operation.clientId,
      client_sequence: operation.clientSequence,
      local_created_at: operation.localCreatedAt,
      operation_kind: edit.operationKind,
      idempotency_scope: "daily_challenges",
      request: edit.request,
    },
    async () => {
      const { instance, day } = await instanceContext(ctx, instanceId, "shuffled daily questions cannot be edited");
      // A topic question has no day to end, so its answer can change until the partner answers.
      if (
        !isTopicInstance(instance) &&
        (operation.localCreatedAt < day.starts_at || operation.localCreatedAt >= day.ends_at)
      ) {
        fail("23514", "daily answer timestamp is outside the question day");
      }
      if (!(await canAccessCoupleContent(ctx, userId, day.couple_id))) {
        fail("42501", "active entitled couple access is required");
      }
      const own = await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", userId))
        .unique();
      if (!own || own.deleted_at !== undefined) {
        fail("22023", "there is no answer to edit");
      }
      // Once the partner has answered, the answer is revealed and can no longer change.
      const partnerAnswered = (await visibleAnswersOf(ctx, instance.id)).some((answer) => answer.user_id !== userId);
      if (partnerAnswered) {
        fail("23514", "answers cannot be edited after your partner has answered");
      }
      if (!(await answerKindsOf(ctx, instance.question_version_id)).includes(edit.kind)) {
        fail("23514", "answer kind is not allowed for this question");
      }
      if (edit.kind === "text") {
        await upsertAnswerText(ctx, own, instance, edit.text!);
      } else {
        await upsertAnswerPartnerChoice(ctx, own, instance, edit.selectedUserId!);
      }
      // Restate the answer's effective time so "answered at" follows the edit.
      await ctx.db.patch(own._id, withUpdatedAt({ created_at: nowIso() }));
      return { answer_id: own.id };
    },
  );
  return result.answer_id;
}

/** Port of `internal.update_daily_answer_text`. */
export async function updateDailyAnswerText(
  ctx: WriterCtx,
  userId: string,
  instanceId: string,
  text: string | null | undefined,
  operation: ClientOperationArgs,
): Promise<string> {
  const body = btrim(text ?? "");
  if (body === "") {
    fail("23514", "answer text is required");
  }
  if (charLength(body) > 2000) {
    fail("23514", "answer text is too long");
  }
  return await editDailyAnswer(ctx, userId, instanceId, operation, {
    kind: "text",
    operationKind: "update_daily_answer_text",
    request: { kind: "update_daily_answer_text", instance_id: instanceId, text: body },
    text: body,
  });
}

/** Port of `internal.update_daily_answer_partner_choice`. */
export async function updateDailyAnswerPartnerChoice(
  ctx: WriterCtx,
  userId: string,
  instanceId: string,
  selectedUserId: string | null | undefined,
  operation: ClientOperationArgs,
): Promise<string> {
  if (!selectedUserId) {
    fail("23514", "partner choice selection is required");
  }
  return await editDailyAnswer(ctx, userId, instanceId, operation, {
    kind: "partner_choice",
    operationKind: "update_daily_answer_partner_choice",
    request: { kind: "update_daily_answer_partner_choice", instance_id: instanceId, selected_user_id: selectedUserId },
    selectedUserId,
  });
}

/** Port of `public.reset_daily_challenge_for_testing`. Returns how many couple days were reset. */
export async function resetDailyChallengeForCouple(ctx: WriterCtx, coupleId: string): Promise<number> {
  const now = nowIso();
  const days = (
    await ctx.db
      .query("couple_days")
      .withIndex("by_couple_id_starts_at", (q) => q.eq("couple_id", coupleId).lte("starts_at", now))
      .collect()
  ).filter((day) => now < day.ends_at);

  for (const day of days) {
    const instances = await ctx.db
      .query("daily_question_instances")
      .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) => q.eq("couple_day_id", day.id))
      .collect();

    // 1. The chats of the day's questions. A chat spans every day its question came back on,
    // so this test reset removes all of it.
    for (const instance of instances) {
      const questionId = (await getByUuid(ctx, "question_versions", instance.question_version_id))?.question_id;
      const link = questionId
        ? await ctx.db
            .query("daily_question_threads")
            .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId).eq("question_id", questionId))
            .unique()
        : null;
      if (!link) continue;
      const messages = await ctx.db
        .query("thread_messages")
        .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", link.thread_id))
        .collect();
      for (const message of messages) {
        const media = await ctx.db
          .query("thread_message_media")
          .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", message.id))
          .collect();
        for (const item of media) {
          await tombstoneReportTargets(ctx, "thread_message_media", {
            message_id: item.message_id,
            media_asset_id: item.media_asset_id,
          });
          await ctx.db.delete(item._id);
        }
        await tombstoneReportTargets(ctx, "thread_message", message.id);
        await ctx.db.delete(message._id);
      }
      await ctx.db.delete(link._id);
      const thread = await getByUuid(ctx, "conversation_threads", link.thread_id);
      if (thread) await ctx.db.delete(thread._id);
    }

    // 2. Every answer and its detail rows. Linked media assets stay in place.
    for (const instance of instances) {
      const answers = await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id))
        .collect();
      for (const answer of answers) {
        for (const link of await ctx.db
          .query("daily_answer_media")
          .withIndex("by_answer_id_sort_order", (q) => q.eq("answer_id", answer.id))
          .collect()) {
          await ctx.db.delete(link._id);
        }
        for (const row of await ctx.db
          .query("daily_answer_text")
          .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
          .collect()) {
          await ctx.db.delete(row._id);
        }
        for (const row of await ctx.db
          .query("daily_answer_partner_choice")
          .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
          .collect()) {
          await ctx.db.delete(row._id);
        }
        for (const row of await ctx.db
          .query("daily_answer_option_choice")
          .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
          .collect()) {
          await ctx.db.delete(row._id);
        }
        await tombstoneReportTargets(ctx, "daily_answer", answer.id);
        await ctx.db.delete(answer._id);
      }
    }

    // 3. The day's skips.
    for (const shuffle of await ctx.db
      .query("daily_question_shuffles")
      .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
      .collect()) {
      if (shuffle.couple_day_id === day.id) await ctx.db.delete(shuffle._id);
    }

    // 4. The instances and who has seen their answers. Replacement links point inside the
    // day, so every row goes together.
    for (const instance of instances) {
      for (const state of await ctx.db
        .query("daily_answer_seen_states")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id))
        .collect()) {
        await ctx.db.delete(state._id);
      }
      await ctx.db.delete(instance._id);
    }

    // 5. Clear completion so the card returns to its active state.
    for (const challenge of await ctx.db
      .query("daily_challenges")
      .withIndex("by_couple_day_id_user_id", (q) => q.eq("couple_day_id", day.id))
      .collect()) {
      await ctx.db.patch(challenge._id, { completed_at: undefined, partner_notified_at: undefined });
    }

    // 6. Fresh slots.
    await ensureDailyChallengeSlots(ctx, day.id);
  }
  return days.length;
}
