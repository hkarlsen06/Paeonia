import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

// The couple chat ("Just us") is the one chat a couple has that is not about anything in
// particular. It is the chat every other kind uses, so these tests cover what is its own: one
// thread per couple, its push, and who may use it. The shared thread rules are in threads.test.ts.

const NOW = "2026-11-04T12:00:00.000Z";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers();
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds = 60) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

const write = (user: TestUser, coupleId: string, body = "hi") =>
  user.as.mutation(api.threads.create_couple_thread_with_message, { ...op(), p_couple_id: coupleId, p_body: body });

const typing = (user: TestUser, coupleId: string, isTyping = true) =>
  user.as.mutation(api.chatPresence.set_chat_typing, { p_couple_id: coupleId, p_subject_kind: "couple", p_is_typing: isTyping });

const presence = (user: TestUser, coupleId: string) =>
  user.as.query(api.chatPresence.get_chat_presence, { p_couple_id: coupleId, p_subject_kind: "couple" });

const noPresence = { partner_in_chat: false, partner_typing: false, partner_last_read_message_id: null, partner_read_at: null };
const deniedCouple = { code: "42501", message: "active entitled couple access is required" };
const deniedThread = { code: "42501", message: "active entitled thread access is required" };

async function startChat(couple: TestCouple) {
  const [first] = await write(couple.first, couple.coupleId, "Morning, you");
  return first;
}

