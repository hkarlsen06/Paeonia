import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { resolveContentReportTarget } from "./lib/reportTargets";
import { failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import {
  addDevice,
  createCouple,
  createSignedInUser,
  newTest,
  transactionClock,
  type TestConvex,
  type TestCouple,
  type TestUser,
} from "./test.setup";

const NOW = "2026-11-10T20:00:00.000Z";
const SECRET = "Meet me under the clock tower";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers();
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

type SendOptions = {
  user?: TestUser;
  letterId?: string;
  body?: string;
  delivery?: "now" | "at" | "morning";
  deliverAt?: string;
  withImage?: boolean;
  template?: string;
  operation?: ReturnType<typeof op>;
};

/** Writes a letter from `couple.first` (or `user`), uploading its image first when asked, like the app. */
async function send(t: TestConvex, couple: TestCouple, options: SendOptions = {}) {
  const user = options.user ?? couple.first;
  const letterId = options.letterId ?? newUuid();
  const image = options.withImage
    ? await uploadAsset(t, user, { ...photo(couple.coupleId, "letter", "letter_image"), parentId: letterId })
    : null;
  const letter = await user.as.mutation(api.letters.send_letter, {
    p_letter_id: letterId,
    p_template_key: options.template ?? "good_morning",
    p_body: options.body ?? SECRET,
    ...(image ? { p_media_asset_id: image.assetId } : {}),
    p_delivery_kind: options.delivery ?? "now",
    ...(options.deliverAt ? { p_deliver_at: options.deliverAt } : {}),
    ...(options.operation ?? op()),
  });
  return { letterId, imageId: image?.assetId ?? null, letter };
}

const getLetters = (user: TestUser) => user.as.query(api.letters.get_letters, {});
const olderLetters = (user: TestUser, list: "received" | "sent", before: { at: string; id: string }, limit = 50) =>
  user.as.query(api.letters.get_older_letters, { p_list: list, p_before_at: before.at, p_before_id: before.id, p_limit: limit });
/** Every letter `get_letters` gives `user`, once each. */
async function lettersFor(user: TestUser) {
  const mail = await getLetters(user);
  const all = [...mail.waiting, ...mail.received.letters, ...mail.sent.letters];
  return all.filter((letter, index) => all.findIndex((other) => other.id === letter.id) === index);
}
const open = (user: TestUser, id: string) => user.as.mutation(api.letters.open_letter, { p_letter_id: id });
const remove = (user: TestUser, id: string) => user.as.mutation(api.letters.delete_letter, { p_letter_id: id, ...op() });
const signImage = (user: TestUser, id: string) => user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: id });
const letterRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("letters").collect());
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
/** Runs the jobs scheduled to start now, such as the push about a letter that arrived. */
async function runDueJobs(t: TestConvex) {
  await vi.runOnlyPendingTimersAsync();
  await t.finishInProgressScheduledFunctions();
}
const scheduledDeliveries = (t: TestConvex) =>
  t.run(async (ctx) =>
    (await ctx.db.system.query("_scheduled_functions").collect()).filter((job) => job.name.includes("deliver_letter")),
  );

describe("access", () => {
  test("someone outside the couple and a couple without a subscription are refused by every function", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { letterId } = await send(t, couple);
    const stranger = await createSignedInUser(t);
    const lapsed = await createCouple(t, { entitled: false });

    for (const user of [stranger, lapsed.first]) {
      expect((await failure(getLetters(user))).code).toBe("42501");
      expect((await failure(olderLetters(user, "received", { at: NOW, id: letterId }))).code).toBe("42501");
      expect((await failure(user.as.query(api.letters.get_letter_partner_time_zone, {}))).code).toBe("42501");
      expect((await failure(user.as.mutation(api.letters.send_letter, {
        p_letter_id: newUuid(),
        p_template_key: "blank",
        p_body: "hi",
        p_delivery_kind: "now",
        ...op(),
      }))).code).toBe("42501");
      expect((await failure(open(user, letterId))).code).toBe("42501");
      expect((await failure(remove(user, letterId))).code).toBe("42501");
    }
    expect(await letterRows(t)).toHaveLength(1);
  });

  test("another couple cannot open, delete or reuse a letter's id", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const { letterId } = await send(t, couple);
    expect((await failure(open(other.second, letterId))).code).toBe("42501");
    expect((await failure(remove(other.first, letterId))).code).toBe("42501");
    expect((await failure(send(t, other, { letterId }))).code).toBe("42501");
    expect(await lettersFor(other.second)).toEqual([]);
  });
});

