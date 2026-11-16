import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
// Voice and video calls: who may do what, every call state in docs/calling-plan.md, and what an
// ended call leaves in the couple chat.
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { failure } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple } from "./test.setup";

const START = Date.parse("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(START));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

const liveCalls = (t: TestConvex) => t.run((ctx) => ctx.db.query("calls").collect());
const callRows = (t: TestConvex) =>
  t.run(async (ctx) => (await ctx.db.query("thread_messages").collect()).filter((row) => row.call !== undefined));
const missedCallPushes = (t: TestConvex) =>
  t.run(async (ctx) => (await ctx.db.query("notification_outbox").collect()).filter((row) => row.kind === "missed_call"));

const op = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: newUuid(),
  p_client_sequence: 1,
  p_local_created_at: new Date().toISOString(),
});

/** Sets how `userId` shares their location in the couple: off, on, or on and paused for an hour. */
async function setLocationSharing(t: TestConvex, coupleId: string, userId: string, state: "off" | "on" | "paused") {
  await t.run(async (ctx) => {
    const existing = await ctx.db
      .query("location_sharing_preferences")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
      .unique();
    if (existing) await ctx.db.delete(existing._id);
    const now = new Date().toISOString();
    await ctx.db.insert("location_sharing_preferences", {
      couple_id: coupleId,
      user_id: userId,
      is_enabled: state !== "off",
      source: "settings_toggle",
      updates_while_closed: false,
      paused_until: state === "paused" ? new Date(Date.now() + 3_600_000).toISOString() : undefined,
      created_at: now,
      updated_at: now,
    });
  });
}

/** The first partner calls the second. Returns the call id. */
async function call(couple: TestCouple): Promise<string> {
  const callId = newUuid();
  const started = await couple.first.as.mutation(api.calls.start_call, { p_call_id: callId, p_device_id: newUuid() });
  expect(started).toEqual({ call_id: callId, answered_incoming: false });
  return callId;
}

async function setup() {
  const t = newTest();
  const couple = await createCouple(t);
  await addDevice(t, couple.first.userId);
  await addDevice(t, couple.second.userId);
  return { t, couple };
}

