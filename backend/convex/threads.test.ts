import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds = 60) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

async function createMemory(user: TestUser) {
  const memoryId = newUuid();
  await user.as.mutation(api.memories.create_memory, {
    ...op(),
    p_memory_id: memoryId,
    p_title: "Private memory title",
    p_memory_date: "2026-10-01",
    p_note_body: "note",
  });
  return memoryId;
}

type Result = { thread_id: string; message_id: string }[];

async function memoryThread(user: TestUser, memoryId: string, body = "Secret message text one"): Promise<Result> {
  return await user.as.mutation(api.threads.create_memory_thread_with_message, { ...op(), p_memory_id: memoryId, p_body: body });
}

/** A daily question instance both partners answered (or only the listed users). */
async function dailyInstance(t: TestConvex, couple: TestCouple, answeredBy: TestUser[] = [couple.first, couple.second]) {
  const instanceId = newUuid();
  await t.run(async (ctx) => {
    const now = new Date().toISOString();
    const dayId = await getOrCreateCoupleDayAt(ctx, couple.coupleId, now);
    await ctx.db.insert("daily_question_instances", {
      id: instanceId,
      couple_day_id: dayId,
      question_version_id: newUuid(),
      seeded_for_user_id: couple.first.userId,
      slot_number: 1,
      status: "active",
      created_at: now,
    });
    for (const user of answeredBy) {
      await ctx.db.insert("daily_question_answers", {
        id: newUuid(),
        instance_id: instanceId,
        user_id: user.userId,
        moderation_status: "visible",
        created_at: now,
        updated_at: now,
      });
    }
  });
  return instanceId;
}

const dailyThread = (user: TestUser, instanceId: string, body = "Secret message text two") =>
  user.as.mutation(api.threads.create_daily_question_thread_with_message, { ...op(), p_instance_id: instanceId, p_body: body });

const send = (user: TestUser, threadId: string, args: Record<string, unknown> = {}) =>
  user.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: threadId, p_body: "hi", ...args });

describe("memory threads", () => {
  test("the first message creates the thread and later messages reuse it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [first] = await memoryThread(couple.first, memoryId);
    expect(await t.run((ctx) => ctx.db.query("memory_threads").collect())).toMatchObject([
      { memory_id: memoryId, thread_id: first.thread_id },
    ]);
    expect(await t.run((ctx) => ctx.db.query("conversation_threads").collect())).toMatchObject([
      { id: first.thread_id, couple_id: couple.coupleId, kind: "memory", created_by_user_id: couple.first.userId, moderation_status: "visible" },
    ]);
    const [second] = await memoryThread(couple.second, memoryId, "reply");
    expect(second.thread_id).toBe(first.thread_id);
    expect(second.message_id).not.toBe(first.message_id);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(2);
  });

  test("a replay returns the first result without another message", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const args = { ...op(), p_memory_id: memoryId, p_body: "once" };
    const first = await couple.first.as.mutation(api.threads.create_memory_thread_with_message, args);
    expect(await couple.first.as.mutation(api.threads.create_memory_thread_with_message, args)).toEqual(first);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(1);
    expect(
      await failure(couple.first.as.mutation(api.threads.create_memory_thread_with_message, { ...args, p_body: "other" })),
    ).toEqual({ code: "23505", message: "client operation replay hash mismatch" });
  });

  test("queues a generic alert and records the streak activity", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const device = await addDevice(t, couple.second.userId, { locale: "en", token: "b" });
    await addDevice(t, couple.first.userId, { locale: "en", token: "a" });
    const memoryId = await createMemory(couple.first);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });

    const [result] = await memoryThread(couple.first, memoryId);
    const rows = await outbox(t);
    expect(rows).toHaveLength(1);
    const [row] = rows;
    expect(row.recipient_user_id).toBe(couple.second.userId);
    expect(row.payload).toEqual({
      type: "thread_message_sent",
      couple_id: couple.coupleId,
      thread_id: result.thread_id,
      message_id: result.message_id,
      actor_user_id: couple.first.userId,
      route: "memories",
      deeplink: "paeonia://memories",
      memory_id: memoryId,
    });
    expect(row.dedupe_key).toBe(`thread_message_sent:${result.message_id}:${device.id}`);
    expect(row.apns_collapse_id).toBe(`thread:${result.thread_id}`);
    expect([row.title, row.body]).toEqual(["First Partner sent you a message", "Open Paeonia to read it and reply."]);
    expect(JSON.stringify(rows)).not.toContain("Secret message");

    const events = await t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events.filter((event) => event.activity_kind === "thread_message_sent")).toMatchObject([
      { dedupe_key: `thread_message_sent:${result.message_id}`, metadata: { thread_id: result.thread_id }, user_id: couple.first.userId },
    ]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a disabled messages preference suppresses the alert but not the activity", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const memoryId = await createMemory(couple.first);
    const [{ thread_id }] = await memoryThread(couple.first, memoryId);
    expect(await outbox(t)).toHaveLength(2);
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").withIndex("by_user_id", (q) => q.eq("user_id", couple.second.userId)).unique();
      await ctx.db.patch(preference!._id, { messages_enabled: false });
    });
    const [sent] = await send(couple.first, thread_id, { p_body: "Secret message text three" });
    expect((await outbox(t)).filter((row) => row.kind === "thread_message_sent")).toHaveLength(1);
    const events = await t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events.some((event) => event.dedupe_key === `thread_message_sent:${sent.message_id}`)).toBe(true);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the alert names the sender but not the text, in the device language", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "nb-NO" });
    const memoryId = await createMemory(couple.first);
    await memoryThread(couple.first, memoryId);
    const row = (await outbox(t)).find((item) => item.kind === "thread_message_sent")!;
    expect([row.title, row.body]).toEqual(["First Partner sendte deg en melding", "Åpne Paeonia for å lese og svare."]);
    expect(JSON.stringify(row)).not.toContain("Secret message");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a missing or hidden memory is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const denied = { code: "42501", message: "active entitled memory access is required" };
    expect(await failure(memoryThread(couple.first, newUuid()))).toEqual(denied);
    const memoryId = await createMemory(couple.first);
    await couple.first.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1 });
    expect(await failure(memoryThread(couple.first, memoryId))).toEqual(denied);
  });
});

