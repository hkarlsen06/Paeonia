import type { Doc } from "../_generated/dataModel";
import { hasActiveRelationshipBlock } from "./access";
import { type ReaderCtx, type WriterCtx, withUpdatedAt } from "./db";
import { nameForViewer } from "./partnerNames";
import { createRelationshipSyncEvent } from "./syncEvents";

/**
 * Bringing back an ended relationship. When the same two people pair again before their old
 * couple's cleanup starts, and both agree, the old couple opens again with what
 * `endRelationshipForPair` only hid: answers, chats, memories, drawings, photos and voice. What it
 * deleted (locations, together days, recaps, hearts, call history, nicknames) stays gone.
 *
 * The person who enters the code asks (`accept_pairing_invite` with `p_restore`), which marks the
 * invite. The invite's creator answers (`answer_relationship_restore`). Either way the two end up
 * paired, with the old couple or a new one.
 */

/**
 * The pair's ended couple that may come back now, or null. Only a couple that a partner left can,
 * and only before its cleanup deadline and before the cleanup started. A block, a report or a
 * safety warning in the pair, or a deleted or banned member, rules it out, and the caller pairs
 * the two as new without saying why.
 */
export async function findRestorableCouple(ctx: ReaderCtx, pairId: string, now: string): Promise<Doc<"couples"> | null> {
  const ended = await ctx.db
    .query("couples")
    .withIndex("by_pair_id_status", (q) => q.eq("pair_id", pairId).eq("status", "ended"))
    .collect();
  const couple = ended.sort((a, b) => ((a.ended_at ?? "") < (b.ended_at ?? "") ? 1 : -1))[0];
  if (
    !couple ||
    couple.end_reason !== "user_left" ||
    couple.delete_after === undefined ||
    couple.delete_after <= now ||
    couple.cleanup_started_at !== undefined ||
    couple.purged_at !== undefined
  ) {
    return null;
  }
  if (await hasActiveRelationshipBlock(ctx, pairId)) return null;
  const report = await ctx.db
    .query("content_reports")
    .withIndex("by_pair_id", (q) => q.eq("pair_id", pairId))
    .first();
  const warning = await ctx.db
    .query("pair_safety_warning_flags")
    .withIndex("by_pair_id_created_at", (q) => q.eq("pair_id", pairId))
    .first();
  if (report || warning) return null;
  for (const member of await membersOf(ctx, couple.id)) {
    if (!(await isActiveAccount(ctx, member.user_id))) return null;
  }
  return couple;
}

/** False for a banned person and for one whose account deletion started. */
export async function isActiveAccount(ctx: ReaderCtx, userId: string): Promise<boolean> {
  const user = await ctx.db
    .query("users")
    .withIndex("by_uuid", (q) => q.eq("id", userId))
    .unique();
  if (!user || user.banned_at !== undefined) return false;
  const deletion = await ctx.db
    .query("account_deletion_jobs")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .first();
  return deletion === null;
}

async function membersOf(ctx: ReaderCtx, coupleId: string) {
  return await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
}

/**
 * Opens a couple from `findRestorableCouple` again: both members are active, the cleanup deadline
 * is gone, and each member gets a `relationship_started` event that tells the app to load the
 * couple's content again. Out of the `ended` status the cleanup and purge crons never reach it.
 */
export async function reopenCouple(ctx: WriterCtx, couple: Doc<"couples">, initiatedByUserId: string): Promise<void> {
  await ctx.db.patch(
    couple._id,
    withUpdatedAt({ status: "active" as const, ended_at: undefined, end_reason: undefined, delete_after: undefined }),
  );
  for (const member of await membersOf(ctx, couple.id)) {
    await ctx.db.patch(
      member._id,
      withUpdatedAt({ status: "active" as const, left_at: undefined, ended_notice_seen_at: undefined }),
    );
    await createRelationshipSyncEvent(ctx, {
      user_id: member.user_id,
      couple_id: couple.id,
      initiated_by_user_id: initiatedByUserId,
      event_kind: "relationship_started",
      reason: "relationship_restored",
      relationship_status: "active",
      member_status: "active",
      local_purge_scope: { relationship: "refresh", relationship_content: "refresh", entitlement: "refresh" },
    });
  }
}

/**
 * The request waiting for this person's answer, for the access snapshot, or null. It comes from
 * their newest pending invite that someone asked to bring a relationship back through. An expired
 * invite still shows until the hourly cron marks it, so the answer then pairs nobody.
 */
export async function restoreRequestFor(ctx: ReaderCtx, userId: string) {
  const invites = await ctx.db
    .query("pairing_invites")
    .withIndex("by_created_by_user_id_status_expires_at", (q) => q.eq("created_by_user_id", userId).eq("status", "pending"))
    .collect();
  const asked = invites
    .filter((invite) => invite.restore_requested_by_user_id !== undefined)
    .sort((a, b) => ((a.restore_requested_at ?? "") < (b.restore_requested_at ?? "") ? 1 : -1))[0];
  if (!asked?.restore_requested_by_user_id || !asked.restore_requested_at) return null;
  return {
    invite_id: asked.id,
    partner_user_id: asked.restore_requested_by_user_id,
    partner_name: await nameForViewer(ctx, userId, asked.restore_requested_by_user_id),
    requested_at: asked.restore_requested_at,
  };
}