describe("access", () => {
  test("someone outside the couple can reach none of a call", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    const stranger = await createSignedInUser(t, {});
    const strangerCouple = await createCouple(t);
    for (const outsider of [stranger, strangerCouple.first]) {
      expect((await failure(outsider.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() }))).code).toBe("42501");
      expect((await failure(outsider.as.mutation(api.calls.decline_call, { p_call_id: callId }))).code).toBe("42501");
      expect((await failure(outsider.as.mutation(api.calls.end_call, { p_call_id: callId }))).code).toBe("42501");
      expect((await failure(outsider.as.mutation(api.calls.call_heartbeat, { p_call_id: callId }))).code).toBe("42501");
      expect((await failure(outsider.as.mutation(api.calls.create_call_live_ticket, { p_call_id: callId }))).code).toBe("42501");
      expect((await failure(outsider.as.action(api.calls.get_call_ice_servers, { p_call_id: callId }))).code).toBe("42501");
    }
    expect(await stranger.as.query(api.calls.get_live_call, {})).toBeNull();
    expect(await strangerCouple.first.as.query(api.calls.get_live_call, {})).toBeNull();
    expect((await failure(stranger.as.query(api.calls.get_call_context, {}))).code).toBe("42501");
    expect((await failure(stranger.as.mutation(api.calls.start_call, { p_call_id: newUuid(), p_device_id: newUuid() }))).code).toBe("42501");
    // Nothing they tried changed the call.
    expect(await liveCalls(t)).toMatchObject([{ id: callId, state: "ringing" }]);
  });

  test("a couple without access cannot start a call", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    const refused = await failure(couple.first.as.mutation(api.calls.start_call, { p_call_id: newUuid(), p_device_id: newUuid() }));
    expect(refused.code).toBe("42501");
    expect(await liveCalls(t)).toEqual([]);
  });

  test("a signed-out caller is refused", async () => {
    const t = newTest();
    await expect(t.mutation(api.calls.start_call, { p_call_id: newUuid(), p_device_id: newUuid() })).rejects.toThrow();
    await expect(t.query(api.calls.get_live_call, {})).rejects.toThrow();
  });

  test("the ticket joins the couple's call channel, only for a member of the live call", async () => {
    process.env.PAEONIA_LIVE_RELAY_URL = "wss://relay.example.test/canvas";
    process.env.PAEONIA_LIVE_RELAY_SECRET = "relay-secret";
    try {
      const { couple } = await setup();
      const callId = await call(couple);
      const ticket = await couple.second.as.mutation(api.calls.create_call_live_ticket, { p_call_id: callId });
      const claims = JSON.parse(atob(ticket!.ticket.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")));
      expect(claims).toMatchObject({ c: couple.coupleId, u: couple.second.userId, ch: "call" });
      await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
      expect((await failure(couple.second.as.mutation(api.calls.create_call_live_ticket, { p_call_id: callId }))).message).toBe("call_not_live");
    } finally {
      delete process.env.PAEONIA_LIVE_RELAY_URL;
      delete process.env.PAEONIA_LIVE_RELAY_SECRET;
    }
  });

  test("ICE servers are empty without a TURN key, and relay only while the viewer has paused location sharing", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    const relayOnly = async () => (await couple.second.as.action(api.calls.get_call_ice_servers, { p_call_id: callId })).relay_only;
    expect(await couple.second.as.action(api.calls.get_call_ice_servers, { p_call_id: callId })).toEqual({ ice_servers: [], relay_only: false });
    await setLocationSharing(t, couple.coupleId, couple.second.userId, "on");
    expect(await relayOnly()).toBe(false);
    await setLocationSharing(t, couple.coupleId, couple.second.userId, "paused");
    expect(await relayOnly()).toBe(true);
    // The partner's choice is theirs alone.
    expect((await couple.first.as.action(api.calls.get_call_ice_servers, { p_call_id: callId })).relay_only).toBe(false);
    await setLocationSharing(t, couple.coupleId, couple.second.userId, "off");
    expect(await relayOnly()).toBe(false);
  });

  test("TURN credentials carry the call id, and the call's end revokes them", async () => {
    process.env.CLOUDFLARE_TURN_KEY_ID = "key-1";
    process.env.CLOUDFLARE_TURN_API_TOKEN = "token-1";
    const requests: { url: string; body: unknown }[] = [];
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      requests.push({ url, body: init?.body ? JSON.parse(String(init.body)) : null });
      if (url.endsWith("/generate-ice-servers")) {
        return new Response(JSON.stringify({
          iceServers: [
            { urls: ["stun:stun.cloudflare.com:3478"] },
            { urls: ["turn:turn.cloudflare.com:3478?transport=udp"], username: "turn-user", credential: "secret" },
          ],
        }), { status: 201 });
      }
      return new Response(null, { status: 204 });
    });
    try {
      const { t, couple } = await setup();
      const callId = await call(couple);
      const servers = await couple.first.as.action(api.calls.get_call_ice_servers, { p_call_id: callId });
      expect(servers.ice_servers).toEqual([
        { urls: ["stun:stun.cloudflare.com:3478"] },
        { urls: ["turn:turn.cloudflare.com:3478?transport=udp"], username: "turn-user", credential: "secret" },
      ]);
      expect(requests[0]).toEqual({
        url: "https://rtc.live.cloudflare.com/v1/turn/keys/key-1/credentials/generate-ice-servers",
        body: { ttl: 86_400, customIdentifier: callId },
      });
      await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
      await t.finishAllScheduledFunctions(vi.runAllTimers);
      expect(requests.map((request) => request.url)).toContain(
        "https://rtc.live.cloudflare.com/v1/turn/keys/key-1/credentials/turn-user/revoke",
      );
    } finally {
      fetchMock.mockRestore();
      delete process.env.CLOUDFLARE_TURN_KEY_ID;
      delete process.env.CLOUDFLARE_TURN_API_TOKEN;
    }
  });

  test("without TURN from Cloudflare, a viewer who may connect directly gets STUN and one who must relay is refused", async () => {
    process.env.CLOUDFLARE_TURN_KEY_ID = "key-1";
    process.env.CLOUDFLARE_TURN_API_TOKEN = "token-1";
    let cloudflare: () => Promise<Response> = async () => new Response(null, { status: 503 });
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(() => cloudflare());
    try {
      const { t, couple } = await setup();
      const callId = await call(couple);
      const stunOnly = { ice_servers: [{ urls: ["stun:stun.cloudflare.com:3478"] }], relay_only: false };
      expect(await couple.first.as.action(api.calls.get_call_ice_servers, { p_call_id: callId })).toEqual(stunOnly);
      cloudflare = async () => {
        throw new TypeError("fetch failed");
      };
      expect(await couple.first.as.action(api.calls.get_call_ice_servers, { p_call_id: callId })).toEqual(stunOnly);

      await setLocationSharing(t, couple.coupleId, couple.second.userId, "paused");
      expect(await failure(couple.second.as.action(api.calls.get_call_ice_servers, { p_call_id: callId }))).toEqual({
        code: "P0003",
        message: "turn_unavailable",
      });
    } finally {
      fetchMock.mockRestore();
      delete process.env.CLOUDFLARE_TURN_KEY_ID;
      delete process.env.CLOUDFLARE_TURN_API_TOKEN;
    }
  });

  test("each member gets at most four sets of TURN credentials per call, and the end revokes them all", async () => {
    process.env.CLOUDFLARE_TURN_KEY_ID = "key-1";
    process.env.CLOUDFLARE_TURN_API_TOKEN = "token-1";
    const urls: string[] = [];
    let minted = 0;
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      urls.push(url);
      if (url.endsWith("/generate-ice-servers")) {
        minted += 1;
        return new Response(JSON.stringify({
          iceServers: [{ urls: ["turn:turn.cloudflare.com:3478"], username: `turn-user-${minted}`, credential: "secret" }],
        }), { status: 201 });
      }
      return new Response(null, { status: 204 });
    });
    try {
      const { t, couple } = await setup();
      const callId = await call(couple);
      for (let attempt = 0; attempt < 4; attempt += 1) {
        await couple.first.as.action(api.calls.get_call_ice_servers, { p_call_id: callId });
      }
      expect(await failure(couple.first.as.action(api.calls.get_call_ice_servers, { p_call_id: callId }))).toEqual({
        code: "P0003",
        message: "turn_limit_reached",
      });
      expect(minted).toBe(4);
      // The partner's own sets are counted apart.
      await couple.second.as.action(api.calls.get_call_ice_servers, { p_call_id: callId });
      expect(minted).toBe(5);

      await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
      await t.finishAllScheduledFunctions(vi.runAllTimers);
      const revoked = urls.filter((url) => url.endsWith("/revoke"));
      expect(revoked).toHaveLength(5);
      for (let index = 1; index <= 5; index += 1) {
        expect(revoked).toContain(`https://rtc.live.cloudflare.com/v1/turn/keys/key-1/credentials/turn-user-${index}/revoke`);
      }
    } finally {
      fetchMock.mockRestore();
      delete process.env.CLOUDFLARE_TURN_KEY_ID;
      delete process.env.CLOUDFLARE_TURN_API_TOKEN;
    }
  });

  test("the call context gives the partner's zone only while they share their location", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "America/New_York"] });
    const context = () => couple.first.as.query(api.calls.get_call_context, {});
    expect(await context()).toEqual({ partner_time_zone_id: null });
    await setLocationSharing(t, couple.coupleId, couple.second.userId, "on");
    expect(await context()).toEqual({ partner_time_zone_id: "America/New_York" });
    await addDevice(t, couple.second.userId, { timeZone: "Asia/Tokyo" });
    expect(await context()).toEqual({ partner_time_zone_id: "Asia/Tokyo" });
    await setLocationSharing(t, couple.coupleId, couple.second.userId, "paused");
    expect(await context()).toEqual({ partner_time_zone_id: null });
    await setLocationSharing(t, couple.coupleId, couple.second.userId, "off");
    expect(await context()).toEqual({ partner_time_zone_id: null });
    // The viewer's own sharing does not show the partner's zone.
    await setLocationSharing(t, couple.coupleId, couple.first.userId, "on");
    expect(await context()).toEqual({ partner_time_zone_id: null });

    const unknown = await createCouple(t);
    await setLocationSharing(t, unknown.coupleId, unknown.second.userId, "on");
    expect(await unknown.first.as.query(api.calls.get_call_context, {})).toEqual({ partner_time_zone_id: null });
  });
});