describe("daily question threads", () => {
  test("starts a thread once both partners answered and uses the daily payload", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en" });
    const instanceId = await dailyInstance(t, couple);
    const [result] = await dailyThread(couple.first, instanceId);
    expect(await t.run((ctx) => ctx.db.query("daily_question_threads").collect())).toMatchObject([
      { instance_id: instanceId, thread_id: result.thread_id },
    ]);
    expect(await t.run((ctx) => ctx.db.query("conversation_threads").first())).toMatchObject({ kind: "daily_question" });
    const row = (await outbox(t)).find((item) => item.kind === "thread_message_sent")!;
    expect(row.payload).toEqual({
      type: "thread_message_sent",
      couple_id: couple.coupleId,
      thread_id: result.thread_id,
      message_id: result.message_id,
      actor_user_id: couple.first.userId,
      route: "daily",
      deeplink: `paeonia://daily/chat?instanceId=${instanceId}`,
      instance_id: instanceId,
    });
    const [again] = await dailyThread(couple.second, instanceId, "reply");
    expect(again.thread_id).toBe(result.thread_id);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("needs the caller's answer and the partner's answer", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const onlyPartner = await dailyInstance(t, couple, [couple.second]);
    expect(await failure(dailyThread(couple.first, onlyPartner))).toEqual({
      code: "42501",
      message: "you must answer this daily question before starting its thread",
    });
    const onlyMe = await dailyInstance(t, couple, [couple.first]);
    expect(await failure(dailyThread(couple.first, onlyMe))).toEqual({
      code: "23514",
      message: "daily question thread requires both partners to answer",
    });
    expect(await t.run((ctx) => ctx.db.query("conversation_threads").collect())).toHaveLength(0);
  });

  test("refuses unknown and shuffled questions", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const missing = { code: "22023", message: "daily question instance was not found" };
    expect(await failure(dailyThread(couple.first, newUuid()))).toEqual(missing);
    const instanceId = await dailyInstance(t, couple);
    await t.run(async (ctx) => {
      const instance = await ctx.db.query("daily_question_instances").first();
      await ctx.db.patch(instance!._id, { status: "shuffled" });
    });
    expect(await failure(dailyThread(couple.first, instanceId))).toEqual(missing);
  });

  test("strangers, former partners, and unentitled couples are refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await dailyInstance(t, couple);
    const stranger = await createSignedInUser(t);
    const denied = { code: "42501", message: "active entitled couple access is required" };
    expect(await failure(dailyThread(stranger, instanceId))).toEqual(denied);

    const unentitled = await createCouple(t, { entitled: false });
    expect(await failure(dailyThread(unentitled.first, await dailyInstance(t, unentitled)))).toEqual(denied);

    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(dailyThread(couple.first, instanceId))).toEqual(denied);
    expect(await failure(dailyThread(couple.second, instanceId))).toEqual(denied);
  });
});

