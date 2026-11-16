import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import { findCurrentCouple } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import { coupleChatDeepLink } from "./deepLinks";
import { newUuid } from "./ids";
import { enqueueNotificationForUser } from "./notifications";
import { coupleChatThread } from "./threadSubjects";
import { nowIso } from "./time";

// A couple's live call. The `calls` row exists only while the call rings or runs, and every way a
// call ends goes through `endCall`, which deletes the row and leaves the call's row in the couple
// chat. See docs/calling-plan.md.

/** How long a call rings before it ends as missed. */
export const RING_MS = 45_000;
/** A running call ends when one member has sent no heartbeat for this long. */
export const HEARTBEAT_TIMEOUT_MS = 60_000;

/**
 * Why a call ended. A missed call that the callee did not choose (`canceled` by the caller, or
 * `timed_out`) sends the callee a missed-call push. `declined` and `left` (sign-out, leaving the
 * relationship, account deletion) send none.
 */
export type CallEnd = "declined" | "canceled" | "timed_out" | "hung_up" | "lost" | "left";

/** The couple's live call, or null. */
export async function liveCallOfCouple(ctx: ReaderCtx, coupleId: string): Promise<Doc<"calls"> | null> {
  return await ctx.db
    .query("calls")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .first();
}

export function isCallMember(call: Doc<"calls">, userId: string): boolean {
  return call.caller_user_id === userId || call.callee_user_id === userId;
}

/** The live call as the app reads it (`calls:get_live_call`). */
export function callView(call: Doc<"calls">) {
  return {
    call_id: call.id,
    caller_user_id: call.caller_user_id,
    callee_user_id: call.callee_user_id,
    state: call.state,
    answered_device_id: call.answered_device_id ?? null,
    ring_expires_at: call.ring_expires_at,
    answered_at: call.answered_at ?? null,
    created_at: call.created_at,
  };
}

/**
 * Ends the call: deletes its row, writes its row in the couple chat while the couple is still
 * active, sends the missed-call push when `reason` calls for one, and revokes the call's TURN
 * credentials. A ringing call ends as missed, a running one as completed with its length.
 */
export async function endCall(ctx: WriterCtx, call: Doc<"calls">, reason: CallEnd): Promise<void> {
  const now = nowIso();
  await ctx.db.delete(call._id);
  if (call.turn_usernames.length > 0) {
    await ctx.scheduler.runAfter(0, internal.calls.revoke_turn_credentials, { usernames: call.turn_usernames });
  }
  const couple = await getByUuid(ctx, "couples", call.couple_id);
  if (!couple || couple.status !== "active") return;

  const record: Doc<"thread_messages">["call"] =
    call.state === "active" && call.answered_at !== undefined
      ? { outcome: "completed", duration_seconds: Math.max(0, Math.round((Date.parse(now) - Date.parse(call.answered_at)) / 1000)) }
      : { outcome: "missed" };
  const threadId = await coupleChatThreadId(ctx, call);
  // The row's id is the call's id, so a call writes one row at most, and `start_call` can tell an ended call by it.
  if (await getByUuid(ctx, "thread_messages", call.id)) return;
  await ctx.db.insert("thread_messages", {
    id: call.id,
    thread_id: threadId,
    couple_id: call.couple_id,
    sender_user_id: call.caller_user_id,
    call: record,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });

  if (record.outcome === "missed" && (reason === "canceled" || reason === "timed_out")) {
    try {
      await enqueueNotificationForUser(ctx, {
        recipient_user_id: call.callee_user_id,
        kind: "missed_call",
        payload: {
          type: "missed_call",
          couple_id: call.couple_id,
          actor_user_id: call.caller_user_id,
          route: "chat",
          deeplink: coupleChatDeepLink,
          thread_id: threadId,
          message_id: call.id,
        },
        dedupe_key: `missed_call:${call.id}`,
        apns_push_type: "alert",
        apns_collapse_id: `call:${call.id}`,
        scheduled_for: now,
      });
    } catch {
      // A push problem must never keep a call from ending.
    }
  }
}

/** The couple chat's thread, started by the caller when nobody has written in it yet. */
async function coupleChatThreadId(ctx: WriterCtx, call: Doc<"calls">): Promise<string> {
  const existing = await coupleChatThread(ctx, call.couple_id);
  if (existing) return existing.id;
  const id = newUuid();
  const now = nowIso();
  await ctx.db.insert("conversation_threads", {
    id,
    couple_id: call.couple_id,
    kind: "couple",
    created_by_user_id: call.caller_user_id,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
  return id;
}

/** Ends the couple's live call, if any. Leaving the relationship calls it before the couple ends. */
export async function endLiveCallOfCouple(ctx: WriterCtx, coupleId: string): Promise<void> {
  const call = await liveCallOfCouple(ctx, coupleId);
  if (call) await endCall(ctx, call, "left");
}

/** Ends the live call `userId` takes part in, if any. Signing out calls it. */
export async function endLiveCallOfUser(ctx: WriterCtx, userId: string): Promise<void> {
  const couple = await findCurrentCouple(ctx, userId);
  const call = couple ? await liveCallOfCouple(ctx, couple.id) : null;
  if (call && isCallMember(call, userId)) await endCall(ctx, call, "left");
}

/** Deletes the couple's call reports. Returns the rows deleted. */
export async function deleteCoupleCallReports(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = await ctx.db
    .query("call_reports")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}
