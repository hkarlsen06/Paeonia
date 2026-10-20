import type { Doc } from "../_generated/dataModel";
import { listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import { instancesOfDay, isLive, visibleAnswersOf } from "./dailyQuestions";
import { enqueueNotificationForUser, notificationAlertBody, notificationAlertTitle } from "./notifications";
import { addMs, nowIso } from "./time";

/**
 * The pushes a partner's daily answers send: "answered too" (`partner_answered`) and "finished
 * today's questions" (`daily_challenge_completed`). Answering both questions and the partner's two
 * happens within a minute or so, so each recipient has one lane: the first answer queues a push
 * `DAILY_PARTNER_PUSH_DELAY_SECONDS` out, and every answer before it is due adds to that push
 * instead of queueing another. When it is due, `resolveDailyPartnerPush` picks the kind and the
 * copy from what still waits for the recipient, so the push never asks them to answer questions
 * they already answered.
 */

export const DAILY_PARTNER_PUSH_DELAY_SECONDS = 75;

const DAILY_PARTNER_PUSH_KINDS = ["partner_answered", "daily_challenge_completed"] as const;
export type DailyPartnerPushKind = (typeof DAILY_PARTNER_PUSH_KINDS)[number];

/**
 * A lane collects at most this many answered questions, and as many finished days. That is more
 * than one burst of answers needs, and the payload stays small.
 */
const MAX_LANE_INSTANCES = 20;

export function isDailyPartnerPushKind(kind: string): kind is DailyPartnerPushKind {
  return (DAILY_PARTNER_PUSH_KINDS as readonly string[]).includes(kind);
}

type LaneEvent = {
  couple_id: string;
  actor_user_id: string;
  recipient_user_id: string;
  /** A question the recipient answered first and the partner answered just now. */
  answered_instance_id?: string;
  /** The couple day the partner just finished. */
  completed_couple_day_id?: string;
};

function idList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((id): id is string => typeof id === "string") : [];
}

function withId(ids: string[], id: string | undefined): string[] {
  return id === undefined || ids.includes(id) || ids.length >= MAX_LANE_INSTANCES ? ids : [...ids, id];
}

/**
 * The lane's events live in the payload: `instance_ids` for answered questions and
 * `completed_couple_day_ids` for finished days. A late offline answer can finish yesterday
 * right before today, so a lane can hold more than one day.
 */
function withEvent(payload: Record<string, unknown>, event: LaneEvent): Record<string, unknown> {
  return {
    ...payload,
    instance_ids: withId(idList(payload.instance_ids), event.answered_instance_id),
    completed_couple_day_ids: withId(idList(payload.completed_couple_day_ids), event.completed_couple_day_id),
  };
}

const todayDeeplink = (coupleDayId: string) => `paeonia://daily/today?coupleDayId=${coupleDayId}`;
const revealDeeplink = (instanceId: string, coupleDayId: string) =>
  `paeonia://daily/reveal?instanceId=${instanceId}&coupleDayId=${coupleDayId}`;

/**
 * The recipient's lane rows that have not come due yet, one per device. A row that is due may be
 * sending already, so a later answer starts a new lane instead of changing it.
 */
async function openLaneRows(ctx: ReaderCtx, event: LaneEvent, now: string): Promise<Doc<"notification_outbox">[]> {
  const rows = await ctx.db
    .query("notification_outbox")
    .withIndex("by_recipient_user_id_created_at", (q) =>
      q
        .eq("recipient_user_id", event.recipient_user_id)
        .gte("created_at", addMs(now, -2 * DAILY_PARTNER_PUSH_DELAY_SECONDS * 1000)),
    )
    .collect();
  return rows.filter(
    (row) =>
      isDailyPartnerPushKind(row.kind) &&
      row.sent_at === undefined &&
      row.failed_at === undefined &&
      row.scheduled_for > now &&
      (row.payload as Record<string, unknown>).couple_id === event.couple_id,
  );
}

/**
 * Adds the event to the recipient's open lane, or opens one. Queueing the lane's push again with
 * its own dedupe key adds a row for a phone that signed in since, and skips the phones that have one.
 */
