import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, components } from "./_generated/api";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { newUuid } from "./lib/ids";
import { chatTypingRoom, removePresenceRooms } from "./lib/presence";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { failure, op } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-11T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

/** A daily question both partners answered, so its chat can start. */
async function answeredInstance(t: TestConvex, couple: TestCouple) {
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
    for (const user of [couple.first, couple.second]) {
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

const presence = (user: TestCouple["first"], instanceId: string) =>
  user.as.query(api.chatPresence.get_daily_chat_presence, { p_instance_id: instanceId });

describe("typing", () => {
  test("the partner sees typing until it stops, and never their own", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await answeredInstance(t, couple);

    await couple.first.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: true });
    expect((await presence(couple.second, instanceId)).partner_typing).toBe(true);
    expect((await presence(couple.first, instanceId)).partner_typing).toBe(false);

    tick(3);
    await couple.first.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: true });
    expect((await presence(couple.second, instanceId)).partner_typing).toBe(true);

    await couple.first.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: false });
    expect((await presence(couple.second, instanceId)).partner_typing).toBe(false);
    // A second stop, such as on send after the idle stop, changes nothing.
    await couple.first.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: false });
    expect((await presence(couple.second, instanceId)).partner_typing).toBe(false);
  });

  test("strangers cannot type or read presence", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await answeredInstance(t, couple);
    const stranger = await createSignedInUser(t);

    expect(
      await failure(stranger.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: true })),
    ).toEqual({ code: "42501", message: "active entitled couple access is required" });
    expect(await presence(stranger, instanceId)).toEqual({
      partner_typing: false,
      partner_last_read_message_id: null,
      partner_read_at: null,
    });
  });

  test("typing ends 4 seconds after the last heartbeat, such as when the app was killed", async () => {
    // The presence component times sessions out with scheduled functions, so fake every timer.
    vi.useFakeTimers();
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await answeredInstance(t, couple);
    await couple.first.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: true });
    expect((await presence(couple.second, instanceId)).partner_typing).toBe(true);

    const lastHeartbeat = Date.now();
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(Date.now() - lastHeartbeat).toBeGreaterThanOrEqual(4_000);
    expect((await presence(couple.second, instanceId)).partner_typing).toBe(false);
  });

  test("ending the relationship or deleting the account clears typing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await answeredInstance(t, couple);
    const room = chatTypingRoom(couple.coupleId, instanceId);
    const typists = () => t.run((ctx) => ctx.runQuery(components.presence.public.listRoom, { roomId: room }));
    await couple.first.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: true });
    await couple.second.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: true });
    expect(await typists()).toHaveLength(2);

    await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.first.userId, "user_left"));
    expect(await typists()).toEqual([]);
    expect((await failure(couple.second.as.mutation(api.chatPresence.set_daily_chat_typing, { p_instance_id: instanceId, p_is_typing: true }))).code).toBe("42501");

    // Account deletion also clears whatever a user still has, in any room.
    const leftover = chatTypingRoom(newUuid(), newUuid());
    await t.run((ctx) => ctx.runMutation(components.presence.public.heartbeat, { roomId: leftover, userId: couple.first.userId, sessionId: "s" }));
    await t.run((ctx) => removePresenceRooms(ctx, [couple.first.userId], ""));
    expect(await t.run((ctx) => ctx.runQuery(components.presence.public.listUser, { userId: couple.first.userId }))).toEqual([]);
  });
});

describe("read receipts", () => {
  test("marking read moves forward only and the partner sees it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await answeredInstance(t, couple);
    const [first] = await couple.first.as.mutation(api.threads.create_daily_question_thread_with_message, {
      ...op(),
      p_instance_id: instanceId,
      p_body: "one",
    });
    tick(5);
    const [second] = await couple.first.as.mutation(api.threads.send_thread_message, {
      ...op(),
      p_thread_id: first.thread_id,
      p_body: "two",
    });

    await couple.second.as.mutation(api.chatPresence.mark_thread_read, {
      p_thread_id: first.thread_id,
      p_message_id: second.message_id,
    });
    await couple.second.as.mutation(api.chatPresence.mark_thread_read, {
      p_thread_id: first.thread_id,
      p_message_id: first.message_id,
    });

    const state = await presence(couple.first, instanceId);
    expect(state.partner_last_read_message_id).toBe(second.message_id);
    expect(state.partner_read_at).toEqual(expect.any(String));
    expect((await presence(couple.second, instanceId)).partner_last_read_message_id).toBeNull();
  });

  test("the thread list carries how far the caller has read", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await answeredInstance(t, couple);
    const [message] = await couple.first.as.mutation(api.threads.create_daily_question_thread_with_message, {
      ...op(),
      p_instance_id: instanceId,
      p_body: "hi",
    });
    const readThrough = async (user: TestCouple["first"]) =>
      (await user.as.query(api.threads.get_conversation_threads, {}))[0].viewer_read_through_at;

    expect(await readThrough(couple.second)).toBeNull();
    tick(5);
    await couple.second.as.mutation(api.chatPresence.mark_thread_read, {
      p_thread_id: message.thread_id,
      p_message_id: message.message_id,
    });
    expect(await readThrough(couple.second)).toBe("2026-10-11T12:00:00.000Z");
    expect(await readThrough(couple.first)).toBeNull();
  });

  test("a message from another thread is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const [a] = await couple.first.as.mutation(api.threads.create_daily_question_thread_with_message, {
      ...op(),
      p_instance_id: await answeredInstance(t, couple),
      p_body: "a",
    });
    const [b] = await couple.first.as.mutation(api.threads.create_daily_question_thread_with_message, {
      ...op(),
      p_instance_id: await answeredInstance(t, couple),
      p_body: "b",
    });
    expect(
      await failure(couple.second.as.mutation(api.chatPresence.mark_thread_read, { p_thread_id: a.thread_id, p_message_id: b.message_id })),
    ).toEqual({ code: "23514", message: "read message must be in the thread" });
  });
});