describe("call states", () => {
  test("start rings the partner, and both see the same live call", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    const createdAt = (await liveCalls(t))[0].created_at;
    const expected = {
      call_id: callId,
      caller_user_id: couple.first.userId,
      callee_user_id: couple.second.userId,
      state: "ringing",
      answered_device_id: null,
      ring_expires_at: new Date(Date.parse(createdAt) + 45_000).toISOString(),
      answered_at: null,
      created_at: createdAt,
    };
    expect(await couple.first.as.query(api.calls.get_live_call, {})).toEqual(expected);
    expect(await couple.second.as.query(api.calls.get_live_call, {})).toEqual(expected);
  });

  test("sending the same start again returns the same call", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    const again = await couple.first.as.mutation(api.calls.start_call, { p_call_id: callId.toUpperCase(), p_device_id: newUuid() });
    expect(again).toEqual({ call_id: callId, answered_incoming: false });
    expect(await liveCalls(t)).toHaveLength(1);
  });

  test("calling a partner whose call to you rings answers it", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    const device = newUuid();
    const glare = await couple.second.as.mutation(api.calls.start_call, { p_call_id: newUuid(), p_device_id: device });
    expect(glare).toEqual({ call_id: callId, answered_incoming: true });
    expect(await liveCalls(t)).toMatchObject([{ id: callId, state: "active", answered_device_id: device }]);
  });

  test("a second call while one is live is refused as busy", async () => {
    const { couple } = await setup();
    const callId = await call(couple);
    const busy = await failure(couple.first.as.mutation(api.calls.start_call, { p_call_id: newUuid(), p_device_id: newUuid() }));
    expect(busy).toEqual({ code: "P0001", message: "call_busy" });
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() });
    expect(await failure(couple.second.as.mutation(api.calls.start_call, { p_call_id: newUuid(), p_device_id: newUuid() }))).toEqual({
      code: "P0001",
      message: "call_busy",
    });
  });

  test("the first phone to answer wins, and the caller cannot answer", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    expect((await failure(couple.first.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() }))).message).toBe("call_not_ringing");
    const phone = newUuid();
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: phone });
    const late = await failure(couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() }));
    expect(late).toEqual({ code: "P0002", message: "call_not_ringing" });
    expect(await couple.first.as.query(api.calls.get_live_call, {})).toMatchObject({
      state: "active",
      answered_device_id: phone,
      answered_at: expect.any(String),
    });
    expect(await liveCalls(t)).toHaveLength(1);
  });

  test("the ring times out after 45 seconds into one missed call, a push, and no answer after", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await liveCalls(t)).toEqual([]);
    expect(await callRows(t)).toMatchObject([{ id: callId, sender_user_id: couple.first.userId, call: { outcome: "missed" } }]);
    expect((await callRows(t))[0].body).toBeUndefined();
    const late = await failure(couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() }));
    expect(late).toEqual({ code: "P0002", message: "call_not_ringing" });
    // The sweep after the timeout finds nothing more to end.
    await t.mutation(internal.calls.sweep_calls, {});
    expect(await callRows(t)).toHaveLength(1);

    const pushes = await missedCallPushes(t);
    expect(pushes).toHaveLength(1);
    expect(pushes[0]).toMatchObject({ recipient_user_id: couple.second.userId, apns_push_type: "alert" });
    expect(pushes[0].payload).toMatchObject({ type: "missed_call", message_id: callId, route: "chat", deeplink: "paeonia://chat" });
    const delivered = await deliverDuePushes(t);
    expect(delivered.find((push) => push.payload.type === "missed_call")).toMatchObject({ title: "Missed call from First Partner", badge: 1 });
  });

  test("a late retry of an ended call never rings again", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
    const retry = await failure(couple.first.as.mutation(api.calls.start_call, { p_call_id: callId, p_device_id: newUuid() }));
    expect(retry).toEqual({ code: "P0002", message: "call_not_ringing" });
    expect(await liveCalls(t)).toEqual([]);
  });

  test("declining writes a missed call without a push, and only the callee can decline", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    expect((await failure(couple.first.as.mutation(api.calls.decline_call, { p_call_id: callId }))).code).toBe("42501");
    await couple.second.as.mutation(api.calls.decline_call, { p_call_id: callId });
    await couple.second.as.mutation(api.calls.decline_call, { p_call_id: callId });
    expect(await liveCalls(t)).toEqual([]);
    expect(await callRows(t)).toMatchObject([{ id: callId, call: { outcome: "missed" } }]);
    // The ring timeout that was waiting writes nothing more.
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await callRows(t)).toHaveLength(1);
    expect(await missedCallPushes(t)).toEqual([]);
  });

  test("the callee ending a ringing call declines it", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    await couple.second.as.mutation(api.calls.end_call, { p_call_id: callId });
    expect(await callRows(t)).toMatchObject([{ call: { outcome: "missed" } }]);
    expect(await missedCallPushes(t)).toEqual([]);
  });

  test("the caller canceling writes a missed call and tells the callee", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    tick(10);
    await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
    await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await liveCalls(t)).toEqual([]);
    expect(await callRows(t)).toMatchObject([{ id: callId, call: { outcome: "missed" } }]);
    expect(await missedCallPushes(t)).toHaveLength(1);
  });

  test("ending a running call writes a completed call with its length, in the couple chat", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    tick(5);
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() });
    tick(30);
    await couple.second.as.mutation(api.calls.call_heartbeat, { p_call_id: callId });
    tick(62);
    await couple.second.as.mutation(api.calls.end_call, { p_call_id: callId });
    expect(await couple.first.as.query(api.calls.get_live_call, {})).toBeNull();
    const [row] = await callRows(t);
    expect(row.call?.outcome).toBe("completed");
    expect(row.call?.duration_seconds).toBeGreaterThanOrEqual(92);
    expect(row.call?.duration_seconds).toBeLessThanOrEqual(93);
    expect(await missedCallPushes(t)).toEqual([]);

    const [thread] = await couple.second.as.query(api.threads.get_conversation_threads, {});
    expect(thread).toMatchObject({ kind: "couple", last_message_id: callId, last_message_body: null });
    expect(thread.last_message_call).toEqual({ outcome: "completed", duration_seconds: row.call?.duration_seconds });
    const page = await couple.first.as.query(api.threads.get_thread_messages, { p_thread_id: thread.thread_id, p_limit: 10 });
    expect(page.messages).toMatchObject([{ message_id: callId, sender_user_id: couple.first.userId, body: null, call: thread.last_message_call }]);
  });

  test("a completed call after an unread message keeps the chat unread for the person who has not read it", async () => {
    const { couple } = await setup();
    await couple.second.as.mutation(api.threads.create_couple_thread_with_message, { ...op(), p_couple_id: couple.coupleId, p_body: "call me?" });
    tick(5);
    const callId = await call(couple);
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() });
    tick(30);
    await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });

    const [forFirst] = await couple.first.as.query(api.threads.get_conversation_threads, {});
    expect(forFirst).toMatchObject({ last_message_id: callId, last_message_sender_user_id: couple.first.userId, has_unread: true });
    const [forSecond] = await couple.second.as.query(api.threads.get_conversation_threads, {});
    expect(forSecond.has_unread).toBe(false);

    const page = await couple.first.as.query(api.threads.get_thread_messages, { p_thread_id: forFirst.thread_id, p_limit: 10 });
    const message = page.messages.find((row) => row.message_id !== callId)!;
    await couple.first.as.mutation(api.chatPresence.mark_thread_read, { p_thread_id: forFirst.thread_id, p_message_id: message.message_id });
    expect((await couple.first.as.query(api.threads.get_conversation_threads, {}))[0].has_unread).toBe(false);
  });

  test("a call's row cannot be edited, replied to, deleted, reacted to or reported", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
    const threadId = (await t.run((ctx) => ctx.db.query("conversation_threads").first()))!.id;
    expect(await failure(couple.first.as.mutation(api.threads.edit_thread_message, { p_message_id: callId, p_body: "hi" }))).toEqual({
      code: "23514",
      message: "calls cannot be edited",
    });
    const reply = await failure(
      couple.second.as.mutation(api.threads.send_thread_message, { p_thread_id: threadId, p_body: "sorry", p_reply_to_message_id: callId, ...op() }),
    );
    expect(reply).toEqual({ code: "23514", message: "calls cannot be replied to" });
    expect(await failure(couple.first.as.mutation(api.threads.delete_thread_message, { p_message_id: callId, ...op() }))).toEqual({
      code: "23514",
      message: "calls cannot be deleted",
    });
    // The callee did not send the row, so they are refused as for any message of the partner's.
    expect((await failure(couple.second.as.mutation(api.threads.delete_thread_message, { p_message_id: callId, ...op() }))).code).toBe("42501");
    for (const user of [couple.first, couple.second]) {
      expect(
        await failure(user.as.mutation(api.reactions.set_reaction, { p_kind: "thread_message", p_target_id: callId, p_emoji: "❤️" })),
      ).toEqual({ code: "23514", message: "calls cannot be reacted to" });
    }
    expect(await callRows(t)).toMatchObject([{ id: callId, call: { outcome: "missed" } }]);
    expect((await callRows(t))[0].deleted_at).toBeUndefined();
    expect(await t.run((ctx) => ctx.db.query("reactions").collect())).toEqual([]);
    const report = await failure(
      couple.second.as.mutation(api.reports.submit_leave_and_report, {
        p_target_kind: "thread_message",
        p_target_id: callId,
        p_reason: "harassment",
        ...op(),
      }),
    );
    expect(report).toEqual({ code: "23514", message: "calls cannot be reported" });
  });

  test("the heartbeat sweep ends a call that lost one side, and keeps one that did not", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() });
    for (let beat = 0; beat < 4; beat += 1) {
      tick(15);
      await couple.first.as.mutation(api.calls.call_heartbeat, { p_call_id: callId });
      await couple.second.as.mutation(api.calls.call_heartbeat, { p_call_id: callId });
    }
    await t.mutation(internal.calls.sweep_calls, {});
    expect(await liveCalls(t)).toHaveLength(1);
    // The callee's phone goes quiet. The caller's keeps beating.
    for (let beat = 0; beat < 4; beat += 1) {
      tick(15);
      await couple.first.as.mutation(api.calls.call_heartbeat, { p_call_id: callId });
    }
    tick(1);
    await t.mutation(internal.calls.sweep_calls, {});
    expect(await liveCalls(t)).toEqual([]);
    const [row] = await callRows(t);
    expect(row.call?.outcome).toBe("completed");
    expect(row.call?.duration_seconds).toBeGreaterThanOrEqual(121);
  });

  test("leaving the relationship ends the call first and leaves its row in the chat", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() });
    await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.second.userId, "left"));
    expect(await liveCalls(t)).toEqual([]);
    expect(await callRows(t)).toMatchObject([{ id: callId, couple_id: couple.coupleId, call: { outcome: "completed" } }]);
    expect(await couple.first.as.query(api.calls.get_live_call, {})).toBeNull();
    expect(await missedCallPushes(t)).toEqual([]);
  });

  test("signing out ends the person's live call", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    const device = (await t.run((ctx) => ctx.db.query("user_devices").collect())).find((row) => row.user_id === couple.second.userId)!;
    await couple.second.as.mutation(api.identity.disable_user_device, { p_device_id: device.id });
    expect(await liveCalls(t)).toEqual([]);
    expect(await callRows(t)).toMatchObject([{ id: callId, call: { outcome: "missed" } }]);
    expect(await missedCallPushes(t)).toEqual([]);
  });
});

