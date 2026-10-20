import { mutation, query } from "./_generated/server";
import { requireUserId } from "./lib/auth";
import { badgeCountForUser, queueBadgeUpdate } from "./lib/badges";

// The app icon badge (lib/badges.ts). The app subscribes to `get_badge_count` while it runs and
// sets its own icon. When the number changes it calls `sync_badge`, so the person's other phones
// get the new number in a badge-only push.

/** How many things wait for the caller. Zero without an entitled couple. */
export const get_badge_count = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await badgeCountForUser(ctx, userId);
  },
});

/**
 * Sends the caller's current number to each of their phones, after a short wait. A phone that
 * already has one on the way gets no second one, so calling it often is cheap.
 */
export const sync_badge = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await queueBadgeUpdate(ctx, userId);
    return null;
  },
});