async function queueDailyPartnerPush(ctx: WriterCtx, event: LaneEvent, coupleDayId: string): Promise<void> {
  const now = nowIso();
  const open = await openLaneRows(ctx, event, now);
  let kind: DailyPartnerPushKind;
  let scheduledFor: string;
  let payload: Record<string, unknown>;
  if (open.length > 0) {
    for (const row of open) {
      await ctx.db.patch(row._id, { payload: withEvent(row.payload as Record<string, unknown>, event) });
    }
    kind = open[0].kind as DailyPartnerPushKind;
    scheduledFor = open[0].scheduled_for;
    payload = withEvent(open[0].payload as Record<string, unknown>, event);
  } else {
    kind = event.completed_couple_day_id === undefined ? "partner_answered" : "daily_challenge_completed";
    scheduledFor = addMs(now, DAILY_PARTNER_PUSH_DELAY_SECONDS * 1000);
    payload = firstLanePayload(kind, event, coupleDayId);
  }
  await enqueueNotificationForUser(ctx, {
    recipient_user_id: event.recipient_user_id,
    kind,
    payload,
    dedupe_key: `daily_partner:${event.recipient_user_id}:${scheduledFor}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `daily:${event.couple_id}`,
    scheduled_for: scheduledFor,
  });
}

/** The deeplink and copy are for the lane's first event. The send replaces them with what fits by then. */
function firstLanePayload(kind: DailyPartnerPushKind, event: LaneEvent, coupleDayId: string): Record<string, unknown> {
  return withEvent(
    {
      type: kind,
      couple_id: event.couple_id,
      couple_day_id: coupleDayId,
      actor_user_id: event.actor_user_id,
      route: "daily",
      deeplink:
        event.answered_instance_id === undefined
          ? todayDeeplink(coupleDayId)
          : revealDeeplink(event.answered_instance_id, coupleDayId),
    },
    event,
  );
}

/**
 * Port of the `enqueue_partner_answered_notification` trigger. Call after inserting a
 * daily_question_answers row. When the answer is the second visible one, the partner who answered
 * first hears about it through their daily lane.
 */
export async function enqueuePartnerAnsweredNotification(
  ctx: WriterCtx,
  answer: Doc<"daily_question_answers">,
): Promise<void> {
  if (answer.deleted_at !== undefined || answer.moderation_status !== "visible") {
    return;
  }
  const instance = await getByUuid(ctx, "daily_question_instances", answer.instance_id);
  // Topic answers send the throttled `topics_waiting` push instead (lib/topics.ts).
  if (!instance || instance.couple_day_id === undefined) return;
  const visible = await visibleAnswersOf(ctx, answer.instance_id);
  if (visible.length !== 2) return;
  const recipient = visible.find((item) => item.user_id !== answer.user_id);
  if (!recipient) return;
  await queueDailyPartnerPush(
    ctx,
    {
      couple_id: instance.couple_id,
      actor_user_id: answer.user_id,
      recipient_user_id: recipient.user_id,
      answered_instance_id: instance.id,
    },
    instance.couple_day_id,
  );
}

/** Tells the partner, through their daily lane, that `actorUserId` answered every question of their day. */
export async function enqueueDailyChallengeCompletedNotification(
  ctx: WriterCtx,
  args: { couple_id: string; couple_day_id: string; actor_user_id: string },
): Promise<void> {
  for (const member of await listActiveMembers(ctx, args.couple_id)) {
    if (member.user_id === args.actor_user_id) continue;
    await queueDailyPartnerPush(
      ctx,
      {
        couple_id: args.couple_id,
        actor_user_id: args.actor_user_id,
        recipient_user_id: member.user_id,
        completed_couple_day_id: args.couple_day_id,
      },
      args.couple_day_id,
    );
  }
}

/** Whether the recipient answered first, the partner answered too, and the recipient has not opened it since. */
async function revealWaits(
  ctx: ReaderCtx,
  instance: Doc<"daily_question_instances">,
  recipientId: string,
  actorId: string,
): Promise<boolean> {
  const answers = await visibleAnswersOf(ctx, instance.id);
  if (!answers.some((answer) => answer.user_id === recipientId) || !answers.some((answer) => answer.user_id === actorId)) {
    return false;
  }
  const seen = await ctx.db
    .query("daily_answer_seen_states")
    .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", recipientId))
    .unique();
  return seen === null;
}

/** How many of the partner's own questions on the day they answered and the recipient has not. */
async function questionsToAnswer(ctx: ReaderCtx, dayId: string, recipientId: string, actorId: string): Promise<number> {
  let count = 0;
  for (const instance of await instancesOfDay(ctx, dayId)) {
    if (!isLive(instance) || instance.seeded_for_user_id !== actorId) continue;
    const answers = await visibleAnswersOf(ctx, instance.id);
    if (answers.some((a) => a.user_id === actorId) && !answers.some((a) => a.user_id === recipientId)) count += 1;
  }
  return count;
}

export type ResolvedDailyPartnerPush =
  | {
      push: { kind: DailyPartnerPushKind; payload: Record<string, unknown>; title: string; body: string | undefined };
    }
  | { push: null; reason: "ineligible" | "out_of_date" };

/**
 * Decides what a due lane row says. "Finished today's questions" when the partner finished a day
 * in this lane and something still waits for the recipient: the partner's questions to answer, or
 * answers to see. Otherwise "answered too" for the answers the recipient has not opened yet. Null
 * when the recipient turned both kinds off, or already answered and opened everything.
 * `allows` is the recipient's preference check for a kind.
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
  const completedDayIds = idList(lane.completed_couple_day_ids);
  // A day the partner finished in an earlier lane still has questions waiting for the recipient's
  // answers. That lane's "finished" alert said so, and this push replaces it on the Lock Screen
  // (same collapse id), so the day counts here too.
  for (const id of idList(lane.instance_ids)) {
    const dayId = (await getByUuid(ctx, "daily_question_instances", id))?.couple_day_id;
    if (dayId === undefined || completedDayIds.includes(dayId)) continue;
    const challenge = await ctx.db
      .query("daily_challenges")
      .withIndex("by_couple_day_id_user_id", (q) => q.eq("couple_day_id", dayId).eq("user_id", actorId))
      .unique();
    if (challenge?.completed_at !== undefined && (await questionsToAnswer(ctx, dayId, recipientId, actorId)) > 0) {
      completedDayIds.push(dayId);
    }
  }
  const finishedAllowed = completedDayIds.length > 0 && allows("daily_challenge_completed");
  const answeredAllowed = allows("partner_answered");
  if (!finishedAllowed && !answeredAllowed) return { push: null, reason: "ineligible" };

  // The recipient's own questions of a finished day count too, so this push also covers an
  // earlier "answered too" it replaces on the Lock Screen (same collapse id).
  const candidates = new Set(idList(lane.instance_ids));
  let toAnswer = 0;
  for (const dayId of finishedAllowed ? completedDayIds : []) {
    for (const instance of await instancesOfDay(ctx, dayId)) {
      if (isLive(instance) && instance.seeded_for_user_id === recipientId) candidates.add(instance.id);
    }
    toAnswer += await questionsToAnswer(ctx, dayId, recipientId, actorId);
  }
  const toSee: Doc<"daily_question_instances">[] = [];
  for (const id of candidates) {
    const instance = await getByUuid(ctx, "daily_question_instances", id);
    if (!instance || !isLive(instance) || instance.couple_day_id === undefined || instance.couple_id !== coupleId) continue;
    if (await revealWaits(ctx, instance, recipientId, actorId)) toSee.push(instance);
  }

  // The finished days stay in the payload, so a send that retries still knows about them.
  const base = {
    couple_id: coupleId,
    actor_user_id: actorId,
    route: "daily",
    instance_ids: toSee.map((item) => item.id),
    completed_couple_day_ids: completedDayIds,
  };
  let kind: DailyPartnerPushKind;
  let payload: Record<string, unknown>;
  if (finishedAllowed && (toAnswer > 0 || toSee.length > 0)) {
    kind = "daily_challenge_completed";
    const latestDayId = completedDayIds[completedDayIds.length - 1];
    payload = {
      ...base,
      type: kind,
      couple_day_id: latestDayId,
      to_answer: toAnswer > 0,
      to_see: toSee.length > 0,
      deeplink: todayDeeplink(latestDayId),
    };
  } else if (answeredAllowed && toSee.length > 0) {
    kind = "partner_answered";
    const [newest] = [...toSee].sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0));
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
      title: await notificationAlertTitle(ctx, kind, payload, locale),
      body: notificationAlertBody(kind, payload, locale) ?? undefined,
    },
  };
}