describe("ringing", () => {
  test("register_user_device stores the PushKit token and null clears it", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const args = { p_platform: "ios", p_push_token: "push".padEnd(40, "0"), p_apns_environment: "sandbox" };
    await user.as.mutation(api.identity.register_user_device, { ...args, p_voip_push_token: "voip".padEnd(64, "a") });
    expect((await t.run((ctx) => ctx.db.query("user_devices").first()))?.voip_push_token).toBe("voip".padEnd(64, "a"));
    await user.as.mutation(api.identity.register_user_device, { ...args, p_voip_push_token: null });
    expect((await t.run((ctx) => ctx.db.query("user_devices").first()))?.voip_push_token).toBeUndefined();
    expect((await failure(user.as.mutation(api.identity.register_user_device, { ...args, p_voip_push_token: "short" }))).message).toBe("invalid voip push token");
  });

  test("a ring goes to each active phone of the callee with a PushKit token, while the call rings", async () => {
    const { t, couple } = await setup();
    const phone = await addDevice(t, couple.second.userId);
    await t.run((ctx) => ctx.db.patch(phone._id, { voip_push_token: "voip-token" }));
    const callId = await call(couple);
    const rings = await t.query(internal.calls.prepare_call_ring, { call_id: callId });
    expect(rings).toEqual([
      {
        device_id: phone.id,
        voip_push_token: "voip-token",
        apns_environment: "sandbox",
        call_id: callId,
        caller_user_id: couple.first.userId,
        ring_expires_at: (await liveCalls(t))[0].ring_expires_at,
      },
    ]);
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() });
    expect(await t.query(internal.calls.prepare_call_ring, { call_id: callId })).toEqual([]);
  });
});

