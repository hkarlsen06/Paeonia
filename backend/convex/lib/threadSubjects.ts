import { v, type Infer } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { dailyQuestionThreadLink } from "./dailyQuestionRounds";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { fail } from "./errors";
import { gameChatSubjectId } from "./gameChatSubjects";
import { uuidArg } from "./ids";
import { queueThreadMediaAssetsIfOrphaned } from "./mediaOrphans";
import { deleteReactionsOfThread } from "./reactions";
import { nowIso } from "./time";
import { gameKind, threadKind } from "./validators";

// A chat thread is about a question, memory, story or game kind, or about nothing in particular
// (the couple chat). The kind is the thread's `conversation_threads.kind`. Each kind but the
// couple chat has its own link table from the subject to the thread: `daily_question_threads`,
// `memory_threads` and `story_threads`, with game kinds linked by `game_threads`. A couple has one
// couple chat, so its subject has no id and the thread is found by couple and kind. Everything
// that works for any chat (typing, creating the thread with its first message, pushes) finds the
// thread and checks the subject here, so a new kind is one more case in these functions.

export type ThreadSubjectKind = Infer<typeof threadKind>;

export type ThreadSubject = { kind: "couple" } | { kind: Exclude<ThreadSubjectKind, "couple">; id: string };

/** The arguments of a function that names a chat by its subject. The couple chat sends no id. */
export const threadSubjectArgs = { p_subject_kind: threadKind, p_subject_id: v.optional(v.union(v.null(), v.string())) };

export function threadSubjectOf(args: { p_subject_kind: ThreadSubjectKind; p_subject_id?: string | null }): ThreadSubject {
  if (args.p_subject_kind === "couple") return { kind: "couple" };
  if (args.p_subject_id == null) return fail("22023", "chat subject id is required");
  return { kind: args.p_subject_kind, id: uuidArg(args.p_subject_id) };
}

/** The key of a chat's typing room within its couple (`chatTypingRoom`). */
export function subjectRoomKey(subject: ThreadSubject): string {
  return subject.kind === "couple" ? "couple" : subject.id;
}

/** The couple's own chat, or null before anyone has written in it. */
export async function coupleChatThread(ctx: ReaderCtx, coupleId: string): Promise<Doc<"conversation_threads"> | null> {
  return await ctx.db
    .query("conversation_threads")
    .withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId).eq("kind", "couple"))
    .unique();
}

/**
 * The thread of the couple's chat about the subject, or null before anyone has written.
 * A thread that belongs to another couple is never returned.
 */
export async function threadIdOfSubject(
  ctx: ReaderCtx,
  coupleId: string,
  subject: ThreadSubject,
): Promise<string | null> {
  switch (subject.kind) {
    case "couple":
      return (await coupleChatThread(ctx, coupleId))?.id ?? null;
    case "game": {
      const link = await ctx.db.query("game_threads").withIndex("by_subject_id", q => q.eq("subject_id", subject.id)).unique();
      return await threadIdInCouple(ctx, coupleId, link?.thread_id);
    }
    case "daily_question":
      return (await dailyQuestionThreadLink(ctx, coupleId, subject.id))?.thread_id ?? null;
    case "memory": {
      const link = await ctx.db
        .query("memory_threads")
        .withIndex("by_memory_id", (q) => q.eq("memory_id", subject.id))
        .unique();
      return await threadIdInCouple(ctx, coupleId, link?.thread_id);
    }
    case "story": {
      const link = await ctx.db
        .query("story_threads")
        .withIndex("by_story_id", (q) => q.eq("story_id", subject.id))
        .unique();
      return await threadIdInCouple(ctx, coupleId, link?.thread_id);
    }
  }
}

async function threadIdInCouple(ctx: ReaderCtx, coupleId: string, threadId: string | undefined) {
  const thread = await getByUuid(ctx, "conversation_threads", threadId);
  return thread && thread.couple_id === coupleId ? thread.id : null;
}

/** What the thread is about, or null when its link row is gone. */
export async function subjectOfThread(
  ctx: ReaderCtx,
  thread: Pick<Doc<"conversation_threads">, "id" | "kind">,
): Promise<ThreadSubject | null> {
  switch (thread.kind) {
    case "couple":
      return { kind: "couple" };
    case "game": {
      const link = await ctx.db.query("game_threads").withIndex("by_thread_id", q => q.eq("thread_id", thread.id)).unique();
      return link ? { kind: "game", id: link.subject_id } : null;
    }
    case "daily_question": {
      const link = await ctx.db
        .query("daily_question_threads")
        .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
        .unique();
      return link ? { kind: "daily_question", id: link.question_id } : null;
    }
    case "memory": {
      const link = await ctx.db
        .query("memory_threads")
        .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
        .unique();
      return link ? { kind: "memory", id: link.memory_id } : null;
    }
    case "story": {
      const link = await ctx.db
        .query("story_threads")
        .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
        .unique();
      return link ? { kind: "story", id: link.story_id } : null;
    }
  }
}

/**
 * Whether the subject exists for this couple and can have a chat: the question is in the
 * catalog, the memory is shown, the story is not deleted. Every couple has its couple chat. Whether the couple's days of a
 * question allow a chat is the question chat's own rule (`create_daily_question_thread_with_message`).
 */
export async function isChatSubjectAvailable(
  ctx: ReaderCtx,
  coupleId: string,
  subject: ThreadSubject,
): Promise<boolean> {
  switch (subject.kind) {
    case "couple":
      return true;
    case "game": {
      const link = await ctx.db.query("game_threads").withIndex("by_subject_id", q => q.eq("subject_id", subject.id)).unique();
      if (link) return link.couple_id === coupleId;
      // Opening a game chat does not create its thread. Its canonical room can already show typing.
      for (const kind of gameKind.members) {
        if (await gameChatSubjectId(coupleId, kind.value) === subject.id) return true;
      }
      return false;
    }
    case "daily_question":
      return (await getByUuid(ctx, "questions", subject.id)) !== null;
    case "memory": {
      const memory = await getByUuid(ctx, "memories", subject.id);
      return (
        memory !== null &&
        memory.couple_id === coupleId &&
        memory.deleted_at === undefined &&
        memory.moderation_status === "visible"
      );
    }
    case "story": {
      const story = await getByUuid(ctx, "stories", subject.id);
      return story !== null && story.couple_id === coupleId && story.deleted_at === undefined;
    }
  }
}

/**
 * Deletes the chat about a subject that was deleted, such as a story its author took down. The
 * thread keeps its messages as hidden rows until the couple's content is purged. The media of
 * its messages is queued for storage deletion once nothing else shows it. Does nothing when the
 * subject never had a chat.
 */
export async function deleteThreadOfSubject(
  ctx: WriterCtx,
  coupleId: string,
  subject: ThreadSubject,
): Promise<void> {
  const thread = await getByUuid(ctx, "conversation_threads", await threadIdOfSubject(ctx, coupleId, subject));
  if (!thread || thread.deleted_at !== undefined) return;
  await ctx.db.patch(thread._id, withUpdatedAt({ deleted_at: nowIso() }));
  await deleteReactionsOfThread(ctx, thread.id);
  await queueThreadMediaAssetsIfOrphaned(ctx, thread.id);
}