describe("send_thread_message", () => {
  async function thread(t: TestConvex) {
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [{ thread_id }] = await memoryThread(couple.first, memoryId);
    return { couple, threadId: thread_id, memoryId };
  }

  test("returns the thread and message ids and trims the body", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const [row] = await send(couple.second, threadId.toUpperCase(), { p_body: "  hello  " });
    expect(row.thread_id).toBe(threadId);
    const message = await t.run((ctx) => ctx.db.query("thread_messages").withIndex("by_uuid", (q) => q.eq("id", row.message_id)).unique());
    expect(message).toMatchObject({ body: "hello", sender_user_id: couple.second.userId, thread_id: threadId });
  });

  test("a replay does not send twice", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const args = { ...op(), p_thread_id: threadId, p_body: "once", p_media_asset_ids: null };
    const first = await couple.first.as.mutation(api.threads.send_thread_message, args);
    expect(await couple.first.as.mutation(api.threads.send_thread_message, args)).toEqual(first);
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(2);
  });

  test.each([
    ["an empty message", { p_body: "  " }, "thread message must include text or media"],
    ["a long message", { p_body: "x".repeat(4001) }, "thread message body is too long"],
    ["more than 10 media assets", { p_media_asset_ids: Array.from({ length: 11 }, () => newUuid()) }, "thread messages can include at most 10 media assets"],
  ])("rejects %s", async (_name, args, message) => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    expect(await failure(send(couple.first, threadId, args))).toEqual({ code: "23514", message });
  });

  test("rejects repeated media ids and unusable media", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const id = newUuid();
    expect(await failure(send(couple.first, threadId, { p_media_asset_ids: [id, id] }))).toEqual({
      code: "23514",
      message: "thread message media asset ids must be unique",
    });
    expect(await failure(send(couple.first, threadId, { p_media_asset_ids: [id] }))).toEqual({
      code: "23514",
      message: "thread message media asset is not usable",
    });
    const partnerPhoto = await uploadAsset(t, couple.second, photo(couple.coupleId, "thread_message_media", "thread_media"));
    expect(await failure(send(couple.first, threadId, { p_media_asset_ids: [partnerPhoto.assetId] }))).toEqual({
      code: "23514",
      message: "thread message media asset is not usable",
    });
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(1);
  });

  test("sends a photo message under the id the upload reserved", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const a = await uploadAsset(t, couple.first, photo(couple.coupleId, "thread_message_media", "thread_media"));
    const [row] = await send(couple.first, threadId, { p_body: null, p_media_asset_ids: [a.assetId] });
    expect(row.message_id).toBe(a.parentId);
    const messages = await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: threadId });
    const message = messages.find((item: { message_id: string }) => item.message_id === a.parentId);
    expect(message).toMatchObject({ body: null, media_asset_ids: [a.assetId] });
    expect(message!.media).toEqual([
      { media_asset_id: a.assetId, media_type: "image", width: expect.anything(), height: expect.anything(), duration_ms: null },
    ]);
    expect(message!.media_states).toEqual([
      {
        media_asset_id: a.assetId,
        sort_order: 1,
        asset_deleted_at: null,
        asset_moderation_status: "visible",
        asset_storage_delete_status: "none",
        updated_at: expect.any(String),
      },
    ]);
    const [url] = await couple.second.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: a.assetId });
    expect(url.signed_url).toContain("/media?asset=");
  });

  test("a reply points at an earlier message in the same thread", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const [first] = await send(couple.first, threadId, { p_body: "question" });
    const [reply] = await send(couple.second, threadId, { p_body: "answer", p_reply_to_message_id: first.message_id.toUpperCase() });
    const rows = await couple.first.as.query(api.threads.get_thread_messages, { p_thread_id: threadId });
    const replyRow = rows.find((row: { message_id: string }) => row.message_id === reply.message_id);
    expect(replyRow?.reply_to_message_id).toBe(first.message_id);
  });

  test("a reply to another thread's message or a removed message is refused", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const otherMemory = await createMemory(couple.first);
    const [{ message_id: elsewhere }] = await memoryThread(couple.first, otherMemory);
    expect(await failure(send(couple.first, threadId, { p_reply_to_message_id: elsewhere }))).toEqual({
      code: "23514",
      message: "reply target must be in the same thread",
    });
    const [target] = await send(couple.first, threadId, { p_body: "soon hidden" });
    await t.run(async (ctx) => {
      const row = await ctx.db.query("thread_messages").withIndex("by_uuid", (q) => q.eq("id", target.message_id)).unique();
      await ctx.db.patch(row!._id, { moderation_status: "hidden" });
    });
    expect(await failure(send(couple.second, threadId, { p_reply_to_message_id: target.message_id }))).toEqual({
      code: "23514",
      message: "reply target is not available",
    });
  });

  test("a plain send replays the same way it did before replies existed", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const args = { ...op(), p_thread_id: threadId, p_body: "once" };
    const first = await couple.first.as.mutation(api.threads.send_thread_message, args);
    expect(await couple.first.as.mutation(api.threads.send_thread_message, { ...args, p_reply_to_message_id: null })).toEqual(first);
  });

  test("strangers and former partners cannot send", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    const stranger = await createSignedInUser(t);
    const denied = { code: "42501", message: "active entitled thread access is required" };
    expect(await failure(send(stranger, threadId))).toEqual(denied);
    expect(await failure(send(couple.first, newUuid()))).toEqual(denied);
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(send(couple.first, threadId))).toEqual(denied);
    expect(await failure(send(couple.second, threadId))).toEqual(denied);
  });

  test("an unentitled couple cannot send", async () => {
    const t = newTest();
    const { couple, threadId } = await thread(t);
    await t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect(await failure(send(couple.first, threadId))).toEqual({
      code: "42501",
      message: "active entitled thread access is required",
    });
  });

  test("a deleted or hidden thread refuses messages", async () => {
    const t = newTest();
    const { couple, threadId, memoryId } = await thread(t);
    await couple.first.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1 });
    expect(await failure(send(couple.first, threadId))).toEqual({
      code: "42501",
      message: "active entitled thread access is required",
    });
  });
});

