import type { WriterCtx } from "./db";
import { withUpdatedAt } from "./db";
import { fail } from "./errors";
import { deleteHeartsForCouple } from "./hearts";
import { removePresenceRooms } from "./presence";
import { createRelationshipSyncEvent } from "./syncEvents";
import { addDaysToInstant, nowIso } from "./time";

/**
 * Port of the `delete_latest_locations_on_relationship_end` trigger. Call when
 * a couple stops being active.
 */
export async function deleteLatestLocationsForCouple(ctx: WriterCtx, coupleId: string): Promise<void> {
  const rows = await ctx.db
    .query("latest_partner_locations")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  for (const row of rows) {
    await ctx.db.delete(row._id);
  }
}

/**
 * Port of `internal.end_relationship_for_pair`. Ends the pair's active couple,
 * marks the initiator as left and the partner as ended_notice_pending, writes a
 * relationship_ended sync event per member, and removes shared locations and presence.
 * Returns false when the pair has no active couple.
 */
export async function endRelationshipForPair(
  ctx: WriterCtx,
  pairId: string,
  initiatedByUserId: string,
  reason: string,
): Promise<boolean> {
  const couples = await ctx.db
    .query("couples")
    .withIndex("by_pair_id_status", (q) => q.eq("pair_id", pairId).eq("status", "active"))
    .collect();
  couples.sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0));
  const couple = couples[0];
  if (!couple) {
    return false;
  }

  const now = nowIso();
  const cleanupDeadline = addDaysToInstant(now, 30);
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  const initiator = members.find((member) => member.user_id === initiatedByUserId);
  if (initiator?.status !== "active") {
    // The SQL raised after updating the couple row. The transaction rolled back, so nothing persists.
    return fail("42501", "initiating user is not an active member of the relationship");
  }

  await ctx.db.patch(couple._id, withUpdatedAt({ status: "ended" as const, ended_at: now, delete_after: cleanupDeadline }));
  await deleteLatestLocationsForCouple(ctx, couple.id);
  await deleteHeartsForCouple(ctx, couple.id);
  // Open game screens and typing dots of both partners go at once.
  await removePresenceRooms(ctx, members.map((member) => member.user_id), `${couple.id}:`);
  await ctx.db.patch(initiator._id, withUpdatedAt({ status: "left" as const, left_at: now }));
  for (const member of members) {
    if (member.user_id !== initiatedByUserId && member.status === "active") {
      await ctx.db.patch(member._id, withUpdatedAt({ status: "ended_notice_pending" as const }));
    }
  }

  const updated = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const member of updated) {
    await createRelationshipSyncEvent(ctx, {
      user_id: member.user_id,
      couple_id: couple.id,
      initiated_by_user_id: initiatedByUserId,
      event_kind: "relationship_ended",
      reason,
      relationship_status: "ended",
      member_status: member.status,
      ended_at: now,
      delete_after: cleanupDeadline,
      local_purge_scope: {
        relationship_content: "hide",
        location: "purge",
        widget_cache: "purge",
        pending_uploads: "review",
      },
    });
  }
  return true;
}
