import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import {
  accessEndsAt,
  compareByPeriodAndUpdate,
  resolveUserEntitlement,
  type ResolvedEntitlement,
} from "./entitlements";
import { fail } from "./errors";
import { newUuid } from "./ids";
import { nowIso } from "./time";

export { resolveUserEntitlement, userHasDirectEntitlement } from "./entitlements";
export type { ResolvedEntitlement } from "./entitlements";

/**
 * Access helpers port the SQL `security definer` functions that RLS policies
 * and RPCs used. The SQL read `auth.uid()`; here the caller passes the user id
 * it got from `requireUserId`.
 */

/** Port of `internal.is_admin`. It always returned false. Operator work runs through internal functions. */
export function isAdmin(): boolean {
  return false;
}

/** Active members of a couple whose couple row is active. Empty when the couple is not active. */
export async function listActiveMembers(
  ctx: ReaderCtx,
  coupleId: string,
): Promise<Doc<"couple_members">[]> {
  const couple = await getByUuid(ctx, "couples", coupleId);
  if (!couple || couple.status !== "active") {
    return [];
  }
  return await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .collect();
}

/** Port of `internal.is_active_couple_member`. */
export async function isActiveCoupleMember(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
): Promise<boolean> {
  const couple = await getByUuid(ctx, "couples", coupleId);
  if (!couple || couple.status !== "active") {
    return false;
  }
  const member = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
    .unique();
  return member?.status === "active";
}

/** True when any active member of the couple has a direct entitlement. */
export async function coupleHasEntitledMember(ctx: ReaderCtx, coupleId: string): Promise<boolean> {
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .collect();
  for (const member of members) {
    if ((await resolveUserEntitlement(ctx, member.user_id)).is_entitled) {
      return true;
    }
  }
  return false;
}

/** Port of `internal.is_active_entitled_couple_member`. */
export async function isActiveEntitledCoupleMember(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
): Promise<boolean> {
  return (await isActiveCoupleMember(ctx, userId, coupleId)) && (await coupleHasEntitledMember(ctx, coupleId));
}

/** Port of `internal.can_access_couple_content`. */
export async function canAccessCoupleContent(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
): Promise<boolean> {
  return await isActiveEntitledCoupleMember(ctx, userId, coupleId);
}

/** Port of `internal.can_access_visible_memory`. */
export async function canAccessVisibleMemory(
  ctx: ReaderCtx,
  userId: string,
  memoryId: string,
): Promise<boolean> {
  const memory = await getByUuid(ctx, "memories", memoryId);
  return (
    memory !== null &&
    memory.deleted_at === undefined &&
    memory.moderation_status === "visible" &&
    (await canAccessCoupleContent(ctx, userId, memory.couple_id))
  );
}

/** Port of `internal.is_couple_pair_member`. Former members (left, ended) still count. */
export async function isCouplePairMember(
  ctx: ReaderCtx,
  userId: string,
  pairId: string,
): Promise<boolean> {
  const couples = await ctx.db
    .query("couples")
    .withIndex("by_pair_id_status", (q) => q.eq("pair_id", pairId))
    .collect();
  for (const couple of couples) {
    const member = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id).eq("user_id", userId))
      .unique();
    if (member) {
      return true;
    }
  }
  return false;
}

/** The newest active couple that `userId` actively belongs to, or null. */
export async function findCurrentCouple(
  ctx: ReaderCtx,
  userId: string,
): Promise<Doc<"couples"> | null> {
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId).eq("status", "active"))
    .collect();
  let current: Doc<"couples"> | null = null;
  for (const membership of memberships) {
    const couple = await getByUuid(ctx, "couples", membership.couple_id);
    if (couple && couple.status === "active" && (!current || couple.created_at > current.created_at)) {
      current = couple;
    }
  }
  return current;
}

/** Port of `internal.get_entitled_couple_id_for_user`. */
export async function getEntitledCoupleIdForUser(
  ctx: ReaderCtx,
  userId: string,
): Promise<string | null> {
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId).eq("status", "active"))
    .collect();
  const couples: Doc<"couples">[] = [];
  for (const membership of memberships) {
    const couple = await getByUuid(ctx, "couples", membership.couple_id);
    if (couple && couple.status === "active") {
      couples.push(couple);
    }
  }
  couples.sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0));
  for (const couple of couples) {
    if (await coupleHasEntitledMember(ctx, couple.id)) {
      return couple.id;
    }
  }
  return null;
}

