import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { getByUuid, withUpdatedAt } from "./lib/db";
import { revokeEntitlementGrant } from "./lib/entitlements";
import { fail } from "./lib/errors";
import { newUuid, optionalTimestampArg, optionalUuidArg, uuidArg } from "./lib/ids";
import { nowIso } from "./lib/time";
import { grantKind } from "./lib/validators";

function requiredText(value: string, name: string): string {
  const text = value.trim();
  return text.length > 0 ? text : fail("23514", `entitlement grant needs ${name}`);
}

/**
 * Gives a user access without a purchase. Only a lifetime grant may run without an end,
 * because `grantsAccess` counts a review, test or beta grant only before its `expires_at`.
 * A user has at most one live grant per kind and product: when one exists, this returns it
 * unchanged with `created: false`, so a script can run it again. To change a live grant's
 * end, revoke it and create a new one.
 */
export const create_entitlement_grant = internalMutation({
  args: {
    p_user_id: v.string(),
    p_grant_kind: grantKind,
    p_product_id: v.optional(v.string()),
    p_reason: v.string(),
    p_granted_by: v.string(),
    p_expires_at: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = uuidArg(args.p_user_id);
    const productId = optionalUuidArg(args.p_product_id);
    const reason = requiredText(args.p_reason, "a reason");
    const grantedBy = requiredText(args.p_granted_by, "granted_by");
    const expiresAt = optionalTimestampArg(args.p_expires_at);
    const now = nowIso();
    if (expiresAt === undefined && args.p_grant_kind !== "lifetime") {
      return fail("23514", `a ${args.p_grant_kind} grant needs expires_at`);
    }
    if (expiresAt !== undefined && expiresAt <= now) {
      return fail("23514", "expires_at must be in the future");
    }
    if (!(await getByUuid(ctx, "users", userId))) {
      return fail("23503", `user ${userId} does not exist`);
    }
    if (productId !== undefined && !(await getByUuid(ctx, "subscription_products", productId))) {
      return fail("23503", `subscription product ${productId} does not exist`);
    }

    const active = await ctx.db
      .query("entitlement_grants")
      .withIndex("by_user_id_grant_kind_product_id", (q) =>
        q.eq("user_id", userId).eq("grant_kind", args.p_grant_kind).eq("product_id", productId),
      )
      .filter((q) => q.eq(q.field("status"), "active"))
      .collect();
    for (const grant of active) {
      if (grant.expires_at === undefined || grant.expires_at > now) {
        return { grant_id: grant.id, created: false, expires_at: grant.expires_at ?? null };
      }
      // Ran out, and the expiry cron has not marked it yet.
      await ctx.db.patch(grant._id, withUpdatedAt({ status: "expired" as const }));
    }

    const id = newUuid();
    await ctx.db.insert("entitlement_grants", {
      id,
      user_id: userId,
      product_id: productId,
      grant_kind: args.p_grant_kind,
      status: "active",
      scope: "user",
      reason,
      granted_by: grantedBy,
      granted_at: now,
      expires_at: expiresAt,
      created_at: now,
      updated_at: now,
    });
    return { grant_id: id, created: true, expires_at: expiresAt ?? null };
  },
});

/** Ends a grant's access now. Revoking a grant again changes nothing and returns `changed: false`. */
export const revoke_entitlement_grant = internalMutation({
  args: { p_grant_id: v.string(), p_reason: v.string() },
  handler: async (ctx, args) => {
    const grantId = uuidArg(args.p_grant_id);
    const reason = requiredText(args.p_reason, "a reason");
    const grant = await getByUuid(ctx, "entitlement_grants", grantId);
    if (!grant) {
      return fail("P0002", `entitlement grant ${grantId} does not exist`);
    }
    return { changed: await revokeEntitlementGrant(ctx, grant, reason) };
  },
});