describe("couple chat", () => {
  test("a couple has one chat, which the first message starts and both partners write in", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const first = await startChat(couple);
    tick();
    const [second] = await write(couple.second, couple.coupleId, "Morning!");
    expect(second.thread_id).toBe(first.thread_id);
    tick();
    await couple.first.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: first.thread_id, p_body: "Coffee?" });

    expect(await t.run((ctx) => ctx.db.query("conversation_threads").collect())).toMatchObject([
      { id: first.thread_id, couple_id: couple.coupleId, kind: "couple", created_by_user_id: couple.first.userId },
    ]);
    const page = await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: first.thread_id, p_limit: 50 });
    expect(page.messages.map((message) => message.body)).toEqual(["Morning, you", "Morning!", "Coffee?"]);
    expect(await couple.second.as.query(api.threads.get_conversation_threads, {})).toMatchObject([
      {
        thread_id: first.thread_id,
        kind: "couple",
        daily_question_id: null,
        memory_id: null,
        story_id: null,
        game_kind: null,
        last_message_body: "Coffee?",
        last_message_sender_user_id: couple.first.userId,
      },
    ]);
  });

  test("a replay returns the first result without another message", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const args = { ...op(), p_couple_id: couple.coupleId, p_body: "once" };
    const first = await couple.first.as.mutation(api.threads.create_couple_thread_with_message, args);
    expect(await couple.first.as.mutation(api.threads.create_couple_thread_with_message, args)).toEqual(first);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(1);
  });

  test("a photo can start the chat", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.second, photo(couple.coupleId, "thread_message_media", "thread_media"));
    const [row] = await couple.second.as.mutation(api.threads.create_couple_thread_with_message, {
      ...op(),
      p_couple_id: couple.coupleId,
      p_body: null,
      p_media_asset_ids: [up.assetId],
    });
    const [summary] = await couple.first.as.query(api.threads.get_conversation_threads, {});
    expect(summary).toMatchObject({ thread_id: row.thread_id, kind: "couple", last_message_media_type: "image" });
  });

  test("the partner's push opens the couple chat, keeps the thread and message ids, and never holds the text", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en", token: "partner" });
    const [row] = await write(couple.first, couple.coupleId, "Secret chat text");

    const pushes = (await t.run((ctx) => ctx.db.query("notification_outbox").collect())).filter(
      (push) => push.kind === "thread_message_sent",
    );
    expect(pushes).toHaveLength(1);
    expect(pushes[0].recipient_user_id).toBe(couple.second.userId);
    expect(pushes[0].payload).toEqual({
      type: "thread_message_sent",
      couple_id: couple.coupleId,
      thread_id: row.thread_id,
      message_id: row.message_id,
      actor_user_id: couple.first.userId,
      route: "chat",
      deeplink: "paeonia://chat",
    });
    expect([pushes[0].title, pushes[0].body]).toEqual(["First Partner", "Sent you a message"]);
    expect(JSON.stringify(pushes)).not.toContain("Secret chat");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an unread message from the partner counts on the Chats badge until it is read", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const [row] = await write(couple.first, couple.coupleId);
    expect(await couple.second.as.query(api.badges.get_badges, {})).toMatchObject({ questions: 1, icon: 1 });
    expect(await couple.first.as.query(api.badges.get_badges, {})).toMatchObject({ questions: 0, icon: 0 });

    await couple.second.as.mutation(api.chatPresence.mark_thread_read, { p_thread_id: row.thread_id, p_message_id: row.message_id });
    expect(await couple.second.as.query(api.badges.get_badges, {})).toMatchObject({ questions: 0, icon: 0 });
  });

  test("typing and the read mark work before and after the thread exists, with no subject id", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await typing(couple.second, couple.coupleId);
    expect((await presence(couple.first, couple.coupleId)).partner_typing).toBe(true);
    expect((await presence(couple.second, couple.coupleId)).partner_typing).toBe(false);

    const row = await startChat(couple);
    await couple.second.as.mutation(api.chatPresence.mark_thread_read, { p_thread_id: row.thread_id, p_message_id: row.message_id });
    expect((await presence(couple.first, couple.coupleId)).partner_last_read_message_id).toBe(row.message_id);
  });

  test("messages in the couple chat are found by search", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const row = await startChat(couple);
    const result = await couple.second.as.query(api.search.search_couple_content, { p_query: "morning", p_locale: "en" });
    expect(result.messages).toMatchObject([
      { message_id: row.message_id, thread_kind: "couple", question_id: null, memory_id: null, story_id: null, context_title: null },
    ]);
  });

  test("someone outside the couple is refused everywhere", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const row = await startChat(couple);

    for (const outsider of [stranger, other.first]) {
      expect(await failure(write(outsider, couple.coupleId))).toEqual(deniedCouple);
      expect(await failure(typing(outsider, couple.coupleId))).toEqual(deniedCouple);
      expect(await presence(outsider, couple.coupleId)).toEqual(noPresence);
      expect(
        await failure(outsider.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: row.thread_id, p_body: "x" })),
      ).toEqual(deniedThread);
      expect(
        await failure(outsider.as.mutation(api.chatPresence.mark_thread_read, { p_thread_id: row.thread_id, p_message_id: row.message_id })),
      ).toEqual(deniedThread);
      expect(await outsider.as.query(api.threads.get_thread_messages, { p_thread_id: row.thread_id, p_limit: 50 })).toEqual({
        messages: [],
        has_more: false,
      });
    }
    // The other couple's own chat is a different thread.
    const [theirs] = await write(other.first, other.coupleId);
    expect(theirs.thread_id).not.toBe(row.thread_id);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(2);
  });

  test("a couple without access is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect(await failure(write(couple.first, couple.coupleId))).toEqual(deniedCouple);
    expect(await failure(typing(couple.second, couple.coupleId))).toEqual(deniedCouple);
    expect(await presence(couple.first, couple.coupleId)).toEqual(noPresence);
    expect(await t.run((ctx) => ctx.db.query("conversation_threads").collect())).toEqual([]);
  });

  test("a couple that lost access after writing can no longer read or write", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const row = await startChat(couple);
    await t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect(await failure(write(couple.second, couple.coupleId))).toEqual(deniedCouple);
    expect(
      await failure(couple.second.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: row.thread_id, p_body: "x" })),
    ).toEqual(deniedThread);
    expect((await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: row.thread_id, p_limit: 50 })).messages).toEqual([]);
  });

  test("ending the relationship hides, then purges the couple chat", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await startChat(couple);
    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    expect((await t.run((ctx) => ctx.db.query("conversation_threads").collect())).map((thread) => thread.deleted_at)).toEqual([NOW]);
    await t.run((ctx) => purgeCoupleContent(ctx, row));
    expect(await t.run((ctx) => ctx.db.query("conversation_threads").collect())).toEqual([]);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toEqual([]);
  });
});

/** The subject id is still required for every chat that has a subject. */
test("typing in a question chat without its id is refused", async () => {
  const t: TestConvex = newTest();
  const couple = await createCouple(t);
  expect(
    await failure(
      couple.first.as.mutation(api.chatPresence.set_chat_typing, {
        p_couple_id: couple.coupleId,
        p_subject_kind: "daily_question",
        p_is_typing: true,
      }),
    ),
  ).toEqual({ code: "22023", message: "chat subject id is required" });
});