describe("quality reports", () => {
  const report = (changes: Partial<Record<string, unknown>> = {}) => ({
    end_reason: "hung_up" as const,
    media_connected: true,
    answer_to_connected_ms: 420,
    path: "direct" as const,
    reconnects: 1,
    reconnecting_seconds: 3,
    median_rtt_ms: 48,
    audio_loss_percent: 0.4,
    video_loss_percent: 1.2,
    video_sent_seconds: 30,
    video_received_seconds: 20,
    hottest_thermal_state: "fair" as const,
    app_build: "412",
    video_sent_fps: 24,
    video_limits: { cpu: 0, bandwidth: 10, other: 0, none: 90 },
    screen_sent_seconds: 25,
    screen_captured_fps: 58.5,
    screen_source_fps: 4,
    screen_sent_fps: 3.5,
    screen_sent_width: 1_080,
    screen_sent_height: 1_920,
    screen_limits: { cpu: 80, bandwidth: 0, other: 0, none: 20 },
    screen_encode_ms: 41.2,
    screen_qp: 34.5,
    screen_key_frames_per_minute: 2.4,
    screen_encoder: "VideoToolbox",
    screen_power_efficient_encoder: true,
    screen_pixel_format: "420f",
    screen_received_seconds: 12,
    screen_received_fps: 2.5,
    screen_frames_dropped: 40,
    screen_freezes: 6,
    screen_decode_ms: 3.1,
    encoder_resets: 0,
    encoder_failed_frames: 2,
    encoder_dropped_frames: 15,
    ...changes,
  });
  const reportCall = (person: TestCouple["first"], callId: string, changes: Partial<Record<string, unknown>> = {}) =>
    person.as.mutation(api.calls.report_call_quality, { p_call_id: callId, p_report: report(changes) as ReturnType<typeof report> });
  const reports = (t: TestConvex) => t.query(internal.calls.recent_call_reports, {});

  test("someone outside the call's couple, or no longer in it, cannot report it", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    const stranger = await createSignedInUser(t, {});
    const strangerCouple = await createCouple(t);
    for (const outsider of [stranger, strangerCouple.first]) {
      expect((await failure(reportCall(outsider, callId))).code).toBe("42501");
    }
    await expect(t.mutation(api.calls.report_call_quality, { p_call_id: callId, p_report: report() as ReturnType<typeof report> })).rejects.toThrow();
    expect((await failure(reportCall(couple.first, newUuid()))).code).toBe("42501");

    await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
    await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.second.userId, "left"));
    expect((await failure(reportCall(couple.first, callId))).code).toBe("42501");
    expect(await reports(t)).toEqual([]);
  });

  test("each person reports a call once, while it runs or after it ended, with numbers in range", async () => {
    const { t, couple } = await setup();
    const callId = await call(couple);
    await couple.second.as.mutation(api.calls.answer_call, { p_call_id: callId, p_device_id: newUuid() });
    // The phone that hangs up sends its report next to the end, so it can arrive first.
    await reportCall(couple.first, callId);
    await couple.first.as.mutation(api.calls.end_call, { p_call_id: callId });
    tick(1);
    await reportCall(couple.second, callId, { path: "turn", end_reason: "hung_up" });
    await reportCall(couple.second, callId, { app_build: "999" });
    expect(await reports(t)).toMatchObject([
      { call_id: callId, couple_id: couple.coupleId, user_id: couple.second.userId, role: "callee", path: "turn", app_build: "412" },
      { call_id: callId, couple_id: couple.coupleId, user_id: couple.first.userId, role: "caller", path: "direct", screen_sent_fps: 3.5, screen_limits: { cpu: 80 }, screen_encoder: "VideoToolbox", encoder_dropped_frames: 15 },
    ]);

    const missed = await call(couple);
    await couple.second.as.mutation(api.calls.decline_call, { p_call_id: missed });
    await reportCall(couple.first, missed, { end_reason: "no_answer", media_connected: false, path: undefined });
    for (const wrong of [
      { median_rtt_ms: -1 },
      { audio_loss_percent: 101 },
      { reconnecting_seconds: Number.NaN },
      { app_build: "9".repeat(33) },
      { screen_sent_fps: 1_001 },
      { screen_frames_dropped: -1 },
      { screen_limits: { cpu: 101, bandwidth: 0, other: 0, none: 0 } },
      { video_limits: { cpu: 0, bandwidth: Number.POSITIVE_INFINITY, other: 0, none: 0 } },
      { screen_pixel_format: "x".repeat(9) },
      { screen_qp: 256 },
      { encoder_dropped_frames: -1 },
      { screen_encoder: "x".repeat(65) },
    ]) {
      expect((await failure(reportCall(couple.second, missed, wrong))).code).toBe("22023");
    }
    expect((await reports(t)).filter((row) => row.call_id === missed)).toMatchObject([
      { user_id: couple.first.userId, end_reason: "no_answer", media_connected: false },
    ]);
  });

  test("the couple's reports go when the relationship ends or is purged, and every report after 30 days", async () => {
    const { t, couple } = await setup();
    const other = await createCouple(t);
    for (const pair of [couple, other]) {
      const callId = await call(pair);
      await pair.first.as.mutation(api.calls.end_call, { p_call_id: callId });
      await reportCall(pair.first, callId);
      await reportCall(pair.second, callId);
    }
    await couple.first.as.mutation(api.identity.request_account_deletion, {});
    expect((await reports(t)).map((row) => row.couple_id)).toEqual([other.coupleId, other.coupleId]);

    const ended = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((row) => row.id === couple.coupleId)!);
    const leftover = { ...report(), call_id: newUuid(), couple_id: couple.coupleId, user_id: couple.second.userId, role: "callee" as const, created_at: new Date().toISOString() };
    await t.run((ctx) => ctx.db.insert("call_reports", leftover));
    await t.run((ctx) => cleanupCoupleContent(ctx, ended, new Date().toISOString()));
    await t.run((ctx) => ctx.db.insert("call_reports", leftover));
    await t.run((ctx) => purgeCoupleContent(ctx, ended));
    expect((await reports(t)).map((row) => row.couple_id)).toEqual([other.coupleId, other.coupleId]);

    tick(29 * 86_400);
    await t.mutation(internal.retention.prune_expired_rows, {});
    expect(await reports(t)).toHaveLength(2);
    tick(2 * 86_400);
    await t.mutation(internal.retention.prune_expired_rows, {});
    expect(await reports(t)).toEqual([]);
  });
});
