import type { WriterCtx } from "./db";
import { getByUuid } from "./db";
import { fail } from "./errors";
import { endRelationshipForPair } from "./relationshipEnd";
import { newUuid } from "./ids";
import { nowIso } from "./time";

/** `insert into internal.pair_safety_warning_flags ... on conflict do nothing`. */
export async function addPairSafetyWarningFlag(ctx: WriterCtx, pairId: string, sourceReportId: string): Promise<void> {
  const existing = await ctx.db
    .query("pair_safety_warning_flags")
    .withIndex("by_pair_id_source_report_id", (q) => q.eq("pair_id", pairId).eq("source_report_id", sourceReportId))
    .first();
  if (!existing) {
    await ctx.db.insert("pair_safety_warning_flags", {
      id: newUuid(),
      pair_id: pairId,
      source_report_id: sourceReportId,
      created_at: nowIso(),
    });
  }
}

/**
 * Inserts the active block for (pair, blockedBy, blocked) or keeps the existing
 * one, filling in `source_report_id` when it was empty. Includes the
 * `assert_relationship_block_pair_members` trigger check. Returns the block id.
 */
export async function upsertRelationshipBlock(
  ctx: WriterCtx,
  pairId: string,
  blockedByUserId: string,
  blockedUserId: string,
  sourceReportId: string | undefined,
): Promise<string> {
  const pair = await getByUuid(ctx, "relationship_pairs", pairId);
  if (!pair) {
    return fail("23503", "relationship pair not found");
  }
  const members = [pair.user_low_id, pair.user_high_id];
  if (!(members.includes(blockedByUserId) && members.includes(blockedUserId) && blockedByUserId !== blockedUserId)) {
    return fail("23514", "relationship block users must match the pair");
  }
  const rows = await ctx.db
    .query("relationship_blocks")
    .withIndex("by_pair_id_blocked_by_user_id_blocked_user_id", (q) =>
      q.eq("pair_id", pairId).eq("blocked_by_user_id", blockedByUserId).eq("blocked_user_id", blockedUserId),
    )
    .collect();
  const active = rows.find((row) => row.revoked_at === undefined);
  if (active) {
    if (active.source_report_id === undefined && sourceReportId !== undefined) {
      await ctx.db.patch(active._id, { source_report_id: sourceReportId });
    }
    return active.id;
  }
  const id = newUuid();
  await ctx.db.insert("relationship_blocks", {
    id,
    pair_id: pairId,
    blocked_by_user_id: blockedByUserId,
    blocked_user_id: blockedUserId,
    source_report_id: sourceReportId,
    created_at: nowIso(),
  });
  return id;
}

/**
 * Port of `internal.block_relationship` (the version that reads `auth.uid()`;
 * the caller passes the user id). Blocks a current or recently ended partner,
 * flags the pair when the block came from a report, and ends the relationship.
 * Returns the block id.
 */
export async function blockRelationship(
  ctx: WriterCtx,
  currentUserId: string,
  blockedUserId: string | null | undefined,
  sourceReportId?: string,
): Promise<string> {
  if (!blockedUserId || blockedUserId === currentUserId) {
    return fail("23514", "blocked user must be a different user");
  }

  // The newest active couple the two share, else the newest ended one still inside its retention window.
  const now = nowIso();
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", currentUserId))
    .collect();
  let best: { pairId: string; active: boolean; createdAt: string } | null = null;
  for (const membership of memberships) {
    const blockedMember = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", membership.couple_id).eq("user_id", blockedUserId))
      .unique();
    if (!blockedMember) continue;
    const couple = await getByUuid(ctx, "couples", membership.couple_id);
    if (!couple) continue;
    const active = couple.status === "active";
    if (!active && !(couple.status === "ended" && couple.delete_after !== undefined && couple.delete_after > now)) {
      continue;
    }
    if (!best || (active && !best.active) || (active === best.active && couple.created_at > best.createdAt)) {
      best = { pairId: couple.pair_id, active, createdAt: couple.created_at };
    }
  }
  if (!best) {
    return fail("42501", "blocked user must be a current or recently ended partner");
  }
  const pairId = best.pairId;

  if (sourceReportId !== undefined) {
    const report = await getByUuid(ctx, "content_reports", sourceReportId);
    if (
      !report ||
      report.reporter_user_id !== currentUserId ||
      report.reported_user_id !== blockedUserId ||
      report.pair_id !== pairId
    ) {
      return fail("42501", "source report does not belong to this block");
    }
  }

  const blockId = await upsertRelationshipBlock(ctx, pairId, currentUserId, blockedUserId, sourceReportId);
  if (sourceReportId !== undefined) {
    await addPairSafetyWarningFlag(ctx, pairId, sourceReportId);
  }
  await endRelationshipForPair(ctx, pairId, currentUserId, "blocked");
  return blockId;
}
