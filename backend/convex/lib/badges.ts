import type { Doc } from "../_generated/dataModel";
import { getEntitledCoupleIdForUser } from "./access";
import { findCoupleDayAt } from "./coupleDays";
import { isSharedRound, loadQuestionRounds } from "./dailyQuestionRounds";
import { instancesOfDay, isLive, visibleAnswersOf } from "./dailyQuestions";
import type { ReaderCtx, WriterCtx } from "./db";
import { gamesWaitingFor } from "./gameRegistry";
import { insertNotificationOutbox, listActiveUserDevices, preferenceAllows } from "./notifications";
import { addMs, nowIso } from "./time";
import { topicsWaitingCount } from "./topics";

// The app icon badge: how many things wait for this person in their couple. Only things that
// wait for them count, one per item: an unread chat, a partner's answer they have not opened, a
// game that waits on them, and the partner's story they have not seen. Reminders, streaks and the
// trial notice never count. A kind the person switched off in Notifications does not count either.
// The server sends the number as `aps.badge`: in every alert, and in a badge-only push
// (`queueBadgeUpdate`) when something was read on another phone.
//
// The app's tab badges show the same counts split by tab, so the icon never shows a number that no
// tab explains. The tabs ignore the Notifications switches, since those turn off pushes and not
// what the app shows.

/** How long a story stays on Home, so how long an unseen one counts. */
const STORY_BADGE_MS = 24 * 60 * 60 * 1000;
/** A badge-only push waits this long, so a burst of reads sends one number. */
const BADGE_UPDATE_DELAY_MS = 30 * 1000;
/** How far back a pending badge-only push can be. More than its delay plus send retries. */
const BADGE_UPDATE_LOOKBACK_MS = 10 * 60 * 1000;

/** What waits for one person, by the tab that shows it, and the number on the app icon. */
export type BadgeCounts = {
  /** Unread question chats, today's answers to open, and Topics questions that wait. */
  questions: number;
  /** Games that wait on this person, and open invites. */
  games: number;
  /** The partner's stories still on Home that this person has not opened, and unread story replies. */
  home: number;
  /** Memories whose comments the partner wrote in and this person has not read. */
  memories: number;
  /** The tabs' items of the kinds whose alerts are on in Notifications. */
  icon: number;
};

const NO_BADGES: BadgeCounts = { questions: 0, games: 0, home: 0, memories: 0, icon: 0 };

/** What waits for `userId`. All zero without an entitled couple. */
export async function badgeCountsForUser(ctx: ReaderCtx, userId: string, now: string = nowIso()): Promise<BadgeCounts> {
  const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
  if (coupleId === null) return NO_BADGES;
  const chats = await unreadChats(ctx, coupleId, userId);
  const answers = (await answersWaiting(ctx, coupleId, userId, now)) + (await topicsWaitingCount(ctx, coupleId, userId));
  const stories = await unseenStories(ctx, coupleId, userId, now);
  const games = await gamesWaitingFor(ctx, coupleId, userId);
  const preference = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
  // Every counted kind has a switch, and a missing preference row blocks those kinds.
  const allows = (kind: Parameters<typeof preferenceAllows>[0]) =>
    preference !== null && preferenceAllows(kind, "alert", preference);
  const icon =
    // Every chat push, whatever the chat is about, follows the Messages switch.
    (allows("thread_message_sent") ? chats.questions + chats.memories + chats.stories : 0) +
    (allows("partner_answered") ? answers : 0) +
    (allows("story_posted") ? stories : 0) +
    (allows("game_turn_ready") ? games : 0);
  return {
    questions: chats.questions + answers,
    games,
    home: stories + chats.stories,
    memories: chats.memories,
    icon,
  };
}

/** The number on the app icon for `userId`. Zero without an entitled couple. */
export async function badgeCountForUser(ctx: ReaderCtx, userId: string, now: string = nowIso()): Promise<number> {
  return (await badgeCountsForUser(ctx, userId, now)).icon;
}

/** Unread chats by what they are about: a question, a memory (its comments) or a story (its replies). */
type UnreadChats = { questions: number; memories: number; stories: number };

/**
 * Chats whose newest message is from the partner and newer than what this person read on any
 * phone. A question chat counts only while it can be opened, like `get_conversation_threads`.
 */
