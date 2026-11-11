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
import { optionalTimestampArg, optionalUuidArg, timestampArg, uuidArg } from "./lib/ids";
import {
  deliverAtFor,
  DUE_LETTER_PAGE,
  LETTER_DELIVERY_KINDS,
  LETTER_TEMPLATE_KEYS,
  MAILBOX_FIRST_PAGE,
  MAX_LETTER_WAIT_MS,
  MAX_OLDER_PAGE,
  MAX_WAITING_LETTERS,
  nextLetterState,
  parseLetterBody,
  type LetterDelivery,
  type LetterTemplateKey,
} from "./lib/letters";
import { isUsableMediaAsset } from "./lib/mediaAssetState";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { enqueueLetterNotification } from "./lib/notifications";
import { consumeRateLimit } from "./lib/rateLimits";
import { resolveMemberStreakTimeZone } from "./lib/streakDeadlines";
import { nowIso } from "./lib/time";

/**
 * The letter as `viewerId` may see it, or null when they may not see it at all. The author sees
 * every letter they wrote. The recipient never sees a sealed letter, and sees a delivered one
 * only as arrived, without its words, card, image or written time, until they open it.
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
    template_key: showsContent ? row.template_key : null,
    body: showsContent ? row.body : null,
    media_asset_id: showsContent ? row.media_asset_id ?? null : null,
    delivery_kind: isAuthor ? row.delivery_kind : null,
    deliver_at: isAuthor ? row.deliver_at ?? null : null,
    state: row.state,
    delivered_at: row.delivered_at ?? null,
    opened_at: row.opened_at ?? null,
    created_at: showsContent ? row.created_at : null,
  };
}

async function partnerOf(ctx: ReaderCtx, coupleId: string, userId: string): Promise<string | null> {
  const members = await listActiveMembers(ctx, coupleId);
  return members.find((member) => member.user_id !== userId)?.user_id ?? null;
}

/** True while the couple is active and both of the letter's people are still in it. */
async function bothStillTogether(ctx: ReaderCtx, letter: Doc<"letters">): Promise<boolean> {
  const members = await listActiveMembers(ctx, letter.couple_id);
  return [letter.author_user_id, letter.recipient_user_id].every((userId) =>
    members.some((member) => member.user_id === userId));
}

type MailboxList = "received" | "sent";
type LetterCursor = { at: string; id: string };

/**
 * One page of a mailbox list, newest first. The received list is in the order the letters
 * arrived, and holds only delivered and opened letters. The sent list is in the order they were
 * written. `before` is the last letter of the page before. `next_before` is null on the last page.
 */
async function letterPage(
  ctx: ReaderCtx,
  coupleId: string,
  userId: string,
  list: MailboxList,
  before: LetterCursor | null,
  limit: number,
) {
  const rows = list === "received"
    ? ctx.db.query("letters").withIndex("by_couple_id_recipient_user_id_deleted_at_delivered_at_id", (q) => {
      const live = q.eq("couple_id", coupleId).eq("recipient_user_id", userId).eq("deleted_at", undefined);
      return before === null ? live.gte("delivered_at", "") : live.gte("delivered_at", "").lte("delivered_at", before.at);
    })
    : ctx.db.query("letters").withIndex("by_couple_id_author_user_id_deleted_at_created_at_id", (q) => {
      const live = q.eq("couple_id", coupleId).eq("author_user_id", userId).eq("deleted_at", undefined);
      return before === null ? live : live.lte("created_at", before.at);
    });
  const page: Doc<"letters">[] = [];
  let hasMore = false;
  for await (const row of rows.order("desc")) {
    const at = (list === "received" ? row.delivered_at : row.created_at) ?? "";
    // Letters that share the cursor's millisecond sort by id, so skip the ones already sent.
    if (before !== null && at === before.at && row.id >= before.id) continue;
    if (page.length === limit) {
      hasMore = true;
      break;
    }
    page.push(row);
  }
  const last = page.at(-1);
  return {
    letters: page.flatMap((row) => letterForViewer(row, userId) ?? []),
    next_before: hasMore && last
      ? { at: (list === "received" ? last.delivered_at : last.created_at) ?? "", id: last.id }
      : null,
  };
}

/**
 * The caller's Mail for the Us tab card, the badge and the top of the mailbox. It holds the
 * letters that arrived and wait to be opened (oldest first, at most 50), and the newest page of
 * the received and the sent list. `get_older_letters` reads further back. It reads no clock and no
 * device. A letter appears for the recipient when it is delivered, and a sealed letter is outside
 * every range the recipient reads. Fails with `42501` without an entitled couple.
 */
export const get_letters = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const waiting = await ctx.db
      .query("letters")
      .withIndex("by_couple_id_recipient_user_id_deleted_at_state_delivered_at", (q) =>
        q.eq("couple_id", coupleId).eq("recipient_user_id", userId).eq("deleted_at", undefined).eq("state", "delivered"))
      .take(MAX_WAITING_LETTERS);
    return {
      waiting: waiting.flatMap((row) => letterForViewer(row, userId) ?? []),
      received: await letterPage(ctx, coupleId, userId, "received", null, MAILBOX_FIRST_PAGE),
      sent: await letterPage(ctx, coupleId, userId, "sent", null, MAILBOX_FIRST_PAGE),
    };
  },
});

/**
 * The page of the `p_list` mailbox list (`received` or `sent`) after the letter at `p_before_at`
 * with id `p_before_id`, as `next_before` of the page before gave them. At most 50 letters, in the
 * shape of a `get_letters` list. Fails with `42501` without an entitled couple.
 */
