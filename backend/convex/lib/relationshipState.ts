import type { Doc } from "../_generated/dataModel";
import { pairPartnerOf } from "./access";
import { getByUuid, type ReaderCtx } from "./db";
import { accountNameOf } from "./partnerNames";

/** Port of `internal.get_current_relationship_state`. Returns the one row it returned, or null. */
export async function getCurrentRelationshipState(ctx: ReaderCtx, userId: string) {
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId))
    .collect();

  const candidates: { member: Doc<"couple_members">; couple: Doc<"couples">; current: boolean }[] = [];
  for (const member of memberships) {
    const couple = await getByUuid(ctx, "couples", member.couple_id);
    if (!couple) continue;
    const current = couple.status === "active" && member.status === "active";
    const ended =
      couple.status === "ended" &&
      (member.status === "ended_notice_pending" || member.status === "ended_notice_seen" || member.status === "left");
    if (current || ended) candidates.push({ member, couple, current });
  }
  candidates.sort((a, b) => {
    if (a.current !== b.current) return a.current ? -1 : 1;
    return a.couple.created_at < b.couple.created_at ? 1 : a.couple.created_at > b.couple.created_at ? -1 : 0;
  });
  const best = candidates[0];
  if (!best) return null;

  // From the pair, because the partner's own member row goes when they delete their account.
  const partnerUserId = pairPartnerOf(await getByUuid(ctx, "relationship_pairs", best.couple.pair_id), userId);
  const profile = partnerUserId
    ? await ctx.db
        .query("profiles")
        .withIndex("by_user_id", (q) => q.eq("user_id", partnerUserId))
        .unique()
    : null;
  const visible = profile?.moderation_status === "visible";
  const ownProfile = await ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", userId)).unique();
  return {
    couple_id: best.couple.id,
    pair_id: best.couple.pair_id,
    relationship_status: best.couple.status,
    member_status: best.member.status,
    // This person joined with the partner's invite code.
    accepted_invite: best.member.role === "partner",
    partner_user_id: partnerUserId,
    // The partner's own name and the viewer's nickname for them travel separately. The app joins them
    // in `PartnerName`, so the settings screen can show both. Push copy uses `nameForViewer`.
    partner_account_name: visible ? accountNameOf(profile) : null,
    partner_nickname: visible && best.current ? (best.member.partner_nickname ?? null) : null,
    own_avatar_decoration: ownProfile?.avatar_decoration ?? null,
    partner_avatar_decoration: visible && best.current ? (profile?.avatar_decoration ?? null) : null,
    partner_profile_photo_asset_id: visible
      ? profile?.profile_photo_asset_id ?? profile?.provider_profile_photo_asset_id ?? null
      : null,
    started_on: best.couple.started_on ?? null,
    ended_at: best.couple.ended_at ?? null,
    delete_after: best.couple.delete_after ?? null,
    ended_notice_seen_at: best.member.ended_notice_seen_at ?? null,
    first_day_finished_at: best.member.first_day_finished_at ?? null,
    reunion_celebration_due_at: best.current ? (best.member.reunion_celebration_due_at ?? null) : null,
  };
}