describe("send_letter", () => {
  test("a letter for now is delivered at once, and the author sees all of it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const timestamp = await transactionClock(t);
    const { letterId, imageId, letter } = await send(t, couple, { withImage: true });
    expect(letter).toEqual({
      id: letterId,
      author_user_id: couple.first.userId,
      recipient_user_id: couple.second.userId,
      template_key: "good_morning",
      body: SECRET,
      media_asset_id: imageId,
      delivery_kind: "now",
      deliver_at: timestamp(NOW),
      state: "delivered",
      delivered_at: timestamp(NOW),
      opened_at: null,
      created_at: timestamp(NOW),
    });
    expect(await getLetters(couple.first)).toEqual({
      waiting: [],
      received: { letters: [], next_before: null },
      sent: { letters: [letter], next_before: null },
    });
  });

  test("trims the note, refuses an empty or too long one, and refuses an unknown template or delivery", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await send(t, couple, { body: "  hello  " })).letter?.body).toBe("hello");
    expect((await send(t, couple, { body: "😀".repeat(2000) })).letter?.body).toBe("😀".repeat(2000));
    expect((await failure(send(t, couple, { body: "   " }))).code).toBe("23514");
    expect((await failure(send(t, couple, { body: "\uFEFF" }))).code).toBe("23514");
    expect((await failure(send(t, couple, { body: "a".repeat(2001) }))).code).toBe("22001");
    expect((await failure(send(t, couple, { body: "❤️".repeat(1001) }))).code).toBe("22001");
    expect((await send(t, couple, { body: "\u0085" })).letter?.body).toBe("\u0085");
    expect((await failure(send(t, couple, { template: "secret_admirer" }))).code).toBe("23514");
    expect((await failure(send(t, couple, { delivery: "at" }))).code).toBe("23514");
    expect((await failure(send(t, couple, { delivery: "at", deliverAt: "2027-11-12T20:00:00.000Z" }))).code).toBe("23514");
    expect(await letterRows(t)).toHaveLength(3);
  });

  test("a replay returns the letter as it is now and queues nothing twice", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const letterId = newUuid();
    const operation = op();
    const first = await send(t, couple, { letterId, operation });
    await runDueJobs(t);
    await open(couple.second, letterId);
    const again = await send(t, couple, { letterId, operation });
    expect(again.letter?.state).toBe("opened");
    expect((await send(t, couple, { letterId })).letter?.id).toBe(first.letterId);
    expect(await letterRows(t)).toHaveLength(1);
    await runDueJobs(t);
    expect((await outbox(t)).filter((row) => row.kind === "letter_arrived")).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("refuses an image that does not fit the contract", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const letterId = newUuid();
    const sendWith = (user: TestUser, assetId: string) =>
      failure(user.as.mutation(api.letters.send_letter, {
        p_letter_id: letterId,
        p_template_key: "blank",
        p_body: "hi",
        p_media_asset_id: assetId,
        p_delivery_kind: "now",
        ...op(),
      }));
    const partners = await uploadAsset(t, couple.second, { ...photo(couple.coupleId, "letter", "letter_image"), parentId: letterId });
    expect((await sendWith(couple.first, partners.assetId)).code).toBe("42501");
    const otherLetter = await uploadAsset(t, couple.first, { ...photo(couple.coupleId, "letter", "letter_image"), parentId: newUuid() });
    expect((await sendWith(couple.first, otherLetter.assetId)).code).toBe("23514");
    const storyPhoto = await uploadAsset(t, couple.first, { ...photo(couple.coupleId, "story", "story_photo"), parentId: letterId });
    expect((await sendWith(couple.first, storyPhoto.assetId)).code).toBe("23514");
    expect(await letterRows(t)).toHaveLength(0);
  });

  test("the 31st letter in an hour is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (let i = 0; i < 30; i += 1) await send(t, couple, { body: `letter ${i}` });
    expect((await failure(send(t, couple))).code).toBe("53300");
  });
});

