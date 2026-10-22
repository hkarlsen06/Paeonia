import type { QueryCtx } from "../_generated/server";
import { resolveCurrentCoupleEntitlement, resolveUserEntitlement } from "./access";
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
  return {
    account_status: "active",
    user_entitlement: await resolveUserEntitlement(ctx, userId),
    couple_entitlement: await resolveCurrentCoupleEntitlement(ctx, userId),
    relationship_state: await getCurrentRelationshipState(ctx, userId),
  };
}
