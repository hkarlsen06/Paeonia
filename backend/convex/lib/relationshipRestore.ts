import type { Doc } from "../_generated/dataModel";
import { findCurrentCouple, findRelationshipPairId, hasActiveRelationshipBlock } from "./access";
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
  if (await pairHasSafetyConcern(ctx, pairId)) return null;
  for (const member of await membersOf(ctx, couple.id)) {
    if (!(await isActiveAccount(ctx, member.user_id))) return null;
  }
  return couple;
}

/** True when the pair has a block, a report or a safety warning, at any time. */
async function pairHasSafetyConcern(ctx: ReaderCtx, pairId: string): Promise<boolean> {
  if (await hasActiveRelationshipBlock(ctx, pairId)) return true;
  const report = await ctx.db
    .query("content_reports")
    .withIndex("by_pair_id", (q) => q.eq("pair_id", pairId))
    .first();
  const warning = await ctx.db
    .query("pair_safety_warning_flags")
    .withIndex("by_pair_id_created_at", (q) => q.eq("pair_id", pairId))
    .first();
  return report !== null || warning !== null;
}

/**
 * The person who asked through this invite and the pair, while their request still stands, or
 * null. It stands while the invite is pending, both accounts are active, neither person is in a
 * couple, and nothing in the pair speaks against it: a block, report or safety warning made after
 * the request ends it at once, before the creator is told or answers. It reads no clock, so the
 * access snapshot can use it, and the answer checks the invite's expiry itself. A request that
 * stands while its couple can no longer come back still pairs the two as new.
 */
export async function standingRestoreRequest(
  ctx: ReaderCtx,
  invite: Doc<"pairing_invites">,
): Promise<{ requesterUserId: string; pairId: string } | null> {
  const requesterUserId = invite.restore_requested_by_user_id;
  if (!requesterUserId || invite.status !== "pending") return null;
  const pairId = await findRelationshipPairId(ctx, invite.created_by_user_id, requesterUserId);
  if (pairId === null || (await pairHasSafetyConcern(ctx, pairId))) return null;
  for (const userId of [invite.created_by_user_id, requesterUserId]) {
    if (!(await isActiveAccount(ctx, userId)) || (await findCurrentCouple(ctx, userId)) !== null) return null;
  }
  return { requesterUserId, pairId };
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

/** This person's pending invites that someone asked through, newest request first. */
async function askedInvitesOf(ctx: ReaderCtx, userId: string): Promise<Doc<"pairing_invites">[]> {
  const invites = await ctx.db
    .query("pairing_invites")
    .withIndex("by_created_by_user_id_status_expires_at", (q) => q.eq("created_by_user_id", userId).eq("status", "pending"))
    .collect();
  return invites
    .filter((invite) => invite.restore_requested_at !== undefined)
    .sort((a, b) => (a.restore_requested_at! < b.restore_requested_at! ? 1 : -1));
}

/**
 * The request waiting for this person's answer, for the access snapshot, or null. It comes from
 * their newest pending invite with a request that still stands. An expired invite still shows
 * until the hourly cron marks it, so the answer then pairs nobody. The app sends `invite_id` and
 * `partner_user_id` back with the answer, so the answer is about the person it showed. The
 * requester's profile photo comes along, and `isAskedToRestoreBy` lets this person read it.
 */
export async function restoreRequestFor(ctx: ReaderCtx, userId: string) {
  for (const invite of await askedInvitesOf(ctx, userId)) {
    const request = await standingRestoreRequest(ctx, invite);
    if (!request) continue;
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user_id", (q) => q.eq("user_id", request.requesterUserId))
      .unique();
    const visible = profile?.moderation_status === "visible" && profile.deleted_at === undefined;
    return {
      invite_id: invite.id,
      partner_user_id: request.requesterUserId,
      partner_name: await nameForViewer(ctx, userId, request.requesterUserId),
      partner_profile_photo_asset_id: visible
        ? profile.profile_photo_asset_id ?? profile.provider_profile_photo_asset_id ?? null
        : null,
      requested_at: invite.restore_requested_at!,
    };
  }
  return null;
}

/** True while `requesterUserId` has a request that stands and waits for this person's answer. */
export async function isAskedToRestoreBy(ctx: ReaderCtx, userId: string, requesterUserId: string): Promise<boolean> {
  for (const invite of await askedInvitesOf(ctx, userId)) {
    if (invite.restore_requested_by_user_id === requesterUserId && (await standingRestoreRequest(ctx, invite)) !== null) {
      return true;
    }
  }
  return false;
}
