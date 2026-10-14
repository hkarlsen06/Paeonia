import type { MutationCtx } from "../_generated/server";
import { findCurrentCouple } from "./access";
import { getByUuid, withTouch } from "./db";
import { fail } from "./errors";
import { endRelationshipForPair } from "./relationshipEnd";
import { refreshStreakAfterDeviceTimeZoneChange } from "./streaks";
import { nowIso } from "./time";

const MAX_REASON_LENGTH = 500;

/**
 * Bans a user. From the next call on, `activeUserIdForSubject` treats them as
 * signed out, so every function refuses them, and the access snapshot tells the
 * app to show the closed-account screen. The ban also ends their relationship,
 * so the partner gets the usual "relationship is closed" notice instead of a
 * partner who never answers, and it turns off their push devices.
 *
 * The Clerk user stays, so the banned person can still sign in, read why the app
 * is closed, and delete their account. Returns false when they were already banned.
 */
export async function banUser(
  ctx: MutationCtx,
  userId: string,
  options: { reason: string; bannedByUserId?: string },
): Promise<boolean> {
  const user = await getByUuid(ctx, "users", userId);
  if (!user) return fail("P0002", "user not found");
  if (user.banned_at !== undefined) return false;
  const reason = options.reason.trim();
  if (reason === "" || Array.from(reason).length > MAX_REASON_LENGTH) {
    return fail("23514", `ban reason must be 1 to ${MAX_REASON_LENGTH} characters`);
  }

  // End the relationship first. It needs the user to still be an active member.
  const couple = await findCurrentCouple(ctx, userId);
  if (couple) await endRelationshipForPair(ctx, couple.pair_id, userId, "account_banned");

  const now = nowIso();
  await ctx.db.patch(user._id, {
    banned_at: now,
    ban_reason: reason,
    banned_by_user_id: options.bannedByUserId,
  });

  // Registering a device needs an active user, so the app turns these back on
  // by itself after an unban.
  for (const device of await ctx.db
    .query("user_devices")
    .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", userId).eq("disabled_at", undefined))
    .collect()) {
    await ctx.db.patch(device._id, withTouch(device, { disabled_at: now }));
    await refreshStreakAfterDeviceTimeZoneChange(ctx, userId, { ...device, disabled_at: now }, device);
  }
  for (const device of await ctx.db
    .query("widget_push_devices")
    .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", userId).eq("disabled_at", undefined))
    .collect()) {
    await ctx.db.patch(device._id, withTouch(device, { disabled_at: now }));
  }
  return true;
}

/** Lifts a ban. The ended relationship stays ended. Returns false when they were not banned. */
export async function unbanUser(ctx: MutationCtx, userId: string): Promise<boolean> {
  const user = await getByUuid(ctx, "users", userId);
  if (!user) return fail("P0002", "user not found");
  if (user.banned_at === undefined) return false;
  await ctx.db.patch(user._id, { banned_at: undefined, ban_reason: undefined, banned_by_user_id: undefined });
  return true;
}
