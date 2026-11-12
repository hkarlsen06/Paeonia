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
import { sharesLocation } from "./lib/locationPause";
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
  VISIT_SWEEP_DAYS,
  visitLettersWrittenBefore,
  visitLetterTime,
  type LetterDelivery,
  type LetterTemplateKey,
} from "./lib/letters";
import { isUsableMediaAsset } from "./lib/mediaAssetState";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { enqueueLetterNotification } from "./lib/notifications";
import { consumeRateLimit } from "./lib/rateLimits";
import { resolveMemberStreakTimeZone } from "./lib/streakDeadlines";
import { addDaysToDate, nowIso } from "./lib/time";
import { isCoupleTogetherAt, todayOnStreakClock } from "./lib/together";
import { openVisits } from "./lib/visits";

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
  const page: NonNullable<ReturnType<typeof letterForViewer>>[] = [];
  let next_before: LetterCursor | null = null;
  for await (const row of rows.order("desc")) {
    const at = (list === "received" ? row.delivered_at : row.created_at) ?? "";
    // Letters that share the cursor's millisecond sort by id, so skip the ones already sent.
    if (before !== null && at === before.at && row.id >= before.id) continue;
    // The cursor names the last letter on the page, so a letter hidden from the reader never reaches it.
    const letter = letterForViewer(row, userId);
    if (letter === null) continue;
    if (page.length === limit) {
      const last = page[limit - 1];
      next_before = { at: (list === "received" ? last.delivered_at : last.created_at) ?? "", id: last.id };
      break;
    }
    page.push(letter);
  }
  return { letters: page, next_before };
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
 * How a letter for the next meeting to `recipientId`, written at `now`, could arrive. The next
 * visit is the first one that starts after today, and `next_visit_start_date` names it only when
 * its evening would bring the letter on (`visitLetterTime`). Otherwise `next_visit_too_soon` is
 * true. Sharing is read as the map reads it, so a partner's pause changes nothing here.
 */
async function meetingOptions(ctx: ReaderCtx, coupleId: string, recipientId: string | null, now: string) {
  const members = await listActiveMembers(ctx, coupleId);
  const today = await todayOnStreakClock(ctx, coupleId, now);
  const next = (await openVisits(ctx, coupleId, today))
    .filter((visit) => visit.start_date > today)
    .reduce<Doc<"visits"> | null>((first, visit) => (first === null || visit.start_date < first.start_date ? visit : first), null);
  const evening = next === null || recipientId === null
    ? null
    : visitLetterTime(next, await resolveMemberStreakTimeZone(ctx, recipientId));
  const counts = next !== null && evening !== null && now < evening;
  const sharing = await Promise.all(members.map((member) =>
    ctx.db
      .query("location_sharing_preferences")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", member.user_id))
      .unique()));
  return {
    together_now: await isCoupleTogetherAt(ctx, coupleId, now),
    next_visit_start_date: counts ? next.start_date : null,
    next_visit_too_soon: next !== null && !counts,
    both_share_location: members.length === 2 && sharing.every(sharesLocation),
  };
}

/** A letter for the next meeting can be sent while apart, with a visit ahead or both sharing location. */
const offersMeetingLetter = (options: Awaited<ReturnType<typeof meetingOptions>>) =>
  !options.together_now && (options.next_visit_start_date !== null || options.both_share_location);

/**
 * What the composer's delivery step needs at `p_now`, the phone's time, read once when it opens.
 * `partner_time_zone_id` is the zone the partner's morning letters follow, null without a
 * partner. `send_letter` works the time out again when the letter goes. `partner_birthday`
 * (`YYYY-MM-DD`) is the partner's birthday from Settings, which a birthday card is set to arrive
 * on, null when nobody saved it. `together_now`,
 * `next_visit_start_date`, `next_visit_too_soon` and `both_share_location` say whether a letter
 * for the next meeting can be sent (`offersMeetingLetter`) and how it would arrive
 * (`meetingOptions`). Fails with `42501` without an entitled couple.
 */
