import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, components } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { chatTypingRoom } from "./lib/presence";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

// Replies to a story and comments on a memory are the chat that question chats use, with the story
// or the memory as the subject. The thread rules shared by every kind are in threads.test.ts.

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds = 60) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

/** `author` posts a story, the way the app does: photo first, then the post. */
async function postStory(t: TestConvex, couple: TestCouple, author: TestUser = couple.first) {
  const storyId = newUuid();
  const up = await uploadAsset(t, author, { ...photo(couple.coupleId, "story", "story_photo"), parentId: storyId });
  await author.as.mutation(api.stories.post_story, {
    p_story_id: storyId,
    p_media_asset_id: up.assetId,
    p_caption: "Thinking of you",
    ...op(),
  });
  return storyId;
}

const reply = (user: TestUser, storyId: string, body = "Love this", extra: Record<string, unknown> = {}) =>
  user.as.mutation(api.threads.create_story_thread_with_message, { ...op(), p_story_id: storyId, p_body: body, ...extra });

const send = (user: TestUser, threadId: string, body = "hi") =>
  user.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: threadId, p_body: body });

const messagesOf = async (user: TestUser, threadId: string) =>
  (await user.as.query(api.threads.get_thread_messages, { p_thread_id: threadId, p_limit: 50 })).messages;

const deniedStory = { code: "42501", message: "active entitled story access is required" };

describe("story replies", () => {
  test("the first reply starts the thread, and both partners write in it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = await postStory(t, couple);

    const [first] = await reply(couple.second, storyId);
    expect(await t.run((ctx) => ctx.db.query("story_threads").collect())).toMatchObject([
      { story_id: storyId, thread_id: first.thread_id },
    ]);
    expect(await t.run((ctx) => ctx.db.query("conversation_threads").collect())).toMatchObject([
      { id: first.thread_id, couple_id: couple.coupleId, kind: "story", created_by_user_id: couple.second.userId },
    ]);

    tick();
    const [second] = await reply(couple.first, storyId, "Thanks!");
    expect(second.thread_id).toBe(first.thread_id);
    tick();
    await send(couple.second, first.thread_id, "Where was this?");
    const bodies = (await messagesOf(couple.first, first.thread_id)).map((message) => message.body);
    expect(bodies).toEqual(["Love this", "Thanks!", "Where was this?"]);
  });

  test("a replay returns the first result without another message", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = await postStory(t, couple);
    const args = { ...op(), p_story_id: storyId, p_body: "once" };
    const first = await couple.second.as.mutation(api.threads.create_story_thread_with_message, args);
    expect(await couple.second.as.mutation(api.threads.create_story_thread_with_message, args)).toEqual(first);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(1);
  });

  test("the partner gets a push that opens the replies and never holds the text", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId, { locale: "en", token: "author" });
    await addDevice(t, couple.second.userId, { locale: "en", token: "viewer" });
    const storyId = await postStory(t, couple);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });

    const [result] = await reply(couple.second, storyId, "Secret reply text");
    const rows = (await outbox(t)).filter((row) => row.kind === "thread_message_sent");
    expect(rows).toHaveLength(1);
    expect(rows[0].recipient_user_id).toBe(couple.first.userId);
    expect(rows[0].payload).toEqual({
      type: "thread_message_sent",
      couple_id: couple.coupleId,
      thread_id: result.thread_id,
      message_id: result.message_id,
      actor_user_id: couple.second.userId,
      route: "stories",
      deeplink: `paeonia://stories/story?storyId=${storyId}&replies=1`,
      story_id: storyId,
    });
    expect([rows[0].title, rows[0].body]).toEqual(["Second Partner", "Sent you a message"]);
    expect(JSON.stringify(rows)).not.toContain("Secret reply");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the thread outlives the story's 24 hours", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = await postStory(t, couple);
    const [first] = await reply(couple.second, storyId);

    tick(3 * 24 * 3600);
    const [later] = await reply(couple.first, storyId, "Still here");
    expect(later.thread_id).toBe(first.thread_id);
    const rows = await couple.first.as.query(api.threads.get_conversation_threads, {});
    expect(rows).toMatchObject([{ thread_id: first.thread_id, kind: "story", story_id: storyId, memory_id: null, deleted_at: null }]);
  });

  test("deleting the story deletes the replies and frees their photos", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = await postStory(t, couple);
    const [first] = await reply(couple.second, storyId);
    const replyPhoto = await uploadAsset(t, couple.first, photo(couple.coupleId, "thread_message_media", "thread_media"));
    await send(couple.first, first.thread_id, "x");
    await couple.first.as.mutation(api.threads.send_thread_message, {
      ...op(),
      p_thread_id: first.thread_id,
      p_body: null,
      p_media_asset_ids: [replyPhoto.assetId],
    });

    await couple.first.as.mutation(api.stories.delete_story, { p_story_id: storyId, ...op() });
    const [thread] = await t.run((ctx) => ctx.db.query("conversation_threads").collect());
    expect(thread.deleted_at).toBe(NOW);
    const [listed] = await couple.second.as.query(api.threads.get_conversation_threads, {});
    expect(listed.deleted_at).toBe(NOW);
    expect(await messagesOf(couple.second, first.thread_id)).toSatisfy((rows: { body: string | null }[]) =>
      rows.every((row) => row.body === null),
    );
    const asset = await t.run((ctx) =>
      ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", replyPhoto.assetId)).unique(),
    );
    expect(asset).toMatchObject({ storage_delete_status: "pending" });

    expect(await failure(send(couple.second, first.thread_id))).toEqual({
      code: "42501",
      message: "active entitled thread access is required",
    });
    expect(await failure(reply(couple.second, storyId))).toEqual(deniedStory);
  });

  test("a missing story, a stranger and another couple's member are refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const storyId = await postStory(t, couple);
    const [first] = await reply(couple.second, storyId);

    expect(await failure(reply(couple.second, newUuid()))).toEqual(deniedStory);
    expect(await failure(reply(stranger, storyId))).toMatchObject({ code: "42501" });
    expect(await failure(reply(other.first, storyId))).toEqual(deniedStory);
    expect(await failure(send(other.first, first.thread_id))).toMatchObject({ code: "42501" });
    expect(await messagesOf(other.first, first.thread_id)).toEqual([]);
    expect(await other.first.as.query(api.threads.get_conversation_threads, {})).toEqual([]);
  });

  test("ending the relationship hides then purges the thread links", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = await postStory(t, couple);
    await reply(couple.second, storyId);

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    expect((await t.run((ctx) => ctx.db.query("conversation_threads").collect())).map((thread) => thread.deleted_at)).toEqual([NOW]);
    await t.run((ctx) => purgeCoupleContent(ctx, row));
    expect(await t.run((ctx) => ctx.db.query("story_threads").collect())).toEqual([]);
    expect(await t.run((ctx) => ctx.db.query("conversation_threads").collect())).toEqual([]);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toEqual([]);
  });
});

