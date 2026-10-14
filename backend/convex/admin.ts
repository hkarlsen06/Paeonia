import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { findCurrentCouple, resolveUserEntitlement } from "./lib/access";
import { getCurrentUserId } from "./lib/auth";
import { banUser, unbanUser } from "./lib/bans";
import { getByUuid, orNull } from "./lib/db";
import { fail } from "./lib/errors";
import { newUuid, uuidArg } from "./lib/ids";
import { nowIso } from "./lib/time";

// The admin area. Admins are the Clerk users listed, comma separated, in the
// PAEONIA_ADMIN_CLERK_USER_IDS environment variable. It names Clerk users rather
// than Paeonia rows, so it survives a data wipe, and the app cannot change it.
// Every function here checks it on each call. The app only reads it to show the
// Admin row.

const SEARCH_LIMIT = 50;
const AUDIT_LIMIT = 100;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function adminClerkUserIds(): Set<string> {
  return new Set(
    (process.env.PAEONIA_ADMIN_CLERK_USER_IDS ?? "")
      .split(",")
      .map((id) => id.trim())
      .filter(Boolean),
  );
}

function isAdminUser(user: Doc<"users">): boolean {
  return adminClerkUserIds().has(user.clerk_user_id);
}

/** The signed-in admin's user id. Fails with `42501 admin access required` for everyone else. */
async function requireAdmin(ctx: QueryCtx): Promise<string> {
  const userId = await getCurrentUserId(ctx);
  const user = userId ? await getByUuid(ctx, "users", userId) : null;
  if (!user || !isAdminUser(user)) return fail("42501", "admin access required");
  return user.id;
}

async function displayName(ctx: QueryCtx, userId: string | undefined): Promise<string | null> {
  if (!userId) return null;
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
  return orNull(profile?.display_name);
}

/** One row of the user list. */
async function userRow(ctx: QueryCtx, user: Doc<"users">) {
  return {
    user_id: user.id,
    display_name: await displayName(ctx, user.id),
    auth_provider: user.auth_provider,
    created_at: user.created_at,
    is_admin: isAdminUser(user),
    banned_at: orNull(user.banned_at),
  };
}

async function writeAudit(
  ctx: MutationCtx,
  entry: {
    action: Doc<"admin_audit_log">["action"];
    adminUserId?: string;
    operatorIdentifier?: string;
    targetUserId: string;
    reason?: string;
  },
) {
  await ctx.db.insert("admin_audit_log", {
    id: newUuid(),
    action: entry.action,
    admin_user_id: entry.adminUserId,
    operator_identifier: entry.operatorIdentifier,
    target_user_id: entry.targetUserId,
    reason: entry.reason,
    created_at: nowIso(),
  });
}

/** The user a ban or unban names, after the rules every path shares. */
async function banTarget(ctx: QueryCtx, targetUserId: string, actorUserId?: string): Promise<Doc<"users">> {
  const target = await getByUuid(ctx, "users", targetUserId);
  if (!target) return fail("P0002", "user not found");
  if (actorUserId === target.id) return fail("42501", "you can't ban yourself");
  if (isAdminUser(target)) return fail("42501", "admins can't be banned");
  return target;
}

// ---- App-callable ----

/** Whether the signed-in user is an admin. Only hides or shows the Admin row. */
export const get_admin_status = query({
  args: {},
  handler: async (ctx) => {
    const userId = await getCurrentUserId(ctx);
    const user = userId ? await getByUuid(ctx, "users", userId) : null;
    return { is_admin: user ? isAdminUser(user) : false };
  },
});

/**
 * Users for the admin list, at most 50. A full user id finds that user. Other
 * text searches display names. Empty text lists the newest users. `p_banned_only`
 * lists banned users, newest ban first, and ignores the text.
 */
export const search_users = query({
  args: { p_query: v.optional(v.union(v.null(), v.string())), p_banned_only: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    let users: Doc<"users">[];
    const text = (args.p_query ?? "").trim();
    if (args.p_banned_only) {
      users = await ctx.db
        .query("users")
        .withIndex("by_banned_at", (q) => q.gt("banned_at", ""))
        .order("desc")
        .take(SEARCH_LIMIT);
    } else if (UUID_RE.test(text)) {
      const user = await getByUuid(ctx, "users", text.toLowerCase());
      users = user ? [user] : [];
    } else if (text !== "") {
      const profiles = await ctx.db
        .query("profiles")
        .withSearchIndex("search_display_name", (q) => q.search("display_name", text))
        .take(SEARCH_LIMIT);
      users = [];
      for (const profile of profiles) {
        const user = await getByUuid(ctx, "users", profile.user_id);
        if (user) users.push(user);
      }
    } else {
      users = await ctx.db.query("users").order("desc").take(SEARCH_LIMIT);
    }
    return await Promise.all(users.map((user) => userRow(ctx, user)));
  },
});

