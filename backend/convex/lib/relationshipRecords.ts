import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";

// The rows that say who was paired with whom and when: `relationship_pairs`, `couples`,
// `couple_members`, `relationship_sync_events` and `pairing_invites`. They hold no content, so
// the couple purge leaves them. `retention.ts` deletes them once nothing needs them, and account
// deletion deletes the person's own at once.

/** Deletes an invite with its hashed code. */
export async function deletePairingInvite(ctx: WriterCtx, invite: Doc<"pairing_invites">): Promise<void> {
  const secrets = await ctx.db
    .query("pairing_invite_secrets")
    .withIndex("by_invite_id", (q) => q.eq("invite_id", invite.id))
    .collect();
  for (const secret of secrets) await ctx.db.delete(secret._id);
  await ctx.db.delete(invite._id);
}

/**
 * Deletes what is left of a couple once its content is gone: both partners' sync events and
 * member rows, the invites that led to it, and the couple row.
 */
export async function deleteCoupleRecords(ctx: WriterCtx, couple: Doc<"couples">): Promise<void> {
  const rows = [
    ...(await ctx.db
      .query("relationship_sync_events")
      .withIndex("by_couple_id_created_at_id", (q) => q.eq("couple_id", couple.id))
      .collect()),
    ...(await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id))
      .collect()),
  ];
  for (const row of rows) await ctx.db.delete(row._id);
  const invites = await ctx.db
    .query("pairing_invites")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const invite of invites) await deletePairingInvite(ctx, invite);
  await ctx.db.delete(couple._id);
}

/**
 * Account deletion: deletes the person's own member rows, sync events and invites in every
 * relationship they had. The partner keeps theirs, with the couple and the pair, until the couple
 * is purged and no block or report stands on the pair. Code that needs both people of an ended
 * couple reads the pair (`pairPartnerOf` in `lib/access.ts`).
 */
export async function deleteUserRelationshipRecords(ctx: WriterCtx, userId: string): Promise<void> {
  const rows = [
    ...(await ctx.db
      .query("couple_members")
      .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId))
      .collect()),
    ...(await ctx.db
      .query("relationship_sync_events")
      .withIndex("by_user_id_created_at_id", (q) => q.eq("user_id", userId))
      .collect()),
  ];
  for (const row of rows) await ctx.db.delete(row._id);
  const invites = await ctx.db
    .query("pairing_invites")
    .withIndex("by_created_by_user_id_status_expires_at", (q) => q.eq("created_by_user_id", userId))
    .collect();
  for (const invite of invites) await deletePairingInvite(ctx, invite);
}

/**
 * True while a block, a safety warning or a report stands on the pair. Each has its own end: a
 * block when the person who made it takes it back or either of the two deletes their account, a warning and a
 * report three years after the report closed. Until then the pair and its couples stay, so a
 * block still stops the two from pairing and a report still says which relationship it was about.
 */
export async function pairIsHeld(ctx: ReaderCtx, pairId: string): Promise<boolean> {
  return (
    (await ctx.db
      .query("relationship_blocks")
      .withIndex("by_pair_id", (q) => q.eq("pair_id", pairId))
      .first()) !== null ||
    (await ctx.db
      .query("pair_safety_warning_flags")
      .withIndex("by_pair_id_created_at", (q) => q.eq("pair_id", pairId))
      .first()) !== null ||
    (await ctx.db
      .query("content_reports")
      .withIndex("by_pair_id", (q) => q.eq("pair_id", pairId))
      .first()) !== null
  );
}
