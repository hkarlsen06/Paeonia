import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { action, internalAction, internalMutation, internalQuery, mutation, query } from "./_generated/server";
import { findCurrentCouple, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { requireUserId } from "./lib/auth";
import {
  callView,
  endCall,
  HEARTBEAT_TIMEOUT_MS,
  isCallMember,
  liveCallOfCouple,
  RING_MS,
} from "./lib/calls";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid } from "./lib/db";
import { fail } from "./lib/errors";
import { uuidArg } from "./lib/ids";
import { signLiveTicket } from "./lib/liveTicket";
import { isSharingNow } from "./lib/locationPause";
import { consumeRateLimit } from "./lib/rateLimits";
import { knownMemberTimeZone } from "./lib/streakDeadlines";
import { addMs, nowIso } from "./lib/time";

// Voice and video calls between partners. Convex owns each live call in `calls`, the relay carries
// the WebRTC setup messages on the `call` channel, and Cloudflare TURN carries media that cannot go
// directly. The rules are in docs/calling-plan.md and lib/calls.ts.

const CALL_BUSY = "call_busy";
const CALL_NOT_RINGING = "call_not_ringing";
const CALL_NOT_LIVE = "call_not_live";

/**
 * The live call `callId` with the caller as a member of it. Fails with 42501 for someone outside the
 * call, and with P0002 `call_not_live` once the call is gone.
 */
async function requireLiveCallMember(ctx: ReaderCtx, userId: string, callId: string): Promise<Doc<"calls">> {
  const call = await getByUuid(ctx, "calls", callId);
  if (!call) return fail("P0002", CALL_NOT_LIVE);
  if (!isCallMember(call, userId)) return fail("42501", "live call access is required");
  return call;
}

/** The call when the viewer takes part in it. Null when it is gone. Fails for someone outside it. */
async function memberCallOrNull(ctx: ReaderCtx, userId: string, callId: string): Promise<Doc<"calls"> | null> {
  const call = await getByUuid(ctx, "calls", callId);
  if (call && !isCallMember(call, userId)) fail("42501", "live call access is required");
  return call;
}

/**
 * Starts a call to the partner with the id the app proposes. When the partner's call to the viewer
 * is ringing, answers that call instead from `p_device_id` (`answered_incoming: true`). Any other live
 * call for the couple refuses with P0001 `call_busy`. Sending the same id again while that call is
 * live returns the same result. An id of a call that already ended refuses with P0002.
 */
export const start_call = mutation({
  args: { p_call_id: v.string(), p_device_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const callId = uuidArg(args.p_call_id);
    const deviceId = uuidArg(args.p_device_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    await consumeRateLimit(ctx, "startCall", userId);

    const live = await liveCallOfCouple(ctx, coupleId);
    if (live) {
      if (live.id === callId && live.caller_user_id === userId) return { call_id: live.id, answered_incoming: false };
      if (live.state === "ringing" && live.callee_user_id === userId) {
        await answer(ctx, live, deviceId);
        return { call_id: live.id, answered_incoming: true };
      }
      return fail("P0001", CALL_BUSY);
    }
    // An ended call left its row in the chat under its own id, so a late retry never rings again.
    if ((await getByUuid(ctx, "calls", callId)) || (await getByUuid(ctx, "thread_messages", callId))) {
      return fail("P0002", CALL_NOT_RINGING);
    }
    const partner = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId);
    if (!partner) return fail("42501", "active entitled couple access is required");

    const now = nowIso();
    const ringExpiresAt = addMs(now, RING_MS);
    await ctx.db.insert("calls", {
      id: callId,
      couple_id: coupleId,
      caller_user_id: userId,
      callee_user_id: partner.user_id,
      state: "ringing",
      ring_expires_at: ringExpiresAt,
      turn_usernames: [],
      turn_mint_user_ids: [],
      created_at: now,
    });
    await ctx.scheduler.runAt(Date.parse(ringExpiresAt), internal.calls.ring_timed_out, { call_id: callId });
    await ctx.scheduler.runAfter(0, internal.push.send_call_ring, { call_id: callId });
    return { call_id: callId, answered_incoming: false };
  },
});