async function unreadChats(ctx: ReaderCtx, coupleId: string, userId: string): Promise<UnreadChats> {
  const threads = await ctx.db
    .query("conversation_threads")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", coupleId))
    .collect();
  const count: UnreadChats = { questions: 0, memories: 0, stories: 0 };
  for (const thread of threads) {
    if (thread.deleted_at !== undefined || thread.moderation_status !== "visible") continue;
    const last = await ctx.db
      .query("thread_messages")
      .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", thread.id))
      .order("desc")
      .first();
    if (!last || last.sender_user_id === userId || last.deleted_at !== undefined || last.moderation_status !== "visible") {
      continue;
    }
    const read = await ctx.db
      .query("thread_read_states")
      .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", thread.id).eq("user_id", userId))
      .unique();
    if (read && read.last_read_message_created_at >= last.created_at) continue;
    if (thread.kind === "daily_question") {
      const daily = await ctx.db
        .query("daily_question_threads")
        .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
        .unique();
      if (daily && !(await loadQuestionRounds(ctx, coupleId, daily.question_id)).some(isSharedRound)) continue;
      count.questions += 1;
    } else if (thread.kind === "memory") {
      count.memories += 1;
    } else {
      count.stories += 1;
    }
  }
  return count;
}

/**
 * Today's questions the partner answered and this person has not opened since: one to answer to
 * see theirs, or one whose reveal is ready. Only the couple day running now, so an old question
 * never keeps the badge up.
 */
async function answersWaiting(ctx: ReaderCtx, coupleId: string, userId: string, now: string): Promise<number> {
  const day = await findCoupleDayAt(ctx, coupleId, now);
  if (!day) return 0;
  let count = 0;
  for (const instance of await instancesOfDay(ctx, day.id)) {
    if (!isLive(instance)) continue;
    const answers = await visibleAnswersOf(ctx, instance.id);
    if (!answers.some((answer) => answer.user_id !== userId)) continue;
    const seen = await ctx.db
      .query("daily_answer_seen_states")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", userId))
      .unique();
    if (!seen) count += 1;
  }
  return count;
}

/** The partner's stories still on Home that this person has not opened. */
async function unseenStories(ctx: ReaderCtx, coupleId: string, userId: string, now: string): Promise<number> {
  const stories = await ctx.db
    .query("stories")
    .withIndex("by_couple_id_created_at", (q) =>
      q.eq("couple_id", coupleId).gt("created_at", addMs(now, -STORY_BADGE_MS)),
    )
    .collect();
  return stories.filter(
    (story) => story.author_user_id !== userId && story.deleted_at === undefined && story.seen_at === undefined,
  ).length;
}

/**
 * Queues a badge-only push to each of the person's phones, so a read on one phone lowers the badge
 * on the others. It goes out `BADGE_UPDATE_DELAY_MS` from now and reads the count when it is sent.
 * A phone that already has one waiting gets no second one. Never throws.
 */
export async function queueBadgeUpdate(ctx: WriterCtx, userId: string): Promise<number> {
  try {
    const now = nowIso();
    const recent = await ctx.db
      .query("notification_outbox")
      .withIndex("by_recipient_user_id_created_at", (q) =>
        q.eq("recipient_user_id", userId).gte("created_at", addMs(now, -BADGE_UPDATE_LOOKBACK_MS)),
      )
      .collect();
    const waiting = new Set(
      recent.filter((row) => row.kind === "badge_update" && isPending(row)).map((row) => row.target_device_id),
    );
    const scheduledFor = addMs(now, BADGE_UPDATE_DELAY_MS);
    let queued = 0;
    for (const device of await listActiveUserDevices(ctx, userId)) {
      if (waiting.has(device.id)) continue;
      const inserted = await insertNotificationOutbox(ctx, {
        recipient_user_id: userId,
        target_device_id: device.id,
        push_token_hash: device.push_token_hash,
        apns_environment: device.apns_environment,
        kind: "badge_update",
        payload: { type: "badge_update" },
        dedupe_key: `badge_update:${device.id}:${scheduledFor}`,
        apns_push_type: "alert",
        apns_collapse_id: "badge",
        scheduled_for: scheduledFor,
      });
      if (inserted) queued += 1;
    }
    return queued;
  } catch {
    // A badge must never make the write that changed it fail.
    return 0;
  }
}

function isPending(row: Doc<"notification_outbox">): boolean {
  return row.sent_at === undefined && row.failed_at === undefined;
}