export const get_letter_delivery_options = query({
  args: { p_now: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const now = timestampArg(args.p_now);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partner = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId);
    return {
      partner_time_zone_id: partner === undefined ? null : await resolveMemberStreakTimeZone(ctx, partner.user_id),
      partner_birthday: partner?.birthday ?? null,
      ...(await meetingOptions(ctx, coupleId, partner?.user_id ?? null, now)),
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
    case "together":
      return { kind: "together" };
    case "at": {
      const at = optionalTimestampArg(deliverAt) ?? fail("23514", "a letter for a set time needs the time");
      if (Date.parse(at) > nowMs + MAX_LETTER_WAIT_MS) fail("23514", "a letter can wait at most a year");
      return { kind: "at", at };
    }
    default:
      return fail("23514", "letter delivery is not supported");
  }
}

/** Fails unless `assetId` is a usable `letter_image` upload of `userId`'s, reserved for the letter `letterId`. */
async function assertLetterImage(ctx: ReaderCtx, assetId: string, userId: string, coupleId: string, letterId: string) {
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

/**
 * Delivers a sealed letter that still exists while both partners are still together, and queues
 * the push in its own job, so a push that fails cannot undo the delivery. Anything else writes
 * nothing, so a second run, the sweep and the scheduled job together still deliver once. Returns
 * whether it delivered.
 */
async function deliverLetter(ctx: WriterCtx, letter: Doc<"letters">): Promise<boolean> {
  const state = letter.deleted_at === undefined ? nextLetterState(letter.state, "deliver") : null;
  if (state === null || !(await bothStillTogether(ctx, letter))) return false;
  await ctx.db.patch(letter._id, { state, delivered_at: nowIso() });
  await ctx.scheduler.runAfter(0, internal.letters.notify_letter_arrived, { letter_id: letter.id });
  return true;
}

/**
 * Delivers the letters `recipientId` gets at the couple's next meeting, a page at a time, or only
 * the ones that waited since before `writtenBefore` when it is set (`waits_since`). The caller decides that the partners met.
 * With no letter waiting this reads no document.
 */
export async function deliverMeetingLetters(
  ctx: WriterCtx,
  coupleId: string,
  recipientId: string,
  writtenBefore?: string,
): Promise<void> {
  const range = ctx.db
    .query("letters")
    .withIndex("by_couple_id_recipient_user_id_delivery_kind_state_deleted_at", (q) =>
      q.eq("couple_id", coupleId).eq("recipient_user_id", recipientId).eq("delivery_kind", "together")
        .eq("state", "sealed").eq("deleted_at", undefined));
  const waiting = await (writtenBefore === undefined
    ? range
    : range.filter((q) => q.lt(q.field("waits_since"), writtenBefore))).take(DUE_LETTER_PAGE);
  let delivered = 0;
  for (const letter of waiting) if (await deliverLetter(ctx, letter)) delivered += 1;
  // A delivered letter leaves the range, so a full page means more may wait.
  if (delivered === DUE_LETTER_PAGE) {
    await ctx.scheduler.runAfter(0, internal.letters.deliver_meeting_letters, {
      couple_id: coupleId,
      recipient_user_id: recipientId,
      ...(writtenBefore === undefined ? {} : { written_before: writtenBefore }),
    });
  }
}

/**
 * Delivers the letters for the next meeting that `visit` has brought on: for each partner who
 * has one waiting, the ones written before the visit's evening on that partner's clock as it is
 * now (`visitLetterTime`) and before its first day began everywhere (`visitLettersWrittenBefore`),
 * once that evening is no later than `now`. A visit whose first day was
 * set less than 20 hours before that evening brings nothing on, so the recipient alone cannot
 * bring a letter on without the author seeing the visit for that long. Reads a partner's devices
 * only when a letter waits for them.
 */
async function deliverVisitLetters(ctx: WriterCtx, visit: Doc<"visits">, now: string): Promise<void> {
  for (const member of await listActiveMembers(ctx, visit.couple_id)) {
    const waits = await ctx.db
      .query("letters")
      .withIndex("by_couple_id_recipient_user_id_delivery_kind_state_deleted_at", (q) =>
        q.eq("couple_id", visit.couple_id).eq("recipient_user_id", member.user_id).eq("delivery_kind", "together")
          .eq("state", "sealed").eq("deleted_at", undefined))
      .first();
    if (waits === null) continue;
    const at = visitLetterTime(visit, await resolveMemberStreakTimeZone(ctx, member.user_id));
    if (at !== null && at <= now) {
      await deliverMeetingLetters(ctx, visit.couple_id, member.user_id, visitLettersWrittenBefore(visit, at));
    }
  }
}

/**
 * Sends the letter `p_letter_id` to the caller's partner. The phone picks the id, so a send and
 * its retries are the same write. `p_delivery_kind` is `now`, `at` (with `p_deliver_at`, at most a
 * year ahead), `morning` (the partner's next 08:00) or `together` (the next meeting). The letter
 * stays sealed until then, and `deliver_letter` runs at that time. A letter for the next meeting
 * arrives when the caller's phone shows the partners together (`location.ts`), or at 20:00 on the
 * partner's clock on the first day of a planned visit (`sweep_letters_for_visits`). It fails with
 * `55000` when the composer would not offer it now (`offersMeetingLetter`). The optional image is a
 * `letter_image` upload reserved for this letter. Returns the letter as its author sees it now, or
 * null when the author deleted it since.
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
      if (delivery.kind === "together" && !offersMeetingLetter(await meetingOptions(ctx, coupleId, recipientId, new Date(nowMs).toISOString()))) {
        return fail("55000", "a letter for the next meeting needs a visit ahead or both sharing location, while apart");
      }

      if (assetId !== undefined) await assertLetterImage(ctx, assetId, userId, coupleId, letterId);

      const deliverAt = deliverAtFor(delivery, nowMs, await resolveMemberStreakTimeZone(ctx, recipientId));
      const sentAt = nowIso();
      const docId = await ctx.db.insert("letters", {
        id: letterId,
        couple_id: coupleId,
        author_user_id: userId,
        recipient_user_id: recipientId,
        template_key: templateKey,
        body,
        media_asset_id: assetId,
        delivery_kind: delivery.kind,
        deliver_at: deliverAt ?? undefined,
        waits_since: sentAt,
        state: "sealed",
        moderation_status: "visible",
        created_at: sentAt,
      });
      if (deliverAt === null) return null;
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
 * Delivers the letter `letter_id` at its time. Runs from the scheduler that `send_letter` or
 * `edit_letter` set. A letter that was deleted, already delivered, or whose couple ended stays as
 * it is, and so does one whose time an edit moved later, which the job for its new time delivers.
 */
export const deliver_letter = internalMutation({
  args: { letter_id: v.string() },
  handler: async (ctx, args) => {
    const letter = await getByUuid(ctx, "letters", args.letter_id);
    if (letter?.deliver_at !== undefined && Date.parse(letter.deliver_at) <= Date.now()) {
      await deliverLetter(ctx, letter);
    }
    return null;
  },
});

/** The next page of `deliverMeetingLetters`. */
export const deliver_meeting_letters = internalMutation({
  args: { couple_id: v.string(), recipient_user_id: v.string(), written_before: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await deliverMeetingLetters(ctx, args.couple_id, args.recipient_user_id, args.written_before);
    return null;
  },
});

/**
 * Changes the sealed letter `p_letter_id` that the caller wrote. It takes the card, the note, the
 * image and the delivery as `send_letter` does, and replaces all of them, so the last change saved
 * wins. The partner can tell nothing until the letter arrives: a sealed letter is outside every
 * range they read. A replaced or removed image is queued for deletion. Moving a letter to the next
 * meeting needs what `send_letter` needs (`55000` otherwise), and it then waits from now, so a visit
 * whose evening has passed does not bring it on. A change that keeps "in the morning" keeps the
 * morning it was set for, so it arrives at once when that morning came before its job ran. A letter that arrived fails with `40001`, a
 * deleted or missing one with `P0002`, and someone else's with `42501`. Returns the letter as its
 * author sees it now, also on a replay after it arrived.
 */
export const edit_letter = mutation({
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
      kind: "edit_letter",
      scope: `letter:${letterId}`,
      request: {
        kind: "edit_letter",
        couple_id: coupleId,
        id: letterId,
        template_key: templateKey,
        body,
        media_asset_id: assetId ?? null,
        delivery,
      },
    });
    await runClientOperation(ctx, userId, input, async () => {
      await consumeRateLimit(ctx, "letterEdit", userId);
      const letter = await getByUuid(ctx, "letters", letterId);
      if (letter && (letter.couple_id !== coupleId || letter.author_user_id !== userId)) {
        return fail("42501", "only the author can change a letter");
      }
      if (!letter || letter.deleted_at !== undefined) return fail("P0002", "letter was deleted");
      if (letter.state !== "sealed") return fail("40001", "letter already arrived");
      const startsWaiting = delivery.kind === "together" && letter.delivery_kind !== "together";
      const now = new Date(nowMs).toISOString();
      if (startsWaiting && !offersMeetingLetter(await meetingOptions(ctx, coupleId, letter.recipient_user_id, now))) {
        return fail("55000", "a letter for the next meeting needs a visit ahead or both sharing location, while apart");
      }
      if (assetId !== undefined && assetId !== letter.media_asset_id) {
        await assertLetterImage(ctx, assetId, userId, coupleId, letterId);
      }

      // A change that keeps "in the morning" keeps the morning it was set for, also once it came.
      const deliverAt = delivery.kind === "morning" && letter.delivery_kind === "morning" && letter.deliver_at
        ? letter.deliver_at
        : deliverAtFor(delivery, nowMs, await resolveMemberStreakTimeZone(ctx, letter.recipient_user_id));
      await ctx.db.patch(letter._id, {
        template_key: templateKey,
        body,
        media_asset_id: assetId,
        delivery_kind: delivery.kind,
        deliver_at: deliverAt ?? undefined,
        waits_since: startsWaiting ? now : letter.waits_since,
      });
      if (letter.media_asset_id !== assetId) await queueOrphanedMediaAssetForDelete(ctx, letter.media_asset_id);
      // A letter for the next meeting has no time. The meeting paths read only `together` letters.
      if (deliverAt === null) return null;
      if (Date.parse(deliverAt) <= nowMs) {
        await deliverLetter(ctx, (await ctx.db.get(letter._id))!);
      } else if (deliverAt !== letter.deliver_at) {
        await ctx.scheduler.runAt(Date.parse(deliverAt), internal.letters.deliver_letter, { letter_id: letterId });
      }
      return null;
    });
    const letter = await getByUuid(ctx, "letters", letterId);
    return letter && letter.couple_id === coupleId ? letterForViewer(letter, userId) : null;
  },
});

