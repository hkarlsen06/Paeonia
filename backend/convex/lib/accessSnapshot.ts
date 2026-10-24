import type { QueryCtx } from "../_generated/server";
import {
  type CoupleEntitlement,
  type ResolvedEntitlement,
  resolveCurrentCoupleEntitlement,
  resolveUserEntitlement,
} from "./access";
import { isCurrentUserBanned, requireUserId } from "./auth";
import { getCurrentRelationshipState } from "./relationshipState";

/**
 * The row `access:get_access_snapshot` returns and `identity:launch` embeds. A
 * banned account gets `account_status: "banned"` and nothing else, so the app
 * shows the closed-account screen. Everyone else needs a signed-in, active user.
 */
export async function readAccessSnapshot(ctx: QueryCtx) {
  if (await isCurrentUserBanned(ctx)) {
    return { account_status: "banned", user_entitlement: null, couple_entitlement: null, relationship_state: null };
  }
  const userId = await requireUserId(ctx);
  const own = await resolveUserEntitlement(ctx, userId);
  return {
    account_status: "active",
    user_entitlement: own,
    couple_entitlement: forViewer(await resolveCurrentCoupleEntitlement(ctx, userId), own),
    relationship_state: await getCurrentRelationshipState(ctx, userId),
  };
}

/**
 * A failed payment is the payer's to fix, so only the payer learns of it. Their own
 * `user_entitlement` says `grace`, and a partner whose own payment is fine sees the couple's
 * access as plain `active`.
 */
function forViewer(couple: CoupleEntitlement | null, own: ResolvedEntitlement): CoupleEntitlement | null {
  if (couple?.status !== "grace" || couple.covering_user_id === own.user_id || own.status === "grace") return couple;
  return { ...couple, status: "active" };
}