describe("edit_thread_message", () => {
  async function sent(t: TestConvex) {
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [{ thread_id, message_id }] = await memoryThread(couple.first, memoryId, "frist try");
    return { couple, threadId: thread_id, messageId: message_id };
  }
  const edit = (user: TestUser, messageId: string, body: string) =>
    user.as.mutation(api.threads.edit_thread_message, { p_message_id: messageId, p_body: body });
  const row = (t: TestConvex, messageId: string) =>
    t.run((ctx) => ctx.db.query("thread_messages").withIndex("by_uuid", (q) => q.eq("id", messageId)).unique());

  test("the sender changes the text and both partners read the edit", async () => {
    const t = newTest();
    const { couple, threadId, messageId } = await sent(t);
    tick(4 * 60);
    await edit(couple.first, messageId.toUpperCase(), "  first try  ");
    expect(await row(t, messageId)).toMatchObject({ body: "first try", edited_at: new Date().toISOString() });
    const rows = await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: threadId });
    expect(rows[0]).toMatchObject({ body: "first try", edited_at: new Date().toISOString() });
  });

  test("saving the same text leaves the message unedited", async () => {
    const t = newTest();
    const { couple, messageId } = await sent(t);
    await edit(couple.first, messageId, " frist try ");
    expect((await row(t, messageId))?.edited_at).toBeUndefined();
  });

  test("closes five minutes after sending", async () => {
    const t = newTest();
    const { couple, messageId } = await sent(t);
    tick(5 * 60 + 1);
    expect(await failure(edit(couple.first, messageId, "late"))).toEqual({
      code: "23514",
      message: "messages can only be edited for 5 minutes after sending",
    });
  });

  test("only the sender can edit, and only to some text", async () => {
    const t = newTest();
    const { couple, messageId } = await sent(t);
    expect(await failure(edit(couple.second, messageId, "mine now"))).toEqual({
      code: "42501",
      message: "only the sender can edit a message",
    });
    expect(await failure(edit(couple.first, messageId, "   "))).toEqual({
      code: "23514",
      message: "an edited message must keep its text",
    });
    expect(await failure(edit(couple.first, messageId, "x".repeat(4001)))).toEqual({
      code: "23514",
      message: "thread message body is too long",
    });
  });

  test("a message without text or a hidden message can't be edited", async () => {
    const t = newTest();
    const { couple, messageId } = await sent(t);
    await t.run(async (ctx) => {
      const message = await ctx.db.query("thread_messages").withIndex("by_uuid", (q) => q.eq("id", messageId)).unique();
      await ctx.db.patch(message!._id, { body: undefined });
    });
    expect(await failure(edit(couple.first, messageId, "words"))).toEqual({
      code: "23514",
      message: "only messages with text can be edited",
    });
    await t.run(async (ctx) => {
      const message = await ctx.db.query("thread_messages").withIndex("by_uuid", (q) => q.eq("id", messageId)).unique();
      await ctx.db.patch(message!._id, { moderation_status: "hidden" });
    });
    expect(await failure(edit(couple.first, messageId, "words"))).toEqual({
      code: "23514",
      message: "message is not available",
    });
  });

  test("a voice message can't be edited even with text", async () => {
    const t = newTest();
    const { couple, threadId } = await sent(t);
    const voice = await uploadAsset(t, couple.first, {
      kind: "thread_message_media",
      purpose: "voice_note",
      mediaType: "voice",
      extension: "m4a",
      mime: "audio/mp4",
      coupleId: couple.coupleId,
    });
    await send(couple.first, threadId, { p_body: "words", p_media_asset_ids: [voice.assetId] });
    expect(await failure(edit(couple.first, voice.parentId, "other words"))).toEqual({
      code: "23514",
      message: "only messages with text can be edited",
    });
  });

  test("a photo caption can be edited", async () => {
    const t = newTest();
    const { couple, threadId } = await sent(t);
    const a = await uploadAsset(t, couple.first, photo(couple.coupleId, "thread_message_media", "thread_media"));
    await send(couple.first, threadId, { p_body: "caption", p_media_asset_ids: [a.assetId] });
    await edit(couple.first, a.parentId, "better caption");
    expect((await row(t, a.parentId))?.body).toBe("better caption");
  });

  test("a former partner can't edit", async () => {
    const t = newTest();
    const { couple, messageId } = await sent(t);
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(edit(couple.first, messageId, "still mine"))).toEqual({
      code: "42501",
      message: "active entitled thread access is required",
    });
  });
});