/** Moves a ringing call to active, answered from `deviceId`. The heartbeat clock starts now. */
async function answer(ctx: WriterCtx, call: Doc<"calls">, deviceId: string): Promise<void> {
  const now = nowIso();
  await ctx.db.patch(call._id, {
    state: "active",
    answered_device_id: deviceId,
    answered_at: now,
    caller_seen_at: now,
    callee_seen_at: now,
  });
}

/** The callee answers from `p_device_id`. The first phone wins. Anything but a ringing call refuses with P0002. */
export const answer_call = mutation({
  args: { p_call_id: v.string(), p_device_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const deviceId = uuidArg(args.p_device_id);
    const call = await memberCallOrNull(ctx, userId, uuidArg(args.p_call_id));
    if (!call || call.state !== "ringing" || call.callee_user_id !== userId) return fail("P0002", CALL_NOT_RINGING);
    await answer(ctx, call, deviceId);
    return null;
  },
});

/** The callee declines. The call ends as missed, without a missed-call push. Does nothing once it no longer rings. */
export const decline_call = mutation({
  args: { p_call_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const call = await memberCallOrNull(ctx, userId, uuidArg(args.p_call_id));
    if (call && call.callee_user_id !== userId) return fail("42501", "only the callee can decline a call");
    if (call?.state === "ringing") await endCall(ctx, call, "declined");
    return null;
  },
});

/**
 * Either member ends the call. A ringing call the caller ends is missed, one the callee ends is
 * declined, and a running one is completed with its length. Does nothing once the call is gone.
 */
export const end_call = mutation({
  args: { p_call_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const call = await memberCallOrNull(ctx, userId, uuidArg(args.p_call_id));
    if (!call) return null;
    const reason = call.state === "active" ? "hung_up" : call.caller_user_id === userId ? "canceled" : "declined";
    await endCall(ctx, call, reason);
    return null;
  },
});

/** A phone's heartbeat during a running call, every 15 seconds. Does nothing while it rings or once it is gone. */
export const call_heartbeat = mutation({
  args: { p_call_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const call = await memberCallOrNull(ctx, userId, uuidArg(args.p_call_id));
    if (call?.state !== "active") return null;
    await ctx.db.patch(call._id, call.caller_user_id === userId ? { caller_seen_at: nowIso() } : { callee_seen_at: nowIso() });
    return null;
  },
});

/**
 * The live call of the viewer's couple, or null. Membership is enough, because a call in progress
 * finishes even if the subscription lapses. Reads no clock: the ring timeout and the heartbeat
 * sweep end calls, which changes the row.
 */
export const get_live_call = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const couple = await findCurrentCouple(ctx, userId);
    const call = couple ? await liveCallOfCouple(ctx, couple.id) : null;
    return call && isCallMember(call, userId) ? callView(call) : null;
  },
});

/** Whether `userId` shares their location in the couple now: sharing is on and not paused. */
async function isSharingLocationNow(ctx: ReaderCtx, coupleId: string, userId: string): Promise<boolean> {
  const preference = await ctx.db
    .query("location_sharing_preferences")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
    .unique();
  return isSharingNow(preference);
}

/**
 * What the call screen shows about the partner: their time zone, or null when it is not really
 * known. Also null while the partner does not share their location, since a time zone says roughly
 * where they are.
 */
export const get_call_context = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const couple = await findCurrentCouple(ctx, userId);
    if (!couple) return fail("42501", "active couple membership is required");
    const partner = (await listActiveMembers(ctx, couple.id)).find((member) => member.user_id !== userId);
    const shown = partner !== undefined && (await isSharingLocationNow(ctx, couple.id, partner.user_id));
    return { partner_time_zone_id: shown ? await knownMemberTimeZone(ctx, partner.user_id) : null };
  },
});

/**
 * A relay ticket for the call's setup messages, on the couple's `call` channel. Only for a member of
 * the live call. Null while the relay is not configured, like the game ticket.
 */
export const create_call_live_ticket = mutation({
  args: { p_call_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const call = await requireLiveCallMember(ctx, userId, uuidArg(args.p_call_id));
    return await signLiveTicket({ coupleId: call.couple_id, userId, channel: "call" });
  },
});

