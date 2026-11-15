import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";

// When a chat counts as unread for one person. The app icon (`lib/badges.ts`) and the chat list
// (`threads:get_conversation_threads`) both read it, so a chat the list marks unread is one the
// badge counts. Kept apart from `lib/badges.ts`, which reaches every game.

/**
 * Whether the thread waits for `userId`: it is shown, and its newest counted message is the
 * partner's, shown, and newer than what this person read on any phone.
 */
export async function isThreadUnreadFor(
  ctx: ReaderCtx,
  thread: Doc<"conversation_threads">,
  userId: string,
): Promise<boolean> {
  if (thread.deleted_at !== undefined || thread.moderation_status !== "visible") return false;
  const last = await newestCountedMessage(ctx, thread.id);
  if (!last || last.sender_user_id === userId || last.deleted_at !== undefined || last.moderation_status !== "visible") {
    return false;
  }
  const read = await ctx.db
    .query("thread_read_states")
    .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", thread.id).eq("user_id", userId))
    .unique();
  return !(read && (read.last_read_message_created_at > last.created_at ||
    (read.last_read_message_created_at === last.created_at && read.last_read_message_id >= last.id)));
}

/**
 * The thread's newest message, passing over the rows of completed calls, which never mark a chat
 * unread. A missed call counts like a message.
 */
async function newestCountedMessage(ctx: ReaderCtx, threadId: string): Promise<Doc<"thread_messages"> | null> {
  for await (const message of ctx.db
    .query("thread_messages")
    .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", threadId))
    .order("desc")) {
    if (message.call?.outcome !== "completed") return message;
  }
  return null;
}