/** One user for the admin detail screen. Account facts only, never relationship content. */
export const get_user = query({
  args: { p_user_id: v.string() },
  handler: async (ctx, args) => {
    const adminUserId = await requireAdmin(ctx);
    const user = await getByUuid(ctx, "users", uuidArg(args.p_user_id));
    if (!user) return null;
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user_id", (q) => q.eq("user_id", user.id))
      .unique();
    const couple = await findCurrentCouple(ctx, user.id);
    let partnerUserId: string | null = null;
    if (couple) {
      const members = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id))
        .collect();
      partnerUserId = members.find((member) => member.user_id !== user.id)?.user_id ?? null;
    }
    const entitlement = await resolveUserEntitlement(ctx, user.id);
    const reportsAgainst = await ctx.db
      .query("content_reports")
      .withIndex("by_reported_user_id_created_at", (q) => q.eq("reported_user_id", user.id))
      .collect();
    const reportsBy = await ctx.db
      .query("content_reports")
      .withIndex("by_reporter_user_id_created_at", (q) => q.eq("reporter_user_id", user.id))
      .collect();
    return {
      ...(await userRow(ctx, user)),
      is_self: user.id === adminUserId,
      ban_reason: orNull(user.ban_reason),
      banned_by_display_name: await displayName(ctx, user.banned_by_user_id),
      onboarding_completed_at: orNull(profile?.onboarding_completed_at),
      time_zone_id: orNull(profile?.time_zone_id),
      is_entitled: entitlement.is_entitled,
      couple_id: couple?.id ?? null,
      paired_since: orNull(couple?.started_on ?? couple?.created_at),
      partner_user_id: partnerUserId,
      partner_display_name: await displayName(ctx, partnerUserId ?? undefined),
      reports_against_count: reportsAgainst.length,
      reports_by_count: reportsBy.length,
    };
  },
});

/** Bans a user. Returns `{ changed: false }` when they were already banned. */
export const ban_user = mutation({
  args: { p_user_id: v.string(), p_reason: v.string() },
  handler: async (ctx, args) => {
    const adminUserId = await requireAdmin(ctx);
    const target = await banTarget(ctx, uuidArg(args.p_user_id), adminUserId);
    const changed = await banUser(ctx, target.id, { reason: args.p_reason, bannedByUserId: adminUserId });
    if (changed) {
      await writeAudit(ctx, {
        action: "user_banned",
        adminUserId,
        targetUserId: target.id,
        reason: args.p_reason.trim(),
      });
    }
    return { changed };
  },
});

/** Lifts a ban. Returns `{ changed: false }` when they were not banned. */
export const unban_user = mutation({
  args: { p_user_id: v.string() },
  handler: async (ctx, args) => {
    const adminUserId = await requireAdmin(ctx);
    const target = await getByUuid(ctx, "users", uuidArg(args.p_user_id));
    if (!target) return fail("P0002", "user not found");
    const changed = await unbanUser(ctx, target.id);
    if (changed) await writeAudit(ctx, { action: "user_unbanned", adminUserId, targetUserId: target.id });
    return { changed };
  },
});

/** The newest admin actions, at most 100, optionally for one user. */
export const get_audit_log = query({
  args: { p_target_user_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const targetUserId = args.p_target_user_id ? uuidArg(args.p_target_user_id) : null;
    const entries = targetUserId
      ? await ctx.db
          .query("admin_audit_log")
          .withIndex("by_target_user_id_created_at", (q) => q.eq("target_user_id", targetUserId))
          .order("desc")
          .take(AUDIT_LIMIT)
      : await ctx.db.query("admin_audit_log").withIndex("by_created_at").order("desc").take(AUDIT_LIMIT);
    return await Promise.all(
      entries.map(async (entry) => ({
        id: entry.id,
        action: entry.action,
        admin_user_id: orNull(entry.admin_user_id),
        admin_display_name: await displayName(ctx, entry.admin_user_id),
        operator_identifier: orNull(entry.operator_identifier),
        target_user_id: entry.target_user_id,
        target_display_name: await displayName(ctx, entry.target_user_id),
        reason: orNull(entry.reason),
        created_at: entry.created_at,
      })),
    );
  },
});

// ---- Operator commands (`npx convex run`) ----

/** Bans a user from the command line, with the same rules as the admin screen. */
export const operator_ban_user = internalMutation({
  args: { p_user_id: v.string(), p_reason: v.string(), p_operator: v.string() },
  handler: async (ctx, args) => {
    const target = await banTarget(ctx, uuidArg(args.p_user_id));
    const changed = await banUser(ctx, target.id, { reason: args.p_reason });
    if (changed) {
      await writeAudit(ctx, {
        action: "user_banned",
        operatorIdentifier: args.p_operator,
        targetUserId: target.id,
        reason: args.p_reason.trim(),
      });
    }
    return { changed };
  },
});

/** Lifts a ban from the command line. */
export const operator_unban_user = internalMutation({
  args: { p_user_id: v.string(), p_operator: v.string() },
  handler: async (ctx, args) => {
    const userId = uuidArg(args.p_user_id);
    const changed = await unbanUser(ctx, userId);
    if (changed) {
      await writeAudit(ctx, { action: "user_unbanned", operatorIdentifier: args.p_operator, targetUserId: userId });
    }
    return { changed };
  },
});