describe("chat presence by subject", () => {
  const typing = (user: TestUser, coupleId: string, kind: "memory" | "story", id: string, isTyping = true) =>
    user.as.mutation(api.chatPresence.set_chat_typing, {
      p_couple_id: coupleId,
      p_subject_kind: kind,
      p_subject_id: id,
      p_is_typing: isTyping,
    });
  const presence = (user: TestUser, coupleId: string, kind: "memory" | "story", id: string) =>
    user.as.query(api.chatPresence.get_chat_presence, { p_couple_id: coupleId, p_subject_kind: kind, p_subject_id: id });

  test("typing and read marks work in a story's replies before and after the thread exists", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = await postStory(t, couple);

    await typing(couple.second, couple.coupleId, "story", storyId);
    expect((await presence(couple.first, couple.coupleId, "story", storyId)).partner_typing).toBe(true);
    expect((await presence(couple.second, couple.coupleId, "story", storyId)).partner_typing).toBe(false);

    const [first] = await reply(couple.second, storyId);
    expect((await presence(couple.first, couple.coupleId, "story", storyId)).partner_last_read_message_id).toBeNull();
    await couple.first.as.mutation(api.chatPresence.mark_thread_read, {
      p_thread_id: first.thread_id,
      p_message_id: first.message_id,
    });
    expect((await presence(couple.second, couple.coupleId, "story", storyId)).partner_last_read_message_id).toBe(first.message_id);
    expect(await t.run((ctx) => ctx.runQuery(components.presence.public.listRoom, { roomId: chatTypingRoom(couple.coupleId, storyId) }))).toHaveLength(1);
  });

  test("a memory's comments have their own room, and a stranger or a missing subject is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const memoryId = newUuid();
    await couple.first.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: memoryId,
      p_title: "Day one",
      p_memory_date: "2026-10-01",
      p_note_body: "note",
    });

    await typing(couple.first, couple.coupleId, "memory", memoryId);
    expect((await presence(couple.second, couple.coupleId, "memory", memoryId)).partner_typing).toBe(true);
    expect(await failure(typing(stranger, couple.coupleId, "memory", memoryId))).toEqual({
      code: "42501",
      message: "active entitled couple access is required",
    });
    expect(await presence(stranger, couple.coupleId, "memory", memoryId)).toEqual({
      partner_typing: false,
      partner_last_read_message_id: null,
      partner_read_at: null,
    });
    expect(await failure(typing(couple.first, couple.coupleId, "memory", newUuid()))).toEqual({
      code: "22023",
      message: "chat subject was not found",
    });
    // A story's id is not a memory's, so naming the wrong kind finds nothing.
    const storyId = await postStory(t, couple);
    expect(await failure(typing(couple.first, couple.coupleId, "memory", storyId))).toMatchObject({ code: "22023" });
  });
});
