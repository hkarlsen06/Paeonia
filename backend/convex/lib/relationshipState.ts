import type { Doc } from "../_generated/dataModel";
import { getByUuid, orNull, type ReaderCtx } from "./db";

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

  const others = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", best.couple.id))
    .collect();
  const partner = others.find((member) => member.user_id !== userId);
  const profile = partner
    ? await ctx.db
        .query("profiles")
        .withIndex("by_user_id", (q) => q.eq("user_id", partner.user_id))
        .unique()
    : null;
  const visible = profile?.moderation_status === "visible";
  return {
    couple_id: best.couple.id,
    pair_id: best.couple.pair_id,
    relationship_status: best.couple.status,
    member_status: best.member.status,
    partner_user_id: partner?.user_id ?? null,
    partner_display_name: visible ? orNull(profile?.display_name) : null,
    partner_profile_photo_asset_id: visible
      ? orNull(profile?.profile_photo_asset_id ?? profile?.provider_profile_photo_asset_id)
      : null,
    started_on: orNull(best.couple.started_on),
    ended_at: orNull(best.couple.ended_at),
    delete_after: orNull(best.couple.delete_after),
    ended_notice_seen_at: orNull(best.member.ended_notice_seen_at),
  };
}
