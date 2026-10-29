import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { insertNotificationOutbox } from "./lib/notifications";
import { failure, op } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date(NOW)); });
afterEach(() => { vi.useRealTimers(); });

async function setup() {
  const t = newTest();
  const couple = await createCouple(t);
  const device = await addDevice(t, couple.second.userId);
  const obsolete = (ids: string[], now = NOW) => couple.second.as.query(api.notificationState.get_obsolete_notifications, {
    p_notification_ids: ids, p_now: now,
  });
  const queue = async (kind: Parameters<typeof insertNotificationOutbox>[1]["kind"], payload: Record<string, unknown>) => {
    await t.run(ctx => insertNotificationOutbox(ctx, {
      recipient_user_id: couple.second.userId, target_device_id: device.id,
      push_token_hash: device.push_token_hash, apns_environment: "sandbox", kind,
      payload: { type: kind, couple_id: couple.coupleId, ...payload },
    }));
    return (await t.run(ctx => ctx.db.query("notification_outbox").order("desc").first()))!.id;
  };
  const prepare = (id: string) => t.mutation(internal.pushQueue.prepare_notification, { outbox_id: id });
  return { t, couple, device, obsolete, queue, prepare };
}

test("a stranger, the partner and a signed-out caller cannot inspect another person's notifications", async () => {
  const s = await setup();
  const id = await s.queue("memory_created", { memory_id: newUuid() });
  const stranger = await createSignedInUser(s.t);
  const args = { p_notification_ids: [id], p_now: NOW };
  for (const caller of [stranger, s.couple.first]) {
    expect((await failure(caller.as.query(api.notificationState.get_obsolete_notifications, args))).code).toBe("42501");
  }
  expect((await failure(s.t.query(api.notificationState.get_obsolete_notifications, args))).code).toBe("42501");
  expect(await s.obsolete([newUuid()])).toHaveLength(1);
});

test("reading a real chat makes both its queued and delivered alerts obsolete", async () => {
  const s = await setup();
  const memory = newUuid();
  await s.couple.first.as.mutation(api.memories.create_memory, {
    ...op(), p_memory_id: memory, p_title: "A day together", p_memory_date: "2026-10-10", p_note_body: "A memory",
  });
  const [message] = await s.couple.first.as.mutation(api.threads.create_memory_thread_with_message, {
    ...op(), p_memory_id: memory, p_body: "Hello",
  });
  const row = (await s.t.run(ctx => ctx.db.query("notification_outbox").collect()))
    .find(row => row.kind === "thread_message_sent")!;
  expect(await s.prepare(row.id)).not.toBeNull();
  expect(await s.obsolete([row.id])).toEqual([]);
  await s.couple.second.as.mutation(api.chatPresence.mark_thread_read, {
    p_thread_id: message.thread_id, p_message_id: message.message_id,
  });
  expect(await s.obsolete([row.id])).toEqual([row.id]);
  expect(await s.prepare(row.id)).toBeNull();
});

test("deleted memories and deleted, seen or expired stories no longer send or remain delivered", async () => {
  const s = await setup();
  const memory = newUuid();
  await s.couple.first.as.mutation(api.memories.create_memory, {
    ...op(), p_memory_id: memory, p_title: "A day together", p_memory_date: "2026-10-10", p_note_body: "A memory",
  });
  const memoryAlert = (await s.t.run(ctx => ctx.db.query("notification_outbox").collect()))[0].id;
  expect(await s.obsolete([memoryAlert])).toEqual([]);
  await s.t.run(async ctx => {
    const row = await ctx.db.query("memories").withIndex("by_uuid", q => q.eq("id", memory)).unique();
    await ctx.db.patch(row!._id, { deleted_at: NOW });
  });
  expect(await s.prepare(memoryAlert)).toBeNull();
  expect(await s.obsolete([memoryAlert])).toEqual([memoryAlert]);
  for (const state of ["deleted", "seen", "expired"] as const) {
    const story = newUuid();
    const document = await s.t.run(ctx => ctx.db.insert("stories", {
      id: story, couple_id: s.couple.coupleId, author_user_id: s.couple.first.userId,
      media_asset_id: newUuid(), created_at: NOW,
    }));
    const id = await s.queue("story_posted", { story_id: story });
    expect(await s.obsolete([id])).toEqual([]);
    await s.t.run(ctx => ctx.db.patch(document, state === "deleted" ? { deleted_at: NOW }
      : state === "seen" ? { seen_at: NOW } : { created_at: "2026-10-09T12:00:00.000Z" }));
    expect(await s.prepare(id)).toBeNull();
    expect(await s.obsolete([id])).toEqual([id]);
  }
});

test("game invites stop being valid after acceptance or 15 minutes, and games collapse independently", async () => {
  const s = await setup();
  for (const kind of ["ludo", "mind_meld"] as const) {
    await s.couple.first.as.mutation(api.games.send_game_invite, { p_kind: kind });
  }
  const rows = await s.t.run(ctx => ctx.db.query("notification_outbox").collect());
  expect(new Set(rows.map(row => row.apns_collapse_id)).size).toBe(2);
  const ludo = rows.find(row => row.payload.game_kind === "ludo")!;
  const meld = rows.find(row => row.payload.game_kind === "mind_meld")!;
  expect(await s.obsolete([ludo.id, meld.id])).toEqual([]);
  expect(await s.prepare(ludo.id)).not.toBeNull();
  await s.couple.second.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: true });
  expect(await s.obsolete([ludo.id, meld.id])).toEqual([ludo.id]);
  expect(await s.prepare(ludo.id)).toBeNull();
  vi.setSystemTime(new Date("2026-10-10T12:15:00.000Z"));
  expect(await s.obsolete([meld.id], new Date().toISOString())).toEqual([meld.id]);
  expect(await s.prepare(meld.id)).toBeNull();
});

test("delivered reminders expire even when their backing row remains", async () => {
  const s = await setup();
  const id = await s.queue("date_reminder", { expires_at: "2026-10-10T12:01:00.000Z" });
  expect(await s.obsolete([id])).toEqual([]);
  expect(await s.obsolete([id], "2026-10-10T12:01:00.000Z")).toEqual([id]);
});

test("reading an earlier message in the same millisecond keeps the later alert", async () => {
  const s = await setup();
  const memory = newUuid();
  await s.couple.first.as.mutation(api.memories.create_memory, {
    ...op(), p_memory_id: memory, p_title: "Together", p_memory_date: "2026-10-10", p_note_body: "A memory",
  });
  const [first] = await s.couple.first.as.mutation(api.threads.create_memory_thread_with_message, {
    ...op(), p_memory_id: memory, p_body: "One",
  });
  const [second] = await s.couple.first.as.mutation(api.threads.send_thread_message, {
    ...op(), p_thread_id: first.thread_id, p_body: "Two",
  });
  const [older, newer] = [first.message_id, second.message_id].sort();
  const alert = await s.queue("thread_message_sent", { message_id: newer });
  await s.couple.second.as.mutation(api.chatPresence.mark_thread_read, {
    p_thread_id: first.thread_id, p_message_id: older,
  });
  expect(await s.obsolete([alert])).toEqual([]);
  expect(await s.prepare(alert)).not.toBeNull();
  await s.couple.second.as.mutation(api.chatPresence.mark_thread_read, {
    p_thread_id: first.thread_id, p_message_id: newer,
  });
  expect(await s.obsolete([alert])).toEqual([alert]);
});