/**
 * The `deliver-due-letters` sweep. Delivers every sealed letter whose time has come, in pages, so
 * a letter arrives even when its scheduled `deliver_letter` was lost. A restore from a backup
 * carries no scheduled jobs, a renamed function leaves its old jobs pointing nowhere, and a failed
 * job is not retried. A letter waiting for a couple that ended stays in the range and writes
 * nothing until the relationship cleanup deletes it. Each run starts `sweep_letters_for_visits`.
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
    if (args.cursor === undefined || args.cursor === null) {
      await ctx.scheduler.runAfter(0, internal.letters.sweep_letters_for_visits, { p_now: now });
    }
    return null;
  },
});

/**
 * The visit half of the delivery sweep, every 5 minutes. Pages over the visits whose first day is
 * from `VISIT_SWEEP_DAYS` days before today in UTC to today, since an evening on a later first
 * day has not come in any zone, and delivers what each has brought on (`deliverVisitLetters`).
 * Nothing is scheduled per visit or letter, so a moved or deleted visit, a recipient in a new zone
 * or an ended couple needs nothing undone. A run that never happened is made up by the next for
 * at least two days after the evening.
 */
export const sweep_letters_for_visits = internalMutation({
  args: {
    p_now: v.optional(v.union(v.null(), v.string())),
    cursor: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const today = now.slice(0, 10);
    const page = await ctx.db
      .query("visits")
      .withIndex("by_deleted_at_start_date", (q) =>
        q.eq("deleted_at", undefined).gte("start_date", addDaysToDate(today, -VISIT_SWEEP_DAYS)).lte("start_date", today))
      .paginate({ numItems: DUE_LETTER_PAGE, cursor: args.cursor ?? null });
    for (const visit of page.page) await deliverVisitLetters(ctx, visit, now);
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.letters.sweep_letters_for_visits, { p_now: now, cursor: page.continueCursor });
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
