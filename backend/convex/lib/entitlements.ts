import type { Doc } from "../_generated/dataModel";
import { getByUuid, type ReaderCtx } from "./db";
import { nowIso } from "./time";

/** One row of the SQL `user_entitlements` view. */
export type EntitlementRow = {
  user_id: string;
  source: string;
  status: string;
  product_id: string | null;
  current_period_end: string | null;
  updated_at: string;
};

/** Result of `resolve_user_entitlement`. Fields other than user_id and is_entitled are null when the user has no entitlement rows. */
export type ResolvedEntitlement = {
  user_id: string;
  is_entitled: boolean;
  source: string | null;
  status: string | null;
  product_id: string | null;
  /** "monthly" or "yearly" for a subscription product. Null for grants without a product. */
  billing_period: string | null;
  current_period_end: string | null;
  updated_at: string | null;
};

function storekitRow(tx: Doc<"storekit_transactions">): EntitlementRow {
  return {
    user_id: tx.user_id,
    source: "storekit",
    status: tx.status,
    product_id: tx.product_id,
    current_period_end: tx.expires_at ?? null,
    updated_at: tx.updated_at,
  };
}

function grantRow(grant: Doc<"entitlement_grants">, now: string): EntitlementRow {
  const source =
    grant.grant_kind === "lifetime"
      ? "lifetime_grant"
      : grant.grant_kind === "review"
        ? "review_grant"
        : "test_grant";
  let status: string;
  if (grant.status === "revoked") {
    status = "revoked";
  } else if (grant.status === "expired") {
    status = "expired";
  } else if (grant.expires_at !== undefined && grant.expires_at <= now) {
    status = "expired";
  } else if (grant.grant_kind === "lifetime") {
    status = "lifetime";
  } else {
    status = "active";
  }
  return {
    user_id: grant.user_id,
    source,
    status,
    product_id: grant.product_id ?? null,
    current_period_end: grant.expires_at ?? null,
    updated_at: grant.updated_at,
  };
}

/** Transaction statuses that can grant access. Only the newest rows of these decide whether a user is entitled. */
const LIVE_STATUSES = ["active", "grace"] as const;
const OTHER_STATUSES = ["billing_retry", "expired", "revoked", "refunded"] as const;

/**
 * The rows of the SQL `user_entitlements` view that can decide `resolveUserEntitlement`, for one user:
 * the newest StoreKit transactions of each status plus the entitlement grants. A renewal is a new
 * transaction, so a long subscriber has many expired ones and this reads a few of them.
 * Within a status the row with the latest end wins, so an older row is never the best one.
 */
export async function listUserEntitlements(
  ctx: ReaderCtx,
  userId: string,
  now: string = nowIso(),
): Promise<EntitlementRow[]> {
  const transactions: Doc<"storekit_transactions">[] = [];
  for (const [statuses, count] of [
    [LIVE_STATUSES, 2],
    [OTHER_STATUSES, 1],
  ] as const) {
    for (const status of statuses) {
      transactions.push(
        ...(await ctx.db
          .query("storekit_transactions")
          .withIndex("by_user_id_status_expires_at", (q) => q.eq("user_id", userId).eq("status", status))
          .order("desc")
          .take(count)),
      );
    }
  }
  const grants = await ctx.db
    .query("entitlement_grants")
    .withIndex("by_user_id_status_expires_at", (q) => q.eq("user_id", userId))
    .collect();
  return [...transactions.map(storekitRow), ...grants.map((grant) => grantRow(grant, now))];
}

function grantsAccess(row: EntitlementRow, now: string): boolean {
  const end = row.current_period_end;
  if (row.source === "storekit") {
    return (row.status === "active" || row.status === "grace") && end !== null && end > now;
  }
  if (row.source === "lifetime_grant") {
    return row.status === "lifetime" && (end === null || end > now);
  }
  return row.status === "active" && end !== null && end > now;
}

function statusRank(status: string): number {
  switch (status) {
    case "lifetime":
      return 0;
    case "active":
      return 1;
    case "grace":
      return 2;
    default:
      return 3;
  }
}

/** Sort order shared with SQL: `current_period_end desc nulls first`, then `updated_at desc`. */
export function compareByPeriodAndUpdate(
  a: { current_period_end: string | null; updated_at: string | null },
  b: { current_period_end: string | null; updated_at: string | null },
): number {
  if (a.current_period_end !== b.current_period_end) {
    if (a.current_period_end === null) return -1;
    if (b.current_period_end === null) return 1;
    return a.current_period_end < b.current_period_end ? 1 : -1;
  }
  if (a.updated_at === b.updated_at) return 0;
  if (a.updated_at === null) return -1;
  if (b.updated_at === null) return 1;
  return a.updated_at < b.updated_at ? 1 : -1;
}

/** Port of `internal.resolve_user_entitlement`. */
export async function resolveUserEntitlement(
  ctx: ReaderCtx,
  userId: string,
  now: string = nowIso(),
): Promise<ResolvedEntitlement> {
  const rows = (await listUserEntitlements(ctx, userId, now)).map((row) => ({
    row,
    grants: grantsAccess(row, now),
  }));
  rows.sort((a, b) => {
    if (a.grants !== b.grants) return a.grants ? -1 : 1;
    const rank = statusRank(a.row.status) - statusRank(b.row.status);
    if (rank !== 0) return rank;
    return compareByPeriodAndUpdate(a.row, b.row);
  });
  const best = rows[0]?.row;
  const product = best?.product_id ? await getByUuid(ctx, "subscription_products", best.product_id) : null;
  return {
    user_id: userId,
    is_entitled: rows.some((item) => item.grants),
    source: best?.source ?? null,
    status: best?.status ?? null,
    product_id: best?.product_id ?? null,
    billing_period: product?.billing_period ?? null,
    current_period_end: best?.current_period_end ?? null,
    updated_at: best?.updated_at ?? null,
  };
}

/** Port of `internal.user_has_direct_entitlement`. */
export async function userHasDirectEntitlement(ctx: ReaderCtx, userId: string): Promise<boolean> {
  return (await resolveUserEntitlement(ctx, userId)).is_entitled;
}