/** Ends a call still ringing at its deadline as missed. Scheduled by `start_call`. */
export const ring_timed_out = internalMutation({
  args: { call_id: v.string() },
  handler: async (ctx, args) => {
    const call = await getByUuid(ctx, "calls", args.call_id);
    if (call?.state === "ringing") await endCall(ctx, call, "timed_out");
    return null;
  },
});

/**
 * The `sweep-calls` cron. Ends a running call that one member sent no heartbeat to for
 * `HEARTBEAT_TIMEOUT_MS` as completed. Also ends a ringing call past its deadline, in case its
 * scheduled timeout was lost.
 */
export const sweep_calls = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = nowIso();
    const staleBefore = addMs(now, -HEARTBEAT_TIMEOUT_MS);
    for (const call of await ctx.db.query("calls").withIndex("by_state", (q) => q.eq("state", "active")).collect()) {
      const since = call.answered_at ?? call.created_at;
      if ((call.caller_seen_at ?? since) <= staleBefore || (call.callee_seen_at ?? since) <= staleBefore) {
        await endCall(ctx, call, "lost");
      }
    }
    for (const call of await ctx.db.query("calls").withIndex("by_state", (q) => q.eq("state", "ringing")).collect()) {
      if (call.ring_expires_at <= now) await endCall(ctx, call, "timed_out");
    }
    return null;
  },
});

/** What one ring needs per phone of the callee that has a PushKit token. Empty once the call no longer rings. */
export const prepare_call_ring = internalQuery({
  args: { call_id: v.string() },
  handler: async (ctx, args) => {
    const call = await getByUuid(ctx, "calls", args.call_id);
    if (call?.state !== "ringing") return [];
    const preference = await ctx.db
      .query("notification_preferences")
      .withIndex("by_user_id", (q) => q.eq("user_id", call.callee_user_id))
      .unique();
    const devices = await ctx.db
      .query("user_devices")
      .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", call.callee_user_id).eq("disabled_at", undefined))
      .collect();
    return devices.flatMap((device) =>
      device.voip_push_token === undefined
        ? []
        : [
            {
              device_id: device.id,
              voip_push_token: device.voip_push_token,
              apns_environment: device.apns_environment,
              call_id: call.id,
              caller_user_id: call.caller_user_id,
              ring_expires_at: call.ring_expires_at,
              lock_screen_detail_level: preference?.lock_screen_detail_level ?? "private",
            },
          ],
    );
  },
});

// ---- TURN ----

const TURN_TTL_SECONDS = 24 * 60 * 60;
const CLOUDFLARE_TURN_API = "https://rtc.live.cloudflare.com/v1/turn/keys";
/** How many sets of TURN credentials one member can get for one call. Enough for a few reconnects. */
const MAX_TURN_MINTS_PER_MEMBER = 4;

/**
 * Checks that the viewer is a member of the live call. When `mint` is true, also counts one set of
 * TURN credentials for them, and refuses with P0003 `turn_limit_reached` past
 * `MAX_TURN_MINTS_PER_MEMBER`. `relay_only` is true unless the viewer shares their location now, so
 * a partner learns nobody's IP address that they could not already see.
 */
export const ice_server_access = internalMutation({
  args: { call_id: v.string(), mint: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const call = await requireLiveCallMember(ctx, userId, uuidArg(args.call_id));
    if (args.mint) {
      const minted = call.turn_mint_user_ids.filter((id) => id === userId).length;
      if (minted >= MAX_TURN_MINTS_PER_MEMBER) return fail("P0003", "turn_limit_reached");
      await ctx.db.patch(call._id, { turn_mint_user_ids: [...call.turn_mint_user_ids, userId] });
    }
    return { call_id: call.id, relay_only: !(await isSharingLocationNow(ctx, call.couple_id, userId)) };
  },
});

