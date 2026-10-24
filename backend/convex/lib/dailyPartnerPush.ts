import type { Doc } from "../_generated/dataModel";
import { listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import { isLive, visibleAnswersOf } from "./dailyQuestions";
import { enqueueNotificationForUser, notificationAlertBody, notificationAlertTitle } from "./notifications";
import { addMs, nowIso } from "./time";

/**
 * The pushes a partner's daily answer sends. When the partner answers a question the recipient
 * has not answered yet, "answered today's question" (`daily_challenge_completed`). When the
 * partner answers one the recipient already answered, "answered too" (`partner_answered`),
 * since both answers are ready to see. A late answer to an earlier day and today's answer can
 * land within a minute, so each recipient has one lane: the first answer queues a push
 * `DAILY_PARTNER_PUSH_DELAY_SECONDS` out, and every answer before it is due adds to that push
 * instead of queueing another. When it is due, `resolveDailyPartnerPush` picks the kind and the
 * copy from what still waits for the recipient.
 */

export const DAILY_PARTNER_PUSH_DELAY_SECONDS = 75;

const DAILY_PARTNER_PUSH_KINDS = ["partner_answered", "daily_challenge_completed"] as const;
export type DailyPartnerPushKind = (typeof DAILY_PARTNER_PUSH_KINDS)[number];

/** A lane collects at most this many questions. That is more than one burst of answers needs. */
const MAX_LANE_INSTANCES = 20;

export function isDailyPartnerPushKind(kind: string): kind is DailyPartnerPushKind {
  return (DAILY_PARTNER_PUSH_KINDS as readonly string[]).includes(kind);
}

function idList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((id): id is string => typeof id === "string") : [];
}

/** The lane's questions live in the payload's `instance_ids`. */
function withInstance(payload: Record<string, unknown>, instanceId: string): Record<string, unknown> {
  const ids = idList(payload.instance_ids);
  return {
    ...payload,
    instance_ids: ids.includes(instanceId) || ids.length >= MAX_LANE_INSTANCES ? ids : [...ids, instanceId],
  };
}

const todayDeeplink = (coupleDayId: string) => `paeonia://daily/today?coupleDayId=${coupleDayId}`;
const revealDeeplink = (instanceId: string, coupleDayId: string) =>
  `paeonia://daily/reveal?instanceId=${instanceId}&coupleDayId=${coupleDayId}`;

/**
 * The recipient's lane rows that have not come due yet, one per device. A row that is due may be
 * sending already, so a later answer starts a new lane instead of changing it.
 */
async function openLaneRows(
  ctx: ReaderCtx,
  coupleId: string,
  recipientId: string,
  now: string,
): Promise<Doc<"notification_outbox">[]> {
  const rows = await ctx.db
    .query("notification_outbox")
    .withIndex("by_recipient_user_id_created_at", (q) =>
      q.eq("recipient_user_id", recipientId).gte("created_at", addMs(now, -2 * DAILY_PARTNER_PUSH_DELAY_SECONDS * 1000)),
    )
    .collect();
  return rows.filter(
    (row) =>
      isDailyPartnerPushKind(row.kind) &&
      row.sent_at === undefined &&
      row.failed_at === undefined &&
      row.scheduled_for > now &&
      (row.payload as Record<string, unknown>).couple_id === coupleId,
  );
}

/**
 * Call after inserting a daily answer. Adds the question to the partner's open lane, or opens
 * one. Queueing the lane's push again with its own dedupe key adds a row for a phone that signed
 * in since, and skips the phones that have one.
 */
export async function enqueueDailyPartnerPush(
  ctx: WriterCtx,
  answer: Doc<"daily_question_answers">,
  instance: Doc<"daily_question_instances">,
): Promise<void> {
  const coupleDayId = instance.couple_day_id;
  // Topic answers send the throttled `topics_waiting` push instead (lib/topics.ts).
  if (coupleDayId === undefined) return;
  const answers = await visibleAnswersOf(ctx, instance.id);
  const now = nowIso();
  for (const member of await listActiveMembers(ctx, instance.couple_id)) {
    if (member.user_id === answer.user_id) continue;
    const open = await openLaneRows(ctx, instance.couple_id, member.user_id, now);
    let kind: DailyPartnerPushKind;
    let scheduledFor: string;
    let payload: Record<string, unknown>;
    if (open.length > 0) {
      for (const row of open) {
        await ctx.db.patch(row._id, { payload: withInstance(row.payload as Record<string, unknown>, instance.id) });
      }
      kind = open[0].kind as DailyPartnerPushKind;
      scheduledFor = open[0].scheduled_for;
      payload = withInstance(open[0].payload as Record<string, unknown>, instance.id);
    } else {
      // The deeplink and copy are for the lane's first answer. The send replaces them with what fits by then.
      const recipientAnswered = answers.some((item) => item.user_id === member.user_id);
      kind = recipientAnswered ? "partner_answered" : "daily_challenge_completed";
      scheduledFor = addMs(now, DAILY_PARTNER_PUSH_DELAY_SECONDS * 1000);
      payload = {
        type: kind,
        couple_id: instance.couple_id,
        couple_day_id: coupleDayId,
        actor_user_id: answer.user_id,
        route: "daily",
        deeplink: recipientAnswered ? revealDeeplink(instance.id, coupleDayId) : todayDeeplink(coupleDayId),
        instance_ids: [instance.id],
      };
    }
    await enqueueNotificationForUser(ctx, {
      recipient_user_id: member.user_id,
      kind,
      payload,
      dedupe_key: `daily_partner:${member.user_id}:${scheduledFor}`,
      redaction_level: "private",
      apns_push_type: "alert",
      apns_collapse_id: `daily:${instance.couple_id}`,
      scheduled_for: scheduledFor,
    });
  }
}

