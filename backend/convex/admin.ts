import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { findCurrentCouple, resolveUserEntitlement } from "./lib/access";
import { getCurrentUserId } from "./lib/auth";
import { banUser, unbanUser } from "./lib/bans";
import { getByUuid, withTouch } from "./lib/db";
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
  return profile?.display_name ?? null;
}

/** One row of the user list. */
async function userRow(ctx: QueryCtx, user: Doc<"users">) {
  return {
    user_id: user.id,
    display_name: await displayName(ctx, user.id),
    auth_provider: user.auth_provider,
    created_at: user.created_at,
    is_admin: isAdminUser(user),
    banned_at: user.banned_at ?? null,
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
      ban_reason: user.ban_reason ?? null,
      banned_by_display_name: await displayName(ctx, user.banned_by_user_id),
      onboarding_completed_at: profile?.onboarding_completed_at ?? null,
      time_zone_id: profile?.time_zone_id ?? null,
      is_entitled: entitlement.is_entitled,
      couple_id: couple?.id ?? null,
      paired_since: couple?.started_on ?? couple?.created_at ?? null,
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
        admin_user_id: entry.admin_user_id ?? null,
        admin_display_name: await displayName(ctx, entry.admin_user_id),
        operator_identifier: entry.operator_identifier ?? null,
        target_user_id: entry.target_user_id,
        target_display_name: await displayName(ctx, entry.target_user_id),
        reason: entry.reason ?? null,
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

// ---- What waits for the operator ----

/** `operator_inbox` counts and lists at most this many rows of each kind and status. */
const INBOX_LIMIT = 200;
const INBOX_IDS = 20;

/** The count of some waiting rows, the times of the first and the last, and the ids of the first few. */
function waitingSummary(waiting: { count: number; first: string[]; last: string[]; ids: string[] }) {
  return {
    count: waiting.count,
    oldest: waiting.first.sort()[0] ?? null,
    newest: waiting.last.sort().at(-1) ?? null,
    ids: waiting.ids.slice(0, INBOX_IDS),
  };
}

/**
 * What waits for the operator and nothing in the app will finish by itself: reports nobody
 * resolved, correction requests nobody answered, and account deletions that ran out of tries.
 * Each part holds a count, when its oldest and newest item arrived, and a few ids to act on.
 * The watchdog on the server asks every few minutes and emails when an answer changes. A count
 * stops at the limit, and `newest` still moves with every new item.
 *
 * To clear an item: `moderation:apply_report_moderation_action` (`dismiss` when a report needs no
 * action), `admin:operator_resolve_correction_request`, `accountDeletion:retry_account_deletion_job`.
 */
export const operator_inbox = internalQuery({
  args: {},
  handler: async (ctx) => {
    const empty = () => ({ count: 0, first: [] as string[], last: [] as string[], ids: [] as string[] });
    const add = (to: ReturnType<typeof empty>, rows: { id: string }[], first?: string, last?: string) => {
      to.count += rows.length;
      to.ids.push(...rows.map((row) => row.id));
      if (first !== undefined) to.first.push(first);
      if (last !== undefined) to.last.push(last);
    };

    const reports = empty();
    for (const status of ["submitted", "under_review"] as const) {
      const waiting = () =>
        ctx.db.query("content_reports").withIndex("by_status_created_at", (q) => q.eq("status", status));
      const rows = await waiting().take(INBOX_LIMIT);
      add(reports, rows, rows[0]?.created_at, (await waiting().order("desc").first())?.created_at);
    }

    const corrections = empty();
    for (const status of ["submitted", "verifying", "processing"] as const) {
      const waiting = () =>
        ctx.db
          .query("privacy_requests")
          .withIndex("by_request_kind_status_requested_at", (q) => q.eq("request_kind", "correction").eq("status", status));
      const rows = await waiting().take(INBOX_LIMIT);
      add(corrections, rows, rows[0]?.requested_at, (await waiting().order("desc").first())?.requested_at);
    }

    const deletions = empty();
    const stuck = () =>
      ctx.db.query("account_deletion_jobs").withIndex("by_status_updated_at", (q) => q.eq("status", "attention_required"));
    const stuckRows = await stuck().take(INBOX_LIMIT);
    add(deletions, stuckRows, stuckRows[0]?.updated_at, (await stuck().order("desc").first())?.updated_at);

    return {
      reports: waitingSummary(reports),
      correction_requests: waitingSummary(corrections),
      account_deletions: waitingSummary(deletions),
    };
  },
});

/**
 * Answers a correction request from the command line, after the operator made the correction or
 * decided against it. `p_message` is what the person reads under the request in the app, so write
 * it for them. Returns false for a request that is not an open correction request.
 */
export const operator_resolve_correction_request = internalMutation({
  args: {
    p_request_id: v.string(),
    p_outcome: v.union(v.literal("completed"), v.literal("rejected")),
    p_message: v.optional(v.string()),
    p_operator: v.string(),
  },
  handler: async (ctx, args): Promise<boolean> => {
    const operator = args.p_operator.trim();
    const message = args.p_message?.trim() || undefined;
    if (operator === "") fail("23514", "operator identifier is required");
    if (message !== undefined && Array.from(message).length > 500) fail("23514", "status message is too long");
    const request = await getByUuid(ctx, "privacy_requests", uuidArg(args.p_request_id));
    const isOpen = request !== null && ["submitted", "verifying", "processing"].includes(request.status);
    if (!request || request.request_kind !== "correction" || !isOpen) return false;
    const now = nowIso();
    await ctx.db.patch(
      request._id,
      withTouch(request, {
        status: args.p_outcome,
        completed_at: args.p_outcome === "completed" ? now : undefined,
        visible_status_message: message,
      }),
    );
    await ctx.db.insert("privacy_request_events", {
      id: newUuid(),
      request_id: request.id,
      event_kind: "correction_resolved",
      metadata: { outcome: args.p_outcome, operator },
      created_at: now,
    });
    return true;
  },
});
