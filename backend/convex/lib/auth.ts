import type { UserIdentity } from "convex/server";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import type { Doc } from "../_generated/dataModel";
import { fail } from "./errors";
import { newUuid } from "./ids";
import { withTouch } from "./db";
import { nowIso } from "./time";
import { assertNoPendingAccountDeletion } from "./accountDeletion";
import { DEFAULT_QUESTION_TIME_MINUTES } from "./questionTime";

type AuthProvider = "apple" | "google" | "unknown";

async function findUserByClerkSubject(ctx: QueryCtx, subject: string): Promise<Doc<"users"> | null> {
  return await ctx.db
    .query("users")
    .withIndex("by_clerk_user_id", (q) => q.eq("clerk_user_id", subject))
    .unique();
}

/**
 * The Paeonia uuid for a Clerk subject, or null when it was never provisioned
 * or its account deletion finished. The `users` row outlives deletion (it
 * blocks re-provisioning), and a Clerk token can stay valid for a short while
 * after the Clerk user is gone. Supabase got this for free from the deleted
 * auth user, so every session lookup must go through here.
 */
export async function activeUserIdForSubject(ctx: QueryCtx, subject: string): Promise<string | null> {
  const user = await findUserByClerkSubject(ctx, subject);
  if (!user) {
    return null;
  }
  const completedDeletion = await ctx.db
    .query("account_deletion_jobs")
    .withIndex("by_user_id", (q) => q.eq("user_id", user.id))
    .filter((q) => q.eq(q.field("status"), "completed"))
    .first();
  return completedDeletion ? null : user.id;
}

/**
 * The signed-in user's uuid even after their deletion finished. Only for the
 * idempotent deletion request, which reports the completed tombstone on retry.
 */
export async function requireUserIdIncludingDeleted(ctx: QueryCtx): Promise<string> {
  const identity = await ctx.auth.getUserIdentity();
  const user = identity ? await findUserByClerkSubject(ctx, identity.subject) : null;
  if (!user) {
    return fail("42501", "authenticated user required");
  }
  return user.id;
}

/** The signed-in user's Paeonia uuid, or null when signed out, not yet provisioned, or deleted. */
export async function getCurrentUserId(ctx: QueryCtx): Promise<string | null> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    return null;
  }
  return await activeUserIdForSubject(ctx, identity.subject);
}

/** Port of the `auth.uid() is null` guard: fails with 42501 `authenticated user required`. */
export async function requireUserId(ctx: QueryCtx): Promise<string> {
  const userId = await getCurrentUserId(ctx);
  if (!userId) {
    return fail("42501", "authenticated user required");
  }
  return userId;
}

/**
 * Port of `internal.auth_metadata_display_name`: the trimmed name, at most 80
 * characters, or undefined when there is none. Clerk sends `name`, or
 * `givenName` and `familyName`. A custom `display_name` claim wins.
 */
export function displayNameFromIdentity(identity: UserIdentity): string | undefined {
  const claims = identity as unknown as Record<string, unknown>;
  const text = (value: unknown) => (typeof value === "string" ? value.trim() : "");
  const joined = [text(identity.givenName), text(identity.familyName)].filter(Boolean).join(" ");
  const raw = text(claims.display_name) || text(identity.name) || joined;
  const trimmed = Array.from(raw).slice(0, 80).join("");
  return trimmed === "" ? undefined : trimmed;
}

/**
 * The sign-in provider from an optional custom session claim `auth_provider`
 * ('apple' or 'google'). Without it, a googleusercontent.com
 * picture URL means google, anything else is 'unknown'.
 */
export function authProviderFromIdentity(identity: UserIdentity): AuthProvider {
  const claims = identity as unknown as Record<string, unknown>;
  const claim = typeof claims.auth_provider === "string" ? claims.auth_provider.toLowerCase() : "";
  if (claim === "apple" || claim === "google") {
    return claim;
  }
  if (typeof identity.pictureUrl === "string" && identity.pictureUrl.includes("googleusercontent.com")) {
    return "google";
  }
  return "unknown";
}

/**
 * Provisions the signed-in user on first call and returns their uuid. Replaces
 * the `auth.users` triggers `create_profile_for_new_user` (profile row plus
 * default notification preferences) and
 * `sync_profile_display_name_from_auth_metadata` (a changed provider name
 * overwrites the profile display name). Idempotent. Mutations only.
 */
export async function ensureCurrentUser(ctx: MutationCtx): Promise<string> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    return fail("42501", "authenticated user required");
  }
  const displayName = displayNameFromIdentity(identity);
  const existing = await findUserByClerkSubject(ctx, identity.subject);

  if (existing) {
    // A pending or finished deletion must never hand the account back out.
    await assertNoPendingAccountDeletion(ctx, existing.id);
    if (existing.claim_display_name !== displayName) {
      await ctx.db.patch(existing._id, { claim_display_name: displayName });
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_user_id", (q) => q.eq("user_id", existing.id))
        .unique();
      if (profile && profile.display_name !== displayName) {
        await ctx.db.patch(profile._id, withTouch(profile, { display_name: displayName }));
      }
    }
    return existing.id;
  }

  const userId = newUuid();
  const now = nowIso();
  await ctx.db.insert("users", {
    id: userId,
    clerk_user_id: identity.subject,
    auth_provider: authProviderFromIdentity(identity),
    email: identity.email || undefined,
    created_at: now,
    claim_display_name: displayName,
  });
  await ctx.db.insert("profiles", {
    user_id: userId,
    display_name: displayName,
    revision: 1,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
  await ctx.db.insert("notification_preferences", {
    user_id: userId,
    streak_reminders_enabled: true,
    daily_challenge_enabled: true,
    partner_answered_enabled: true,
    widget_updates_enabled: true,
    location_updates_enabled: true, // silent refresh pushes, so on by default
    lock_screen_detail_level: "private",
    revision: 1,
    created_at: now,
    updated_at: now,
    memories_enabled: true,
    messages_enabled: true,
    games_enabled: true,
    question_time_enabled: false,
    question_time_minutes: DEFAULT_QUESTION_TIME_MINUTES,
  });
  return userId;
}