export type ResolvedDailyPartnerPush =
  | {
      push: { kind: DailyPartnerPushKind; payload: Record<string, unknown>; title: string; body: string | undefined };
    }
  | { push: null; reason: "ineligible" | "out_of_date" };

function newestFirst(a: Doc<"daily_question_instances">, b: Doc<"daily_question_instances">): number {
  return a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0;
}

/**
 * Decides what a due lane row says. "Answered today's question" while a question the partner
 * answered still waits for the recipient's answer. Otherwise "answered too" for the answers the
 * recipient has not opened yet. Null when the recipient turned both kinds off, or already
 * answered and opened everything. `allows` is the recipient's preference check for a kind.
 */
export async function resolveDailyPartnerPush(
  ctx: ReaderCtx,
  row: Doc<"notification_outbox">,
  recipientId: string,
  locale: string | null | undefined,
  allows: (kind: DailyPartnerPushKind) => boolean,
): Promise<ResolvedDailyPartnerPush> {
  const lane = row.payload as Record<string, unknown>;
  const coupleId = typeof lane.couple_id === "string" ? lane.couple_id : null;
  const actorId = typeof lane.actor_user_id === "string" ? lane.actor_user_id : null;
  if (coupleId === null || actorId === null) return { push: null, reason: "out_of_date" };
  const answerAllowed = allows("daily_challenge_completed");
  const seeAllowed = allows("partner_answered");
  if (!answerAllowed && !seeAllowed) return { push: null, reason: "ineligible" };

  const toAnswer: Doc<"daily_question_instances">[] = [];
  const toSee: Doc<"daily_question_instances">[] = [];
  for (const id of idList(lane.instance_ids)) {
    const instance = await getByUuid(ctx, "daily_question_instances", id);
    if (!instance || !isLive(instance) || instance.couple_day_id === undefined || instance.couple_id !== coupleId) continue;
    const answers = await visibleAnswersOf(ctx, instance.id);
    if (!answers.some((answer) => answer.user_id === actorId)) continue;
    if (!answers.some((answer) => answer.user_id === recipientId)) {
      toAnswer.push(instance);
      continue;
    }
    // Both answered. The push waits until the recipient has seen the partner's answer,
    // whoever answered first: a reveal on the phone marks it seen before the push is due.
    const seen = await ctx.db
      .query("daily_answer_seen_states")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", recipientId))
      .unique();
    if (seen === null) toSee.push(instance);
  }

  const base = {
    couple_id: coupleId,
    actor_user_id: actorId,
    route: "daily",
    instance_ids: [...toAnswer, ...toSee].map((item) => item.id),
  };
  let kind: DailyPartnerPushKind;
  let payload: Record<string, unknown>;
  if (answerAllowed && toAnswer.length > 0) {
    kind = "daily_challenge_completed";
    const coupleDayId = [...toAnswer].sort(newestFirst)[0].couple_day_id!;
    payload = { ...base, type: kind, couple_day_id: coupleDayId, deeplink: todayDeeplink(coupleDayId) };
  } else if (seeAllowed && toSee.length > 0) {
    kind = "partner_answered";
    const [newest] = [...toSee].sort(newestFirst);
    const coupleDayId = newest.couple_day_id!;
    payload = {
      ...base,
      type: kind,
      couple_day_id: coupleDayId,
      question_count: toSee.length,
      deeplink: toSee.length === 1 ? revealDeeplink(newest.id, coupleDayId) : todayDeeplink(coupleDayId),
    };
  } else {
    return { push: null, reason: "out_of_date" };
  }
  return {
    push: {
      kind,
      payload,
      title: await notificationAlertTitle(ctx, recipientId, kind, payload, locale),
      body: notificationAlertBody(kind, payload, locale) ?? undefined,
    },
  };
}
