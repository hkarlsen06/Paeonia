import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";
import { fail } from "./errors";

/**
 * The one place that decides what a person is called on someone else's screen or push.
 *
 * Each member of a couple can set a nickname for their partner (`couple_members.partner_nickname`).
 * It is private. Only the member who set it reads it, and the partner never sees it.
 *
 * Every function that puts a partner's name into copy, an API field or a push calls
 * `nameForViewer`. Reading `profiles.display_name` anywhere else shows the partner's own name to
 * someone who chose another one. `partnerNames.test.ts` fails when a file outside its allow list
 * reads `display_name`.
 */

/** Longest nickname, counted in Unicode code points. "Ellie 🌸" is 7. */
export const PARTNER_NICKNAME_MAX_LENGTH = 30;

/**
 * The nickname to store: trimmed, with every run of whitespace collapsed to one space. Null, an
 * empty string and a string of only whitespace all mean "no nickname" and return null. Fails with
 * `23514` when it is too long or holds control characters.
 */
export function normalizePartnerNickname(raw: string | null | undefined): string | null {
  const collapsed = (raw ?? "").replace(/\s+/gu, " ").trim();
  if (collapsed === "") return null;
  if (Array.from(collapsed).length > PARTNER_NICKNAME_MAX_LENGTH) {
    return fail("23514", `nickname must be at most ${PARTNER_NICKNAME_MAX_LENGTH} characters`);
  }
  if (/\p{Cc}/u.test(collapsed)) {
    return fail("23514", "nickname must not contain control characters");
  }
  return collapsed;
}

/** The trimmed account name on a profile (what the person chose for themselves), or null. */
export function accountNameOf(profile: Pick<Doc<"profiles">, "display_name"> | null | undefined): string | null {
  const name = profile?.display_name?.trim();
  return name ? name : null;
}

/**
 * The nickname `viewerUserId` gave `subjectUserId`, or null. It applies only while both are active
 * members of the same active couple, so a nickname never follows a person into another relationship.
 */
export async function nicknameForViewer(
  ctx: ReaderCtx,
  viewerUserId: string,
  subjectUserId: string,
): Promise<string | null> {
  if (viewerUserId === subjectUserId) return null;
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", viewerUserId).eq("status", "active"))
    .collect();
  for (const membership of memberships) {
    const nickname = membership.partner_nickname?.trim();
    if (!nickname) continue;
    const couple = await ctx.db
      .query("couples")
      .withIndex("by_uuid", (q) => q.eq("id", membership.couple_id))
      .unique();
    if (couple?.status !== "active") continue;
    const subject = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", membership.couple_id).eq("user_id", subjectUserId))
      .unique();
    if (subject?.status === "active") return nickname;
  }
  return null;
}

/**
 * `nameForViewer` plus whether the name is the viewer's nickname. A widget cuts an account name to
 * its first word but shows a nickname whole, so it needs to know which one it got.
 */
export async function nameAndSourceForViewer(
  ctx: ReaderCtx,
  viewerUserId: string,
  subjectUserId: string,
): Promise<{ name: string | null; usesNickname: boolean }> {
  const nickname = await nicknameForViewer(ctx, viewerUserId, subjectUserId);
  if (nickname) return { name: nickname, usesNickname: true };
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", subjectUserId))
    .unique();
  return { name: accountNameOf(profile), usesNickname: false };
}

/**
 * What `viewerUserId` calls `subjectUserId`: the nickname when the viewer set one, otherwise the
 * subject's own account name. Null when neither exists, so the caller picks its generic wording
 * ("Your partner").
 */
export async function nameForViewer(
  ctx: ReaderCtx,
  viewerUserId: string,
  subjectUserId: string,
): Promise<string | null> {
  return (await nameAndSourceForViewer(ctx, viewerUserId, subjectUserId)).name;
}