/** Port of `internal.get_current_entitled_couple_id`. Fails with 42501 when there is none. */
export async function getCurrentEntitledCoupleId(ctx: ReaderCtx, userId: string): Promise<string> {
  const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
  if (!coupleId) {
    return fail("42501", "active entitled couple access is required");
  }
  return coupleId;
}

export type CoupleEntitlement = {
  couple_id: string;
  is_entitled: boolean;
  covering_user_id: string | null;
  source: string | null;
  status: string | null;
  product_id: string | null;
  billing_period: string | null;
  current_period_end: string | null;
  /** When the couple's access ends because nobody's subscription renews, or null. Both partners see it. */
  access_ends_at: string | null;
  updated_at: string | null;
};

function statusRank(status: string | null): number {
  return status === "lifetime" ? 0 : status === "active" ? 1 : status === "grace" ? 2 : 3;
}

/** Port of `internal.resolve_current_couple_entitlement`. Returns null when the user has no active couple. */
export async function resolveCurrentCoupleEntitlement(
  ctx: ReaderCtx,
  userId: string,
): Promise<CoupleEntitlement | null> {
  const couple = await findCurrentCouple(ctx, userId);
  if (!couple) {
    return null;
  }
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", couple.id).eq("status", "active"))
    .collect();
  const resolvedMembers: ResolvedEntitlement[] = [];
  for (const member of members) {
    resolvedMembers.push(await resolveUserEntitlement(ctx, member.user_id));
  }
  const entitled = resolvedMembers.filter((resolved) => resolved.is_entitled);
  entitled.sort((a, b) => {
    const rank = statusRank(a.status) - statusRank(b.status);
    return rank !== 0 ? rank : compareByPeriodAndUpdate(a, b);
  });
  const best = entitled[0];
  return {
    couple_id: couple.id,
    is_entitled: entitled.length > 0,
    covering_user_id: best?.user_id ?? null,
    source: best?.source ?? null,
    status: best?.status ?? null,
    product_id: best?.product_id ?? null,
    billing_period: best?.billing_period ?? null,
    current_period_end: best?.current_period_end ?? null,
    access_ends_at: accessEndsAt(resolvedMembers),
    updated_at: best?.updated_at ?? null,
  };
}

/** Port of `internal.has_active_relationship_block`. */
export async function hasActiveRelationshipBlock(ctx: ReaderCtx, pairId: string): Promise<boolean> {
  const block = await ctx.db
    .query("relationship_blocks")
    .withIndex("by_pair_id_revoked_at", (q) => q.eq("pair_id", pairId).eq("revoked_at", undefined))
    .first();
  return block !== null;
}

function orderedPair(first: string, second: string): { low: string; high: string } {
  return first < second ? { low: first, high: second } : { low: second, high: first };
}

/** Port of `internal.find_relationship_pair_id`. */
export async function findRelationshipPairId(
  ctx: ReaderCtx,
  firstUserId: string | null | undefined,
  secondUserId: string | null | undefined,
): Promise<string | null> {
  if (!firstUserId || !secondUserId || firstUserId === secondUserId) {
    return null;
  }
  const { low, high } = orderedPair(firstUserId, secondUserId);
  const pair = await ctx.db
    .query("relationship_pairs")
    .withIndex("by_user_low_id_user_high_id", (q) => q.eq("user_low_id", low).eq("user_high_id", high))
    .unique();
  return pair?.id ?? null;
}

/** Port of `internal.get_or_create_relationship_pair`. */
export async function getOrCreateRelationshipPair(
  ctx: WriterCtx,
  firstUserId: string | null | undefined,
  secondUserId: string | null | undefined,
): Promise<string> {
  if (!firstUserId || !secondUserId || firstUserId === secondUserId) {
    return fail("23514", "relationship pair requires two distinct users");
  }
  const existing = await findRelationshipPairId(ctx, firstUserId, secondUserId);
  if (existing) {
    return existing;
  }
  const { low, high } = orderedPair(firstUserId, secondUserId);
  const id = newUuid();
  await ctx.db.insert("relationship_pairs", {
    id,
    user_low_id: low,
    user_high_id: high,
    created_at: nowIso(),
  });
  return id;
}