/** Records TURN usernames on the call so its end revokes them. False when the call already ended. */
export const record_turn_usernames = internalMutation({
  args: { call_id: v.string(), usernames: v.array(v.string()) },
  handler: async (ctx, args) => {
    const call = await getByUuid(ctx, "calls", args.call_id);
    if (!call) return false;
    await ctx.db.patch(call._id, { turn_usernames: [...call.turn_usernames, ...args.usernames] });
    return true;
  },
});

type IceServer = { urls: string[]; username?: string; credential?: string };

/** Reads Cloudflare's `iceServers`, keeping only well-formed entries. */
function parseIceServers(body: unknown): IceServer[] {
  const list = (body as { iceServers?: unknown })?.iceServers;
  if (!Array.isArray(list)) return [];
  return list.flatMap((entry): IceServer[] => {
    const urls = typeof entry?.urls === "string" ? [entry.urls] : entry?.urls;
    if (!Array.isArray(urls) || !urls.every((url) => typeof url === "string")) return [];
    return [{
      urls,
      ...(typeof entry.username === "string" ? { username: entry.username } : {}),
      ...(typeof entry.credential === "string" ? { credential: entry.credential } : {}),
    }];
  });
}

/**
 * STUN and TURN servers for a member of the live call, with TURN credentials from Cloudflare that last
 * 24 hours and carry the call id as their custom identifier. The call's end revokes them. Each member
 * gets at most `MAX_TURN_MINTS_PER_MEMBER` sets per call, then P0003 `turn_limit_reached`.
 * `relay_only` is true unless the viewer shares their location now, so the partner never sees their
 * address otherwise. Without `CLOUDFLARE_TURN_KEY_ID` and `CLOUDFLARE_TURN_API_TOKEN` (a local
 * backend) the list is empty and nothing is counted.
 */
export const get_call_ice_servers = action({
  args: { p_call_id: v.string() },
  handler: async (ctx, args): Promise<{ ice_servers: IceServer[]; relay_only: boolean }> => {
    const keyId = process.env.CLOUDFLARE_TURN_KEY_ID;
    const token = process.env.CLOUDFLARE_TURN_API_TOKEN;
    const mint = Boolean(keyId && token);
    const access: { call_id: string; relay_only: boolean } = await ctx.runMutation(internal.calls.ice_server_access, {
      call_id: args.p_call_id,
      mint,
    });
    if (!mint) return { ice_servers: [], relay_only: access.relay_only };

    const response = await fetch(`${CLOUDFLARE_TURN_API}/${keyId}/credentials/generate-ice-servers`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ttl: TURN_TTL_SECONDS, customIdentifier: access.call_id }),
    });
    if (!response.ok) {
      console.error("TURN credentials failed", { status: response.status });
      return fail("P0003", "turn_unavailable");
    }
    const iceServers = parseIceServers(await response.json());
    const usernames = iceServers.flatMap((server) => (server.username ? [server.username] : []));
    if (usernames.length > 0) {
      const live: boolean = await ctx.runMutation(internal.calls.record_turn_usernames, {
        call_id: access.call_id,
        usernames,
      });
      if (!live) {
        await revokeTurnUsernames(usernames);
        return fail("P0002", CALL_NOT_LIVE);
      }
    }
    return { ice_servers: iceServers, relay_only: access.relay_only };
  },
});

async function revokeTurnUsernames(usernames: string[]): Promise<void> {
  const keyId = process.env.CLOUDFLARE_TURN_KEY_ID;
  const token = process.env.CLOUDFLARE_TURN_API_TOKEN;
  if (!keyId || !token) return;
  for (const username of new Set(usernames)) {
    try {
      const response = await fetch(
        `${CLOUDFLARE_TURN_API}/${keyId}/credentials/${encodeURIComponent(username)}/revoke`,
        { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      );
      if (!response.ok) console.error("TURN revoke failed", { status: response.status });
    } catch (error) {
      // The credentials still expire after 24 hours.
      console.error("TURN revoke failed", { error: String(error) });
    }
  }
}

/** Revokes the TURN credentials of a call that ended. Scheduled by `endCall`. */
export const revoke_turn_credentials = internalAction({
  args: { usernames: v.array(v.string()) },
  handler: async (_ctx, args) => {
    await revokeTurnUsernames(args.usernames);
    return null;
  },
});
