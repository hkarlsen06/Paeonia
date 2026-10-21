import { mutation, query } from "./_generated/server";
import { requireUserId } from "./lib/auth";
import { badgeCountsForUser, queueBadgeUpdate } from "./lib/badges";

// The app icon badge (lib/badges.ts). The app subscribes to `get_badges` while it runs, sets its
// own icon, and shows the same counts on its tabs. When the icon number changes it calls
// `sync_badge`, so the person's other phones get the new number in a badge-only push.

/** What waits for the caller, by tab, and the icon number. All zero without an entitled couple. */
export const get_badges = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await badgeCountsForUser(ctx, userId);
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