export const get_older_letters = query({
  args: { p_list: v.string(), p_before_at: v.string(), p_before_id: v.string(), p_limit: v.number() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    if (args.p_list !== "received" && args.p_list !== "sent") return fail("23514", "mailbox list is not supported");
    if (!Number.isFinite(args.p_limit) || args.p_limit < 1) return fail("23514", "limit must be 1 or more");
    const before = { at: timestampArg(args.p_before_at), id: uuidArg(args.p_before_id) };
    return await letterPage(ctx, coupleId, userId, args.p_list, before, Math.min(Math.floor(args.p_limit), MAX_OLDER_PAGE));
  },
});

/**
 * The time zone the partner's morning letters follow, so the composer can show when one arrives.
 * The app reads it once, and `send_letter` works the time out again when the letter goes. Null
 * without a partner. Fails with `42501` without an entitled couple.
 */
export const get_letter_partner_time_zone = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = await partnerOf(ctx, coupleId, userId);
    return { partner_time_zone_id: partnerId === null ? null : await resolveMemberStreakTimeZone(ctx, partnerId) };
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

/**
 * Delivers a sealed letter that still exists while both partners are still together, and queues
 * the push in its own job, so a push that fails cannot undo the delivery. Anything else writes
 * nothing, so a second run, the sweep and the scheduled job together still deliver once.
 */
async function deliverLetter(ctx: WriterCtx, letter: Doc<"letters">): Promise<void> {
  const state = letter.deleted_at === undefined ? nextLetterState(letter.state, "deliver") : null;
  if (state === null || !(await bothStillTogether(ctx, letter))) return;
  await ctx.db.patch(letter._id, { state, delivered_at: nowIso() });
  await ctx.scheduler.runAfter(0, internal.letters.notify_letter_arrived, { letter_id: letter.id });
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
    const body = parseLetterBody(args.p_body);
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
 * letter that was deleted, already delivered, or whose couple ended stays as it is.
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
 * The `deliver-due-letters` sweep. Delivers every sealed letter whose time has come, in pages, so
 * a letter arrives even when its scheduled `deliver_letter` was lost. A restore from a backup
 * carries no scheduled jobs, a renamed function leaves its old jobs pointing nowhere, and a failed
 * job is not retried. A letter waiting for a couple that ended stays in the range and writes
 * nothing until the relationship cleanup deletes it.
 */
export const deliver_due_letters = internalMutation({
  args: {
    p_now: v.optional(v.union(v.null(), v.string())),
    cursor: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const page = await ctx.db
      .query("letters")
      .withIndex("by_state_deleted_at_deliver_at", (q) =>
        q.eq("state", "sealed").eq("deleted_at", undefined).gte("deliver_at", "").lte("deliver_at", now))
      .paginate({ numItems: DUE_LETTER_PAGE, cursor: args.cursor ?? null });
    for (const letter of page.page) await deliverLetter(ctx, letter);
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.letters.deliver_due_letters, { p_now: now, cursor: page.continueCursor });
    }
    return null;
  },
});

/** Tells the recipient that the letter `letter_id` arrived, unless it was deleted or the couple ended since. */
export const notify_letter_arrived = internalMutation({
  args: { letter_id: v.string() },
  handler: async (ctx, args) => {
    const letter = await getByUuid(ctx, "letters", args.letter_id);
    if (!letter || letter.deleted_at !== undefined || letter.state !== "delivered" || !(await bothStillTogether(ctx, letter))) {
      return null;
    }
    await enqueueLetterNotification(ctx, letter, "letter_arrived");
    return null;
  },
});

/**
 * Opens the letter `p_letter_id` that the caller received, and tells its author. Opening it again
 * changes nothing. Returns the whole letter. A letter its author deleted fails with `P0002`. A
 * sealed, hidden or someone else's letter fails with `42501`.
 */
export const open_letter = mutation({
  args: { p_letter_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const letterId = uuidArg(args.p_letter_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const letter = await getByUuid(ctx, "letters", letterId);
    if (letter && (letter.couple_id !== coupleId || letter.recipient_user_id !== userId)) {
      return fail("42501", "letter is not available");
    }
    if (!letter || letter.deleted_at !== undefined) return fail("P0002", "letter was deleted");
    if (letterForViewer(letter, userId) === null) return fail("42501", "letter is not available");
    const state = nextLetterState(letter.state, "open");
    if (state === null) return letterForViewer(letter, userId);
    const opened = { ...letter, state, opened_at: nowIso() };
    await ctx.db.patch(letter._id, { state, opened_at: opened.opened_at });
    await enqueueLetterNotification(ctx, opened, "letter_opened");
    return letterForViewer(opened, userId);
  },
});

/**
 * Deletes the letter `p_letter_id` for both partners. Only its author may, and someone else's
 * letter fails with `42501` even when it is already deleted. A sealed letter is unsent, so it never
 * arrives. Its image is queued for deletion. A missing or already deleted letter of the caller's is fine.
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
      if (existing && (existing.couple_id !== coupleId || existing.author_user_id !== userId)) {
        return fail("42501", "only the author can delete a letter");
      }
      if (!existing || existing.deleted_at !== undefined) return null;
      await ctx.db.patch(existing._id, { deleted_at: nowIso() });
      await queueOrphanedMediaAssetForDelete(ctx, existing.media_asset_id);
      return null;
    });
    return null;
  },
});
