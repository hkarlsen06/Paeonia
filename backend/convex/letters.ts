import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getByUuid, type ReaderCtx, type WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { optionalTimestampArg, optionalUuidArg, uuidArg } from "./lib/ids";
import {
  deliverAtFor,
  LETTER_DELIVERY_KINDS,
  LETTER_TEMPLATE_KEYS,
  MAX_LETTER_BODY_CODE_POINTS,
  MAX_LETTER_WAIT_MS,
  nextLetterState,
  type LetterDelivery,
  type LetterTemplateKey,
} from "./lib/letters";
import { isUsableMediaAsset } from "./lib/mediaAssetState";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { enqueueLetterNotification } from "./lib/notifications";
import { consumeRateLimit } from "./lib/rateLimits";
import { resolveMemberStreakTimeZone } from "./lib/streakDeadlines";
import { charLength } from "./lib/text";
import { nowIso } from "./lib/time";

/**
 * The letter as `viewerId` may see it, or null when they may not see it at all. The author sees
 * every letter they wrote. The recipient never sees a sealed letter, and sees a delivered one
 * without its words and image until they open it.
 */
function letterForViewer(row: Doc<"letters">, viewerId: string) {
  if (row.deleted_at !== undefined) return null;
  const isAuthor = row.author_user_id === viewerId;
  if (!isAuthor && (row.recipient_user_id !== viewerId || row.state === "sealed" || row.moderation_status !== "visible")) {
    return null;
  }
  const showsContent = isAuthor || row.state === "opened";
  return {
    id: row.id,
    author_user_id: row.author_user_id,
    recipient_user_id: row.recipient_user_id,
    template_key: row.template_key,
    body: showsContent ? row.body : null,
    media_asset_id: showsContent ? row.media_asset_id ?? null : null,
    delivery_kind: isAuthor ? row.delivery_kind : null,
    deliver_at: isAuthor ? row.deliver_at ?? null : null,
    state: row.state,
    delivered_at: row.delivered_at ?? null,
    opened_at: row.opened_at ?? null,
    created_at: row.created_at,
  };
}

async function partnerOf(ctx: ReaderCtx, coupleId: string, userId: string): Promise<string | null> {
  const members = await listActiveMembers(ctx, coupleId);
  return members.find((member) => member.user_id !== userId)?.user_id ?? null;
}

/**
 * The letters the caller wrote and the delivered letters they received, newest first, and the time
 * zone their partner's morning letters follow, so the composer can show when one arrives. Reads no
 * clock: a letter appears for the recipient when `deliver_letter` writes it. Fails with `42501`
 * without an entitled couple.
 */
export const get_letters = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = await partnerOf(ctx, coupleId, userId);
    const rows = await ctx.db
      .query("letters")
      .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", coupleId))
      .order("desc")
      .collect();
    return {
      couple_id: coupleId,
      partner_time_zone_id: partnerId === null ? null : await resolveMemberStreakTimeZone(ctx, partnerId),
      letters: rows.flatMap((row) => letterForViewer(row, userId) ?? []),
    };
  },
});

function parseTemplateKey(value: string): LetterTemplateKey {
  return LETTER_TEMPLATE_KEYS.find((key) => key === value) ?? fail("23514", "letter template is not supported");
}

function parseDelivery(kind: string, deliverAt: string | null | undefined, nowMs: number): LetterDelivery {
  switch (LETTER_DELIVERY_KINDS.find((known) => known === kind)) {
    case "now":
      return { kind: "now" };
    case "morning":
      return { kind: "morning" };
    case "at": {
      const at = optionalTimestampArg(deliverAt) ?? fail("23514", "a letter for a set time needs the time");
      if (Date.parse(at) > nowMs + MAX_LETTER_WAIT_MS) fail("23514", "a letter can wait at most a year");
      return { kind: "at", at };
    }
    default:
      return fail("23514", "letter delivery is not supported");
  }
}

/** Delivers a sealed letter that still exists, and tells the recipient. Anything else changes nothing. */
async function deliverLetter(ctx: WriterCtx, letter: Doc<"letters">): Promise<void> {
  const state = letter.deleted_at === undefined ? nextLetterState(letter.state, "deliver") : null;
  if (state === null) return;
  const delivered = { ...letter, state, delivered_at: nowIso() };
  await ctx.db.patch(letter._id, { state, delivered_at: delivered.delivered_at });
  await enqueueLetterNotification(ctx, delivered, "letter_arrived");
}

/**
 * Sends the letter `p_letter_id` to the caller's partner. The phone picks the id, so a send and
 * its retries are the same write. `p_delivery_kind` is `now`, `at` (with `p_deliver_at`, at most a
 * year ahead) or `morning` (the partner's next 08:00). The letter stays sealed until then, and
 * `deliver_letter` runs at that time. The optional image is a `letter_image` upload reserved for
 * this letter. Returns the letter as its author sees it now, or null when the author deleted it since.
 */
