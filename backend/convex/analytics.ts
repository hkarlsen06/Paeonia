import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalAction, mutation, query } from "./_generated/server";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { deleteAnalyticsPerson, deleteInactiveAnalyticsPersons } from "./lib/accountDeletionProviders";
import { requireUserId } from "./lib/auth";
import { backgroundWorkpool } from "./lib/backgroundWorkpool";
import { orNull } from "./lib/db";
import { fail } from "./lib/errors";
import { findProfile, updateProfile } from "./lib/profiles";
import { nowIso } from "./lib/time";

// Usage statistics in PostHog. The app asks each person once whether they share
// them, and starts PostHog only after a yes. The answer is kept on the profile,
// so it is the same on every phone and there is a record of what was agreed to.

/** The person's answer, or null before they have answered. */
export const get_usage_sharing = query({
  args: {},
  handler: async (ctx) => {
    const profile = await findProfile(ctx, await requireUserId(ctx));
    return { shares_usage: orNull(profile?.shares_usage) };
  },
});

/**
 * Saves the person's answer. `p_notice` names the version of the question and
 * the privacy policy they saw. Saying no after a yes asks PostHog to delete
 * what it has. A first no sends nothing to PostHog.
 */
export const set_usage_sharing = mutation({
  args: { p_shares: v.boolean(), p_notice: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const profile = await findProfile(ctx, userId);
    if (!profile || profile.deleted_at !== undefined) {
      return fail("P0002", "active profile was not found");
    }
    const notice = args.p_notice.trim();
    if (notice.length < 1 || notice.length > 64) {
      return fail("23514", "usage sharing notice must be 1 to 64 characters");
    }
    const withdrew = profile.shares_usage === true && !args.p_shares;
    await updateProfile(ctx, profile, {
      shares_usage: args.p_shares,
      shares_usage_decided_at: nowIso(),
      shares_usage_notice: notice,
    });
    if (withdrew) {
      await backgroundWorkpool.enqueueAction(ctx, internal.analytics.delete_analytics_person, { p_user_id: userId });
    }
    return { shares_usage: args.p_shares };
  },
});

/** The `backgroundWorkpool` job queued when someone stops sharing. It retries on failure. */
export const delete_analytics_person = internalAction({
  args: { p_user_id: v.string() },
  handler: async (_ctx, args): Promise<null> => {
    await deleteAnalyticsPerson(args.p_user_id);
    return null;
  },
});

/** The monthly cron that keeps usage statistics for a year after someone's last use. */
export const delete_inactive_analytics_persons = internalAction({
  args: {},
  handler: async (): Promise<number> => deleteInactiveAnalyticsPersons(),
});
