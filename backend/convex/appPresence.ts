import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import type { WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { appRoom, placesInApp, setPresent } from "./lib/presence";
import { findProfile, updateProfile } from "./lib/profiles";

// Whether the partner has Paeonia open, and where in it they are: a game, a chat, or typing in
// one. The app shows it as the partner's floating avatar. Each person can turn it off, and then
// neither partner sees the other, so nobody watches someone who cannot watch back.

/**
 * The app room ends this long after the last heartbeat, such as when the app was killed. The app
 * sends one every 12 seconds while it is in front and says when it leaves.
 */
const APP_PRESENCE_TIMEOUT_MS = 30_000;

const showsPresence = (profile: Doc<"profiles"> | null) => profile?.shows_presence !== false;

async function setInApp(ctx: WriterCtx, coupleId: string, userId: string, present: boolean) {
  await setPresent(ctx, appRoom(coupleId), userId, present, APP_PRESENCE_TIMEOUT_MS);
}

/**
 * A heartbeat while the app is in front (`p_present` true), or leaving (false). A person who hides
 * their presence leaves the room instead, so a heartbeat from a phone that has not heard of the
 * change yet shows nothing. Returns null.
 */
export const set_app_presence = mutation({
  args: { p_present: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    await setInApp(ctx, coupleId, userId, args.p_present && showsPresence(await findProfile(ctx, userId)));
    return null;
  },
});

/** Turns "Show when I'm here" on or off. Off takes the caller out of the app room at once. */
export const set_shows_presence = mutation({
  args: { p_shows: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const profile = await findProfile(ctx, userId);
    if (!profile || profile.deleted_at !== undefined) {
      return fail("P0002", "active profile was not found");
    }
    if (showsPresence(profile) !== args.p_shows) {
      await updateProfile(ctx, profile, { shows_presence: args.p_shows });
    }
    if (!args.p_shows) await setInApp(ctx, coupleId, userId, false);
    return { shows_presence: args.p_shows };
  },
});

/**
 * The caller's own setting, and where the partner is while they have the app open. `partner` is
 * null unless both partners show their presence and the partner is in the app room. Its `games`
 * are the game screens they have open, `chat` the chat screen they have open, and `typing` the
 * chat they type in, each a `ChatPlace`. It reads no clock. The presence component ends each room
 * after its timeout, which updates this query.
 */
export const get_partner_presence = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const shows = showsPresence(await findProfile(ctx, userId));
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id;
    if (!shows || partnerId === undefined || !showsPresence(await findProfile(ctx, partnerId))) {
      return { shows_presence: shows, partner: null };
    }
    return { shows_presence: shows, partner: await placesInApp(ctx, coupleId, partnerId) };
  },
});