export const send_letter = mutation({
  args: {
    p_letter_id: v.string(),
    p_template_key: v.string(),
    p_body: v.string(),
    p_media_asset_id: v.optional(v.union(v.null(), v.string())),
    p_delivery_kind: v.string(),
    p_deliver_at: v.optional(v.union(v.null(), v.string())),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const letterId = uuidArg(args.p_letter_id);
    const assetId = optionalUuidArg(args.p_media_asset_id);
    const templateKey = parseTemplateKey(args.p_template_key);
    const body = args.p_body.trim();
    if (body === "" || charLength(body) > MAX_LETTER_BODY_CODE_POINTS) {
      fail("23514", `letter must have between 1 and ${MAX_LETTER_BODY_CODE_POINTS} characters`);
    }
    const nowMs = Date.now();
    const delivery = parseDelivery(args.p_delivery_kind, args.p_deliver_at, nowMs);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "send_letter",
      scope: `letter:${letterId}`,
      request: {
        kind: "send_letter",
        couple_id: coupleId,
        id: letterId,
        template_key: templateKey,
        body,
        media_asset_id: assetId ?? null,
        delivery,
      },
    });
    await runClientOperation(ctx, userId, input, async () => {
      await consumeRateLimit(ctx, "letterSend", userId);
      await assertNoPendingAccountDeletion(ctx, userId);

      const existing = await getByUuid(ctx, "letters", letterId);
      if (existing) {
        if (existing.couple_id !== coupleId || existing.author_user_id !== userId) {
          return fail("42501", "letter belongs to someone else");
        }
        return null;
      }
      const recipientId = (await partnerOf(ctx, coupleId, userId)) ?? fail("42501", "a letter needs a partner to receive it");

      if (assetId !== undefined) {
        const asset = await getByUuid(ctx, "media_assets", assetId);
        if (!asset || asset.owner_user_id !== userId || asset.couple_id !== coupleId) {
          return fail("42501", "letter image is not available");
        }
        if (
          asset.upload_purpose !== "letter_image" ||
          asset.media_type !== "image" ||
          asset.reserved_parent_kind !== "letter" ||
          asset.reserved_parent_id !== letterId ||
          !isUsableMediaAsset(asset)
        ) {
          return fail("23514", "letter image is not usable");
        }
      }

      const deliverAt = deliverAtFor(delivery, nowMs, await resolveMemberStreakTimeZone(ctx, recipientId));
      const docId = await ctx.db.insert("letters", {
        id: letterId,
        couple_id: coupleId,
        author_user_id: userId,
        recipient_user_id: recipientId,
        template_key: templateKey,
        body,
        media_asset_id: assetId,
        delivery_kind: delivery.kind,
        deliver_at: deliverAt,
        state: "sealed",
        moderation_status: "visible",
        created_at: nowIso(),
      });
      if (Date.parse(deliverAt) <= nowMs) {
        await deliverLetter(ctx, (await ctx.db.get(docId))!);
      } else {
        await ctx.scheduler.runAt(Date.parse(deliverAt), internal.letters.deliver_letter, { letter_id: letterId });
      }
      return null;
    });
    // Read after the operation, so a replay returns the letter as it is now.
    const letter = await getByUuid(ctx, "letters", letterId);
    return letter && letter.couple_id === coupleId ? letterForViewer(letter, userId) : null;
  },
});

/**
 * Delivers the letter `letter_id` at its time. Runs from the scheduler that `send_letter` set. A
 * letter that was deleted, or already delivered, stays as it is, so a second run writes nothing.
 */
export const deliver_letter = internalMutation({
  args: { letter_id: v.string() },
  handler: async (ctx, args) => {
    const letter = await getByUuid(ctx, "letters", args.letter_id);
    if (letter) await deliverLetter(ctx, letter);
    return null;
  },
});

/**
 * Opens the letter `p_letter_id` that the caller received, and tells its author. Opening it again
 * changes nothing. Returns the whole letter. A sealed, deleted, hidden or someone else's letter
 * fails with `42501`, the same as a missing one.
 */
export const open_letter = mutation({
  args: { p_letter_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const letterId = uuidArg(args.p_letter_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const letter = await getByUuid(ctx, "letters", letterId);
    if (!letter || letter.couple_id !== coupleId || letter.recipient_user_id !== userId ||
        letterForViewer(letter, userId) === null) {
      return fail("42501", "letter is not available");
    }
    const state = nextLetterState(letter.state, "open");
    if (state === null) return letterForViewer(letter, userId);
    const opened = { ...letter, state, opened_at: nowIso() };
    await ctx.db.patch(letter._id, { state, opened_at: opened.opened_at });
    await enqueueLetterNotification(ctx, opened, "letter_opened");
    return letterForViewer(opened, userId);
  },
});

/**
 * Deletes the letter `p_letter_id` for both partners. Only its author may. A sealed letter is
 * unsent, so it never arrives. Its image is queued for deletion. A missing or already deleted one is fine.
 */
export const delete_letter = mutation({
  args: { p_letter_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const letterId = uuidArg(args.p_letter_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "delete_letter",
      scope: `letter:${letterId}`,
      request: { kind: "delete_letter", couple_id: coupleId, id: letterId },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "letters", letterId);
      if (!existing || existing.deleted_at !== undefined) return null;
      if (existing.couple_id !== coupleId || existing.author_user_id !== userId) {
        return fail("42501", "only the author can delete a letter");
      }
      await ctx.db.patch(existing._id, { deleted_at: nowIso() });
      await queueOrphanedMediaAssetForDelete(ctx, existing.media_asset_id);
      return null;
    });
    return null;
  },
});
