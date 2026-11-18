import { deleteAnswer } from "./dailyAnswers";
import { dailyQuestionThreadLink } from "./dailyQuestionRounds";
import type { WriterCtx } from "./db";
import { queueOldMediaAssetIfOrphaned } from "./mediaOrphans";
import { tombstoneThreadMessage } from "./threadSubjects";

/**
 * Deletes what one person wrote in private topics (`question_collections.private`), in every
 * relationship they have been in, for when they take back their yes (`lib/topics.ts`). That is
 * each of their answers with its parts, and their messages in those questions' chats, which
 * stay as "Message deleted" rows. The marks of who opened whose answer go too, since the pair of
 * answers they were about no longer exists. The partner's answers and messages stay. A question
 * nobody has answered any more is no longer started. Returns how many answers it deleted.
 */
export async function deleteOwnPrivateTopicAnswers(ctx: WriterCtx, userId: string): Promise<number> {
  const topics = (
    await ctx.db
      .query("question_collections")
      .withIndex("by_kind_status", (q) => q.eq("kind", "topic"))
      .collect()
  ).filter((collection) => collection.private === true);
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId))
    .collect();

  const mediaAssetIds: string[] = [];
  let deleted = 0;
  for (const { couple_id: coupleId } of memberships) {
    for (const topic of topics) {
      const instances = await ctx.db
        .query("daily_question_instances")
        .withIndex("by_couple_id_topic_collection_id", (q) => q.eq("couple_id", coupleId).eq("topic_collection_id", topic.id))
        .collect();
      for (const instance of instances) {
        const own = await ctx.db
          .query("daily_question_answers")
          .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", userId))
          .unique();
        if (!own) continue;
        mediaAssetIds.push(...(await deleteAnswer(ctx, coupleId, own)));
        deleted += 1;

        for (const seen of await ctx.db
          .query("daily_answer_seen_states")
          .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id))
          .collect()) {
          await ctx.db.delete(seen._id);
        }
        const chat = await dailyQuestionThreadLink(ctx, coupleId, instance.question_id);
        if (chat) {
          for await (const message of ctx.db
            .query("thread_messages")
            .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", chat.thread_id))) {
            if (message.sender_user_id === userId && message.deleted_at === undefined) {
              await tombstoneThreadMessage(ctx, message);
            }
          }
        }
        const answerLeft = await ctx.db
          .query("daily_question_answers")
          .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id))
          .first();
        if (!answerLeft) await ctx.db.delete(instance._id);
      }
    }
  }
  // After the last write, so each file is judged by what still shows it.
  await queueOldMediaAssetIfOrphaned(ctx, ...mediaAssetIds);
  return deleted;
}
