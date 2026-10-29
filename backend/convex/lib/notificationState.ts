import type { Doc } from "../_generated/dataModel";
import { findCoupleDayAt } from "./coupleDays";
import { isActiveCoupleMember } from "./access";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { gamePushStillWanted } from "./gameRegistry";
import type { GamePushKind } from "./games";
import { pairingInviteStillWaiting } from "./pairingInviteReminder";
import { hasStartedToday } from "./questionTimeStatus";
import { accessEndingPushStillWanted, paymentProblemPushWanted } from "./subscriptionNotices";
import { addMs } from "./time";
import { hasTopicWaiting, topicPushTooSoon } from "./topics";

const GAME_PUSH_KINDS: readonly string[] = ["game_turn_ready", "game_result", "game_invite", "game_turn_reminder"];

/**
 * Whether the recipient still belongs where the row points. A row whose payload names a couple
 * needs the recipient to be an active member of it, so a push queued before a relationship ended
 * never goes out after. Game pushes also need game access and a turn that still waits for them.
 */
export async function notificationStillWanted(
  ctx: ReaderCtx,
  row: Doc<"notification_outbox">,
  recipientUserId: string,
  now: string,
): Promise<{ wanted: true } | { wanted: false; reason: "ineligible" | "out_of_date" }> {
  const payload = (row.payload ?? {}) as Record<string, unknown>;
  if (GAME_PUSH_KINDS.includes(row.kind)) {
    return await gamePushStillWanted(ctx, row.kind as GamePushKind, payload, recipientUserId, now);
  }
  if (typeof payload.couple_id === "string" && !(await isActiveCoupleMember(ctx, recipientUserId, payload.couple_id))) {
    return { wanted: false, reason: "ineligible" };
  }
  // A message its sender took back before the alert went out needs no alert.
  if (row.kind === "thread_message_sent" && typeof payload.message_id === "string") {
    const message = await getByUuid(ctx, "thread_messages", payload.message_id);
    const thread = message ? await getByUuid(ctx, "conversation_threads", message.thread_id) : null;
    if (!message || message.deleted_at !== undefined || message.moderation_status !== "visible" ||
        !thread || thread.deleted_at !== undefined || thread.moderation_status !== "visible") {
      return { wanted: false, reason: "out_of_date" };
    }
    const read = await ctx.db.query("thread_read_states")
      .withIndex("by_thread_id_user_id", q => q.eq("thread_id", message.thread_id).eq("user_id", recipientUserId)).unique();
    if (read && (read.last_read_message_created_at > message.created_at ||
        (read.last_read_message_created_at === message.created_at && read.last_read_message_id >= message.id))) return { wanted: false, reason: "out_of_date" };
  }
  if (row.kind === "memory_created" && typeof payload.memory_id === "string") {
    const memory = await getByUuid(ctx, "memories", payload.memory_id);
    if (!memory || memory.deleted_at !== undefined || memory.moderation_status !== "visible") {
      return { wanted: false, reason: "out_of_date" };
    }
  }
  if (row.kind === "story_posted" && typeof payload.story_id === "string") {
    const story = await getByUuid(ctx, "stories", payload.story_id);
    if (!story || story.deleted_at !== undefined || story.seen_at !== undefined ||
        addMs(story.created_at, 86_400_000) <= now) return { wanted: false, reason: "out_of_date" };
  }
  // A reaction its sender took back before the alert went out needs no alert.
  if (
    row.kind === "reaction_added" &&
    typeof payload.target_kind === "string" &&
    typeof payload.target_id === "string" &&
    typeof payload.actor_user_id === "string"
  ) {
    const reaction = await ctx.db
      .query("reactions")
      .withIndex("by_target_kind_target_id_user_id", (q) =>
        q
          .eq("target_kind", payload.target_kind as Doc<"reactions">["target_kind"])
          .eq("target_id", payload.target_id as string)
          .eq("user_id", payload.actor_user_id as string),
      )
      .unique();
    if (!reaction) return { wanted: false, reason: "out_of_date" };
  }
  // The topic push can wait up to 3 hours, so it goes out only if something still waits by then,
  // and never sooner than 3 hours after the previous topic push really went out.
  if (
    row.kind === "topics_waiting" &&
    typeof payload.couple_id === "string" &&
    (!(await hasTopicWaiting(ctx, payload.couple_id, recipientUserId)) ||
      (await topicPushTooSoon(ctx, recipientUserId, row.scheduled_for, now)))
  ) {
    return { wanted: false, reason: "out_of_date" };
  }
  // The invite reminder goes out only while the invite still waits for the partner.
  if (row.kind === "pairing_invite_reminder") {
    const invite = typeof payload.invite_id === "string" ? await getByUuid(ctx, "pairing_invites", payload.invite_id) : null;
    if (!invite || invite.created_by_user_id !== recipientUserId) return { wanted: false, reason: "ineligible" };
    if (!(await pairingInviteStillWaiting(ctx, invite, now))) return { wanted: false, reason: "out_of_date" };
  }
  if (
    row.kind === "question_time_reminder" &&
    typeof payload.couple_id === "string" &&
    (await hasStartedToday(ctx, payload.couple_id, recipientUserId, now))
  ) {
    return { wanted: false, reason: "out_of_date" };
  }
  // A payment that went through, or renewal turned back on, before the alert went out needs no alert.
  if (row.kind === "subscription_payment_failed" && !(await paymentProblemPushWanted(ctx, recipientUserId))) {
    return { wanted: false, reason: "out_of_date" };
  }
  if (row.kind === "subscription_ending" && !(await accessEndingPushStillWanted(ctx, recipientUserId, payload))) {
    return { wanted: false, reason: "out_of_date" };
  }
  // Renewal turned off since the trial reminder was queued: the ending push tells of the same end.
  if (row.kind === "subscription_trial_reminder") {
    const tx =
      typeof payload.subscription_id === "string"
        ? await getByUuid(ctx, "storekit_transactions", payload.subscription_id)
        : null;
    if (tx?.auto_renew_off === true) return { wanted: false, reason: "out_of_date" };
  }
  if (row.kind === "streak_reminder" && typeof payload.couple_id === "string") {
    const day = await findCoupleDayAt(ctx, payload.couple_id, now);
    const activity = day ? await ctx.db.query("couple_activity_events")
      .withIndex("by_couple_day_id", q => q.eq("couple_day_id", day.id)).collect() : [];
    if (activity.some(event => event.user_id === recipientUserId)) return { wanted: false, reason: "out_of_date" };
  }
  if (row.kind === "data_export_ready" && typeof payload.export_id === "string") {
    const exported = await getByUuid(ctx, "data_exports", payload.export_id);
    if (!exported || exported.status !== "ready" || (exported.expires_at !== undefined && exported.expires_at <= now)) {
      return { wanted: false, reason: "out_of_date" };
    }
  }
  return { wanted: true };
}