describe("sealed letters stay off the recipient's phone", () => {
  test("a letter for a set time does not exist for the recipient until it is delivered, then it arrives without its words", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en" });
    const deliverAt = "2026-11-10T20:02:00.000Z";
    const { letterId, imageId, letter } = await send(t, couple, { delivery: "at", deliverAt, withImage: true });
    expect(letter?.state).toBe("sealed");
    expect(letter?.deliver_at).toBe(deliverAt);

    const before = await getLetters(couple.second);
    expect(await lettersFor(couple.second)).toEqual([]);
    expect(JSON.stringify(before)).not.toContain(SECRET);
    expect((await failure(signImage(couple.second, imageId!))).code).toBe("42501");
    expect((await failure(open(couple.second, letterId))).code).toBe("42501");
    expect(await deliverDuePushes(t)).toEqual([]);
    const [job] = await scheduledDeliveries(t);
    expect(job.scheduledTime).toBe(Date.parse(deliverAt));
    expect(job.args).toEqual([{ letter_id: letterId }]);

    vi.setSystemTime(new Date(deliverAt));
    await t.mutation(internal.letters.deliver_letter, { letter_id: letterId });
    const after = await getLetters(couple.second);
    const timestamp = await transactionClock(t);
    const arrived = {
      id: letterId,
      author_user_id: couple.first.userId,
      recipient_user_id: couple.second.userId,
      template_key: null,
      body: null,
      media_asset_id: null,
      delivery_kind: null,
      deliver_at: null,
      state: "delivered",
      delivered_at: timestamp(deliverAt),
      opened_at: null,
      created_at: null,
    };
    expect(after).toEqual({
      waiting: [arrived],
      received: { letters: [arrived], next_before: null },
      sent: { letters: [], next_before: null },
    });
    expect(JSON.stringify(after)).not.toContain(SECRET);
    expect(JSON.stringify(after)).not.toContain(imageId);
    expect((await failure(signImage(couple.second, imageId!))).code).toBe("42501");

    await runDueJobs(t);
    const [push] = await deliverDuePushes(t);
    expect(push.title).toBe("First Partner sent you a letter");
    expect(push.payload).toEqual({
      type: "letter_arrived",
      couple_id: couple.coupleId,
      letter_id: letterId,
      actor_user_id: couple.first.userId,
      route: "us",
      deeplink: `paeonia://mail/${letterId}`,
    });
    expect(JSON.stringify(push)).not.toContain(SECRET);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("opening shows the note and the image, and tells the author once", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId, { locale: "nb-NO" });
    const { letterId, imageId } = await send(t, couple, { withImage: true });
    const timestamp = await transactionClock(t);

    const opened = await open(couple.second, letterId);
    expect(opened).toMatchObject({ body: SECRET, media_asset_id: imageId, state: "opened", opened_at: timestamp(NOW) });
    expect((await getLetters(couple.second)).received.letters).toEqual([opened]);
    expect((await getLetters(couple.second)).waiting).toEqual([]);
    const [row] = await signImage(couple.second, imageId!);
    expect(row.signed_url).toContain("/media?asset=");
    expect((await getLetters(couple.first)).sent.letters[0]).toMatchObject({ state: "opened", opened_at: timestamp(NOW) });

    expect(await open(couple.second, letterId)).toEqual(opened);
    await runDueJobs(t);
    const pushes = await deliverDuePushes(t);
    expect(pushes.map((push) => [push.payload.type, push.title])).toEqual([["letter_opened", "Second Partner åpnet brevet ditt"]]);
    expect((await failure(open(couple.first, letterId))).code).toBe("42501");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the author can read the image from the start, and nobody before the letter names it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const letterId = newUuid();
    const image = await uploadAsset(t, couple.first, { ...photo(couple.coupleId, "letter", "letter_image"), parentId: letterId });
    expect((await failure(signImage(couple.first, image.assetId))).code).toBe("42501");
    await send(t, couple, { letterId, delivery: "morning", withImage: false });
    expect((await failure(signImage(couple.first, image.assetId))).code).toBe("42501");

    const sealed = await send(t, couple, { delivery: "morning", withImage: true });
    expect((await signImage(couple.first, sealed.imageId!))[0].media_asset_id).toBe(sealed.imageId);
  });
});