describe("reads", () => {
  test("get_conversation_threads lists threads with their last message, empty threads first", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [{ thread_id: memoryThreadId, message_id }] = await memoryThread(couple.first, memoryId, "memory hello");
    tick();
    const instanceId = await dailyInstance(t, couple);
    const [daily] = await dailyThread(couple.second, instanceId, "daily hello");
    tick();
    const [last] = await send(couple.first, memoryThreadId, { p_body: "latest" });
    // A thread without messages sorts before the others, like a descending order with nulls first.
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      await ctx.db.insert("conversation_threads", {
        id: "00000000-0000-4000-8000-0000000000aa",
        couple_id: couple.coupleId,
        kind: "memory",
        created_by_user_id: couple.first.userId,
        moderation_status: "visible",
        created_at: now,
        updated_at: now,
      });
    });

    const rows = await couple.second.as.query(api.threads.get_conversation_threads, {});
    expect(rows.map((row: { thread_id: string }) => row.thread_id)).toEqual([
      "00000000-0000-4000-8000-0000000000aa",
      memoryThreadId,
      daily.thread_id,
    ]);
    expect(rows[1]).toEqual({
      thread_id: memoryThreadId,
      couple_id: couple.coupleId,
      kind: "memory",
      daily_question_instance_id: null,
      memory_id: memoryId,
      created_by_user_id: couple.first.userId,
      created_at: expect.any(String),
      updated_at: expect.any(String),
      deleted_at: null,
      moderation_status: "visible",
      last_message_id: last.message_id,
      last_message_at: new Date().toISOString(),
      last_message_sender_user_id: couple.first.userId,
      last_message_deleted_at: null,
      last_message_moderation_status: "visible",
      last_message_body: "latest",
      last_message_media_type: null,
      viewer_read_through_at: null,
    });
    expect(rows[2]).toMatchObject({ kind: "daily_question", daily_question_instance_id: instanceId, memory_id: null, last_message_body: "daily hello" });
    expect(rows[0]).toMatchObject({ last_message_id: null, last_message_at: null, last_message_body: null });
    expect(message_id).toBeTruthy();
  });

  test("get_conversation_threads leaves out a question chat once an answer is deleted or hidden", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const deletedInstanceId = await dailyInstance(t, couple);
    await dailyThread(couple.second, deletedInstanceId);
    const hiddenInstanceId = await dailyInstance(t, couple);
    await dailyThread(couple.second, hiddenInstanceId);
    const instanceIds = async () =>
      (await couple.first.as.query(api.threads.get_conversation_threads, {})).map(
        (row: { daily_question_instance_id: string | null }) => row.daily_question_instance_id,
      );
    expect(await instanceIds()).toHaveLength(2);

    await t.run(async (ctx) => {
      const answerOf = async (instanceId: string) =>
        (await ctx.db
          .query("daily_question_answers")
          .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId).eq("user_id", couple.second.userId))
          .unique())!;
      await ctx.db.patch((await answerOf(deletedInstanceId))._id, { deleted_at: new Date().toISOString() });
      await ctx.db.patch((await answerOf(hiddenInstanceId))._id, { moderation_status: "hidden" });
    });
    expect(await instanceIds()).toEqual([]);
  });

  test("get_thread_messages orders by time and hides the text of removed messages", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [{ thread_id, message_id }] = await memoryThread(couple.first, memoryId, "first");
    tick();
    const [second] = await send(couple.second, thread_id, { p_body: "second" });
    await t.run(async (ctx) => {
      const message = await ctx.db.query("thread_messages").withIndex("by_uuid", (q) => q.eq("id", second.message_id)).unique();
      await ctx.db.patch(message!._id, { moderation_status: "hidden" });
    });
    const rows = await couple.first.as.query(api.threads.get_thread_messages, { p_thread_id: thread_id });
    expect(rows.map((row: { message_id: string }) => row.message_id)).toEqual([message_id, second.message_id]);
    expect(rows[0]).toEqual({
      thread_id,
      message_id,
      sender_user_id: couple.first.userId,
      body: "first",
      reply_to_message_id: null,
      created_at: expect.any(String),
      edited_at: null,
      deleted_at: null,
      moderation_status: "visible",
      media_asset_ids: [],
      media: [],
      media_states: [],
    });
    expect(rows[1]).toMatchObject({ body: null, moderation_status: "hidden" });
  });

  test("strangers and former partners get nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [{ thread_id }] = await memoryThread(couple.first, memoryId);
    const stranger = await createSignedInUser(t);
    const read = (user: TestUser) => user.as.query(api.threads.get_thread_messages, { p_thread_id: thread_id });
    expect(await read(stranger)).toEqual([]);
    expect(await read(couple.second)).toHaveLength(1);
    expect(await failure(stranger.as.query(api.threads.get_conversation_threads, {}))).toEqual({
      code: "42501",
      message: "active entitled couple access is required",
    });
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await read(couple.first)).toEqual([]);
    expect(await read(couple.second)).toEqual([]);
    expect(await failure(couple.second.as.query(api.threads.get_conversation_threads, {}))).toMatchObject({ code: "42501" });
  });

  test("an unentitled couple gets nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [{ thread_id }] = await memoryThread(couple.first, memoryId);
    await t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect(await couple.first.as.query(api.threads.get_thread_messages, { p_thread_id: thread_id })).toEqual([]);
    expect(await failure(couple.first.as.query(api.threads.get_conversation_threads, {}))).toMatchObject({ code: "42501" });
  });
});