describe("morning delivery", () => {
  test("arrives at 08:00 on the recipient's clock, worked out at the send", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Asia/Tokyo"] });
    const partnerZone = () => couple.first.as.query(api.letters.get_letter_partner_time_zone, {});
    const sent = await send(t, couple, { delivery: "morning" });
    expect(sent.letter?.deliver_at).toBe("2026-11-10T23:00:00.000Z");
    expect(await partnerZone()).toEqual({ partner_time_zone_id: "Asia/Tokyo" });

    await addDevice(t, couple.second.userId, { timeZone: "America/Los_Angeles" });
    expect(await partnerZone()).toEqual({ partner_time_zone_id: "America/Los_Angeles" });
    expect((await send(t, couple, { delivery: "morning" })).letter?.deliver_at).toBe("2026-11-11T16:00:00.000Z");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("delete_letter", () => {
  test("unsending a sealed letter means the scheduled delivery writes nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const { letterId, imageId } = await send(t, couple, { delivery: "at", deliverAt: "2026-11-11T20:00:00.000Z", withImage: true });
    expect(await remove(couple.first, letterId)).toBeNull();
    expect(await lettersFor(couple.first)).toEqual([]);

    await t.finishAllScheduledFunctions(vi.runAllTimers);
    const [row] = await letterRows(t);
    expect(row.state).toBe("sealed");
    expect(row.delivered_at).toBeUndefined();
    expect(await lettersFor(couple.second)).toEqual([]);
    expect(await outbox(t)).toEqual([]);
    const asset = await t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", imageId!)).unique());
    expect(asset?.storage_delete_status).toBe("pending");
  });

  test("only the author deletes, a delivered letter leaves both lists, and its unsent push is dropped", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const { letterId } = await send(t, couple);
    expect((await failure(remove(couple.second, letterId))).code).toBe("42501");
    await remove(couple.first, letterId);
    expect(await lettersFor(couple.second)).toEqual([]);
    expect((await failure(open(couple.second, letterId))).code).toBe("P0002");
    await runDueJobs(t);
    expect(await deliverDuePushes(t)).toEqual([]);
    expect(await remove(couple.first, letterId)).toBeNull();
    expect((await failure(remove(couple.second, letterId))).code).toBe("42501");
    expect(await remove(couple.first, newUuid())).toBeNull();
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("pushes and badges", () => {
  test("letter pushes follow the letters switch", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    await couple.second.as.mutation(api.identity.set_notification_preference, { p_column: "letters_enabled", p_enabled: false });
    await send(t, couple);
    await runDueJobs(t);
    expect(await outbox(t)).toEqual([]);
  });

  test("a delivered letter counts on the Us tab and the icon until it is opened", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const badges = (user: TestUser) => user.as.query(api.badges.get_badges, {});
    const sealed = await send(t, couple, { delivery: "morning" });
    expect(await badges(couple.second)).toMatchObject({ us: 0, icon: 0 });
    await send(t, couple);
    expect(await badges(couple.second)).toMatchObject({ us: 1, icon: 1 });
    expect(await badges(couple.first)).toMatchObject({ us: 0, icon: 0 });
    vi.setSystemTime(new Date("2026-11-11T08:00:00.000Z"));
    await t.mutation(internal.letters.deliver_letter, { letter_id: sealed.letterId });
    expect(await badges(couple.second)).toMatchObject({ us: 2, icon: 2 });
    await open(couple.second, sealed.letterId);
    expect(await badges(couple.second)).toMatchObject({ us: 1, icon: 1 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("reports", () => {
  test("the recipient can report a letter they opened, and nothing they have not read", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { letterId } = await send(t, couple, { withImage: true });
    const resolve = (userId: string) =>
      t.run((ctx) => resolveContentReportTarget(ctx, userId, "letter", letterId, undefined));
    expect(await resolve(couple.second.userId)).toBeNull();
    await open(couple.second, letterId);
    const target = await resolve(couple.second.userId);
    expect(target).toMatchObject({ reported_user_id: couple.first.userId, couple_id: couple.coupleId });
    expect(target?.snapshot).toMatchObject({ letter_id: letterId, body: SECRET });
    expect(await resolve(couple.first.userId)).toBeNull();
  });
});

describe("cleanup", () => {
  test("cleanup soft-deletes the couple's letters and purge removes them, sparing other couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    await send(t, couple);
    await send(t, couple, { user: couple.second, delivery: "morning" });
    const spared = await send(t, other);

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    const afterCleanup = await letterRows(t);
    expect(afterCleanup.filter((letter) => letter.couple_id === couple.coupleId).every((letter) => letter.deleted_at === NOW)).toBe(true);
    expect(afterCleanup.find((letter) => letter.couple_id === other.coupleId)?.deleted_at).toBeUndefined();

    await t.run((ctx) => purgeCoupleContent(ctx, row));
    expect((await letterRows(t)).map((letter) => letter.id)).toEqual([spared.letterId]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("delivery that cannot be lost", () => {
  const cancelScheduledDeliveries = (t: TestConvex) =>
    t.run(async (ctx) => {
      for (const job of await ctx.db.system.query("_scheduled_functions").collect()) {
        if (job.name.includes("deliver_letter")) await ctx.scheduler.cancel(job._id);
      }
    });
  const arrivedPushes = async (t: TestConvex) => (await outbox(t)).filter((row) => row.kind === "letter_arrived");

  test("a letter whose scheduled delivery was lost, as after a restore, arrives with the sweep once", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const deliverAt = "2026-11-10T21:00:00.000Z";
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt });
    const other = await send(t, couple, { delivery: "at", deliverAt: "2026-11-11T21:00:00.000Z" });
    await cancelScheduledDeliveries(t);

    vi.setSystemTime(new Date("2026-11-10T20:59:59.000Z"));
    await t.mutation(internal.letters.deliver_due_letters, {});
    expect((await letterRows(t)).map((row) => row.state)).toEqual(["sealed", "sealed"]);

    vi.setSystemTime(new Date("2026-11-10T21:00:00.000Z"));
    await t.mutation(internal.letters.deliver_due_letters, {});
    await t.mutation(internal.letters.deliver_due_letters, {});
    await t.mutation(internal.letters.deliver_letter, { letter_id: letterId });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    const rows = await letterRows(t);
    expect(rows.find((row) => row.id === letterId)?.state).toBe("delivered");
    expect(rows.find((row) => row.id === other.letterId)?.state).toBe("sealed");
    expect((await arrivedPushes(t)).map((row) => row.payload.letter_id)).toEqual([letterId]);
  });

  test("the sweep pages through more due letters than one page holds", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run(async (ctx) => {
      for (let i = 0; i < 120; i += 1) {
        await ctx.db.insert("letters", {
          id: newUuid(),
          couple_id: couple.coupleId,
          author_user_id: couple.first.userId,
          recipient_user_id: couple.second.userId,
          template_key: "blank",
          body: `letter ${i}`,
          delivery_kind: "at",
          deliver_at: new Date(Date.parse(NOW) + i * 1000).toISOString(),
          state: "sealed",
          moderation_status: "visible",
          created_at: NOW,
        });
      }
    });
    vi.setSystemTime(new Date("2026-11-10T21:00:00.000Z"));
    await t.mutation(internal.letters.deliver_due_letters, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await letterRows(t)).filter((row) => row.state !== "delivered")).toEqual([]);
  });
});

describe("a relationship that ended", () => {
  const letterPushes = async (t: TestConvex) => (await outbox(t)).filter((row) => row.kind.startsWith("letter_"));

  test.each([
    ["the recipient leaves", (couple: TestCouple) => couple.second.as.mutation(api.relationship.leave_relationship, op())],
    ["the author deletes their account", (couple: TestCouple) => couple.first.as.mutation(api.identity.request_account_deletion, {})],
  ])("a sealed letter is never delivered after %s", async (_, end) => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const deliverAt = "2026-11-11T08:00:00.000Z";
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt });
    await end(couple);

    vi.setSystemTime(new Date(deliverAt));
    await t.mutation(internal.letters.deliver_letter, { letter_id: letterId });
    const [afterJob] = await letterRows(t);
    expect(afterJob.state).toBe("sealed");
    expect(afterJob.delivered_at).toBeUndefined();
    await t.mutation(internal.letters.deliver_due_letters, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await letterRows(t))[0].state).toBe("sealed");
    expect(await letterPushes(t)).toEqual([]);
  });
});

describe("bounded reads", () => {
  type Row = {
    id: string;
    author: TestUser;
    recipient: TestUser;
    state: "sealed" | "delivered" | "opened";
    at: string;
    deleted?: boolean;
    hidden?: boolean;
  };
  async function insertLetters(t: TestConvex, couple: TestCouple, rows: Row[]) {
    await t.run(async (ctx) => {
      for (const row of rows) {
        await ctx.db.insert("letters", {
          id: row.id,
          couple_id: couple.coupleId,
          author_user_id: row.author.userId,
          recipient_user_id: row.recipient.userId,
          template_key: "miss_you",
          body: SECRET,
          delivery_kind: "at",
          deliver_at: row.at,
          state: row.state,
          ...(row.state === "sealed" ? {} : { delivered_at: row.at }),
          ...(row.state === "opened" ? { opened_at: row.at } : {}),
          ...(row.deleted ? { deleted_at: row.at } : {}),
          moderation_status: row.hidden ? "hidden" : "visible",
          created_at: row.at,
        });
      }
    });
  }
  /** Reads a whole list the way the app does, the first page and then older pages until the end. */
  async function wholeList(user: TestUser, list: "received" | "sent", limit: number) {
    let page = (await getLetters(user))[list];
    const letters = [...page.letters];
    while (page.next_before) {
      page = await olderLetters(user, list, page.next_before, limit);
      letters.push(...page.letters);
    }
    return letters;
  }

  test("the received and sent lists page through every letter once, also when many arrived in the same millisecond", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { first, second } = couple;
    const minute = (i: number) => new Date(Date.parse("2026-11-01T00:00:00.000Z") + i * 60_000).toISOString();
    const rows: Row[] = [
      // A sweep page delivers many letters with one timestamp.
      ...Array.from({ length: 40 }, (): Row => ({ id: newUuid(), author: second, recipient: first, state: "delivered", at: minute(1) })),
      ...Array.from({ length: 30 }, (_, i): Row => ({ id: newUuid(), author: second, recipient: first, state: "opened", at: minute(2 + i) })),
      ...Array.from({ length: 10 }, (_, i): Row => ({ id: newUuid(), author: second, recipient: first, state: "opened", at: minute(40 + i), deleted: true })),
      ...Array.from({ length: 5 }, (_, i): Row => ({ id: newUuid(), author: second, recipient: first, state: "sealed", at: minute(60 + i) })),
    ];
    await insertLetters(t, couple, rows);
    const byTimeThenId = (a: Row, b: Row) => (a.at === b.at ? (a.id < b.id ? 1 : -1) : a.at < b.at ? 1 : -1);
    const arrived = rows.filter((row) => row.state !== "sealed" && !row.deleted).sort(byTimeThenId).map((row) => row.id);
    const written = rows.filter((row) => !row.deleted).sort(byTimeThenId).map((row) => row.id);

    const mail = await getLetters(first);
    expect(mail.received.letters).toHaveLength(25);
    expect(mail.sent.letters).toEqual([]);
    for (const limit of [7, 50]) {
      expect((await wholeList(first, "received", limit)).map((letter) => letter.id)).toEqual(arrived);
      expect((await wholeList(second, "sent", limit)).map((letter) => letter.id)).toEqual(written);
    }

    const unopened = (await wholeList(first, "received", 50)).filter((letter) => letter.state === "delivered");
    expect(unopened).toHaveLength(40);
    expect(JSON.stringify(unopened)).not.toContain(SECRET);
    for (const letter of unopened) {
      expect(letter).toMatchObject({ body: null, template_key: null, created_at: null, media_asset_id: null });
    }
    expect((await failure(olderLetters(first, "drafts" as "sent", { at: NOW, id: newUuid() }))).code).toBe("23514");
  });

  test("a page and its cursor hold only letters the reader is shown", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { first, second } = couple;
    const minute = (i: number) => new Date(Date.parse("2026-11-01T00:00:00.000Z") + i * 60_000).toISOString();
    const rows: Row[] = Array.from({ length: 60 }, (_, i): Row => ({
      id: newUuid(),
      author: second,
      recipient: first,
      state: "opened",
      at: minute(i),
      // Every third letter was hidden after a report, so pages end on hidden rows.
      hidden: i % 3 === 0,
    }));
    await insertLetters(t, couple, rows);
    const hidden = rows.filter((row) => row.hidden);
    const shown = rows.filter((row) => !row.hidden).sort((a, b) => (a.at < b.at ? 1 : -1)).map((row) => row.id);

    let page = (await getLetters(first)).received;
    const letters = [...page.letters];
    const cursors = [page.next_before];
    while (page.next_before) {
      page = await olderLetters(first, "received", page.next_before, 4);
      letters.push(...page.letters);
      cursors.push(page.next_before);
    }
    expect(letters.map((letter) => letter.id)).toEqual(shown);
    const seen = JSON.stringify(cursors);
    for (const row of hidden) {
      expect(seen).not.toContain(row.id);
      expect(seen).not.toContain(row.at);
    }
  });

  test("the waiting letters and the badge stop at 50, and deleted letters are not counted", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const at = (i: number) => new Date(Date.parse("2026-11-01T00:00:00.000Z") + i * 1000).toISOString();
    await insertLetters(t, couple, [
      ...Array.from({ length: 20 }, (_, i): Row => ({ id: newUuid(), author: couple.first, recipient: couple.second, state: "delivered", at: at(i), deleted: true })),
      ...Array.from({ length: 60 }, (_, i): Row => ({ id: newUuid(), author: couple.first, recipient: couple.second, state: "delivered", at: at(100 + i) })),
    ]);
    const mail = await getLetters(couple.second);
    expect(mail.waiting).toHaveLength(50);
    expect(mail.waiting[0].delivered_at).toBe(at(100));
    expect(await couple.second.as.query(api.badges.get_badges, {})).toMatchObject({ us: 50, icon: 50 });
  });
});
