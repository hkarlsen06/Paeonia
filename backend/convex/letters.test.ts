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
  delivery?: "now" | "at" | "morning" | "together";
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
const deliveryOptions = (user: TestUser) =>
  user.as.query(api.letters.get_letter_delivery_options, { p_now: new Date().toISOString() });
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
      expect((await failure(deliveryOptions(user))).code).toBe("42501");
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
    const partnerZone = async () => ({ partner_time_zone_id: (await deliveryOptions(couple.first)).partner_time_zone_id });
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
          waits_since: NOW,
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
          waits_since: row.at,
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

describe("letters for the next meeting", () => {
  const HOME = { latitude: 59.9, longitude: 10.75 };
  const AWAY = { latitude: 60.9, longitude: 10.75 };

  async function share(user: TestUser, couple: TestCouple, pausedUntil?: string) {
    await user.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId,
      p_is_enabled: true,
      p_consent_version: "test-v1",
      p_source: "settings_toggle",
      ...(pausedUntil ? { p_paused_until: pausedUntil } : {}),
      ...op(),
    });
  }
  const moveTo = (user: TestUser, couple: TestCouple, at: typeof HOME) =>
    user.as.mutation(api.location.update_latest_partner_location, {
      p_couple_id: couple.coupleId,
      p_latitude: at.latitude,
      p_longitude: at.longitude,
      p_accuracy_m: 20,
      p_captured_at: new Date(Date.now() - 60_000).toISOString(),
      p_source: "foreground_open",
      ...op(),
    });
  const saveVisit = (user: TestUser, id: string, start: string, end: string) =>
    user.as.mutation(api.visits.save_visit, { p_visit_id: id, p_start_date: start, p_end_date: end, p_place: null, ...op() });
  const deleteVisit = (user: TestUser, id: string) => user.as.mutation(api.visits.delete_visit, { p_visit_id: id, ...op() });
  /** One run of the visit half of the delivery sweep, at the test's clock. */
  const sweepAt = async (t: TestConvex, at: string) => {
    vi.setSystemTime(new Date(at));
    await t.mutation(internal.letters.sweep_letters_for_visits, {});
  };
  /** Jobs of the letters module that wait to run, such as a delivery set for later. */
  const pendingLetterJobs = (t: TestConvex) =>
    t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").collect())
        .filter((job) => job.name.includes("letters") && job.state.kind === "pending"));
  const stateOf = async (t: TestConvex, letterId: string) => (await letterRows(t)).find((row) => row.id === letterId)?.state;
  const arrivedPushes = async (t: TestConvex) => (await outbox(t)).filter((row) => row.kind === "letter_arrived");

  async function sharingCouple(t = newTest()) {
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await addDevice(t, couple.second.userId, { locale: "en" });
    await share(couple.first, couple);
    await share(couple.second, couple);
    await moveTo(couple.first, couple, AWAY);
    await moveTo(couple.second, couple, HOME);
    return { t, couple };
  }
  /** A couple in Oslo with a visit planned from `start` to `end`, saved now. */
  async function visitingCouple(start = "2026-11-14", end = "2026-11-16") {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const visitId = newUuid();
    await saveVisit(couple.first, visitId, start, end);
    return { t, couple, visitId };
  }

  test("has no time, schedules nothing, and leaves no trace in the recipient's reads", async () => {
    const { t, couple } = await visitingCouple();
    const before = await getLetters(couple.second);
    const { letterId, imageId, letter } = await send(t, couple, { delivery: "together", withImage: true });
    expect(letter).toMatchObject({ delivery_kind: "together", deliver_at: null, state: "sealed", delivered_at: null });
    expect(await pendingLetterJobs(t)).toEqual([]);

    expect(await getLetters(couple.second)).toEqual(before);
    expect((await failure(open(couple.second, letterId))).code).toBe("42501");
    expect((await failure(signImage(couple.second, imageId!))).code).toBe("42501");
    expect(await couple.second.as.query(api.badges.get_badges, {})).toMatchObject({ us: 0, icon: 0 });
    await t.mutation(internal.letters.deliver_due_letters, { p_now: "2026-11-13T20:00:00.000Z" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await stateOf(t, letterId)).toBe("sealed");
  });

  test("arrives when the author's phone shows the two together, once, and the push goes out", async () => {
    const { t, couple } = await sharingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });

    await moveTo(couple.first, couple, HOME);
    expect(await stateOf(t, letterId)).toBe("delivered");
    expect((await getLetters(couple.second)).waiting.map((letter) => letter.id)).toEqual([letterId]);
    await moveTo(couple.first, couple, HOME);
    await runDueJobs(t);
    const pushes = await deliverDuePushes(t);
    expect(pushes.filter((push) => push.payload.type === "letter_arrived")).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await arrivedPushes(t)).toHaveLength(1);
  });

  test("the recipient's phone alone cannot bring it on, even when it claims to stand by the author", async () => {
    const { t, couple } = await sharingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });

    await moveTo(couple.second, couple, AWAY);
    expect(await stateOf(t, letterId)).toBe("sealed");
    expect(await lettersFor(couple.second)).toEqual([]);

    // The author's next fix there is the meeting, though today is already a together day.
    await moveTo(couple.first, couple, AWAY);
    expect(await stateOf(t, letterId)).toBe("delivered");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a letter the author unsent never arrives at the meeting", async () => {
    const { t, couple } = await sharingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });
    await remove(couple.first, letterId);
    await moveTo(couple.first, couple, HOME);
    expect(await stateOf(t, letterId)).toBe("sealed");
    expect(await lettersFor(couple.second)).toEqual([]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await arrivedPushes(t)).toEqual([]);
  });

  test("a partner's pause changes nothing the author is offered, sends or sees", async () => {
    // Two couples alike, but in one the recipient paused sharing after their last fix.
    const authorView = async (paused: boolean) => {
      vi.setSystemTime(new Date(NOW));
      const { t, couple } = await sharingCouple();
      const sentRows = async () =>
        (await getLetters(couple.first)).sent.letters.map(({ id, author_user_id, recipient_user_id, ...rest }) => rest);
      if (paused) await share(couple.second, couple, new Date(Date.now() + 4 * 3_600_000).toISOString());
      const offered = await deliveryOptions(couple.first);
      await send(t, couple, { delivery: "together" });
      const waiting = await sentRows();
      await moveTo(couple.first, couple, HOME);
      const met = await deliveryOptions(couple.first);
      const sent = await sentRows();
      await t.finishAllScheduledFunctions(vi.runAllTimers);
      return { offered, waiting, met, sent };
    };
    const silent = await authorView(false);
    expect(silent.offered).toMatchObject({ together_now: false, both_share_location: true });
    expect(silent.sent[0]).toMatchObject({ state: "delivered" });
    expect(await authorView(true)).toEqual(silent);
  });

  test("arrives at 20:00 on the recipient's clock on the first day of a visit planned before it, once", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Asia/Tokyo"] });
    await addDevice(t, couple.first.userId);
    await addDevice(t, couple.second.userId);
    await saveVisit(couple.second, newUuid(), "2026-11-14", "2026-11-16");
    const { letterId } = await send(t, couple, { delivery: "together" });
    const back = await send(t, couple, { user: couple.second, delivery: "together" });
    expect(await pendingLetterJobs(t)).toEqual([]);

    await sweepAt(t, "2026-11-14T10:59:59.999Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    await sweepAt(t, "2026-11-14T11:00:00.000Z");
    await sweepAt(t, "2026-11-14T11:05:00.000Z");
    expect(await stateOf(t, letterId)).toBe("delivered");
    expect(await stateOf(t, back.letterId)).toBe("sealed");
    await sweepAt(t, "2026-11-14T19:00:00.000Z");
    expect(await stateOf(t, back.letterId)).toBe("delivered");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await arrivedPushes(t)).map((row) => row.payload.letter_id).sort()).toEqual([letterId, back.letterId].sort());
  });

  test("when no sweep ran on the evening, as after a restore, the next run of the delivery sweep still brings the letter", async () => {
    const { t, couple } = await visitingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });
    // A restore brings back no scheduled job, so nothing may wait for the evening but the cron.
    await t.run(async (ctx) => {
      for (const job of await ctx.db.system.query("_scheduled_functions").collect()) {
        if (job.state.kind === "pending") await ctx.scheduler.cancel(job._id);
      }
    });
    vi.setSystemTime(new Date("2026-11-16T12:00:00.000Z"));
    await t.mutation(internal.letters.deliver_due_letters, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  test("follows the recipient's zone on the day, not the one when the visit was saved", async () => {
    const { t, couple } = await visitingCouple("2026-11-20", "2026-11-22");
    await addDevice(t, couple.second.userId, { timeZone: "Europe/Oslo" });
    const { letterId } = await send(t, couple, { delivery: "together" });
    vi.setSystemTime(new Date("2026-11-19T12:00:00.000Z"));
    await addDevice(t, couple.second.userId, { timeZone: "America/New_York" });

    await sweepAt(t, "2026-11-20T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    await sweepAt(t, "2026-11-21T01:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  test("a visit saved on its own first day or later delivers nothing by time, and location still can", async () => {
    const { t, couple } = await sharingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });
    const today = newUuid();
    await saveVisit(couple.second, today, "2026-11-10", "2026-11-11");
    await sweepAt(t, "2026-11-10T21:00:00.000Z");
    await deleteVisit(couple.second, today);
    // A visit planned ahead whose first day moves to today counts as planned today.
    const moved = newUuid();
    await saveVisit(couple.second, moved, "2026-11-13", "2026-11-14");
    vi.setSystemTime(new Date("2026-11-12T08:00:00.000Z"));
    await saveVisit(couple.second, moved, "2026-11-12", "2026-11-14");
    await sweepAt(t, "2026-11-12T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    expect(await lettersFor(couple.second)).toEqual([]);

    await moveTo(couple.second, couple, HOME);
    await moveTo(couple.first, couple, HOME);
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  /** A couple whose `first` writes from `authorZone` and whose `second` receives in `recipientZone`, sharing location. */
  async function farApartCouple(authorZone: string, recipientZone: string) {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: [authorZone, recipientZone] });
    await addDevice(t, couple.first.userId, { timeZone: authorZone });
    await addDevice(t, couple.second.userId, { timeZone: recipientZone });
    await share(couple.first, couple);
    await share(couple.second, couple);
    return { t, couple };
  }

  test("in Los Angeles and Auckland, a visit the recipient plans for their own today brings nothing on by time", async () => {
    const { t, couple } = await farApartCouple("America/Los_Angeles", "Pacific/Auckland");
    const { letterId } = await send(t, couple, { delivery: "together" });
    // Thursday 19 November 19:55 in Auckland is Wednesday 18 November 22:55 in Los Angeles.
    vi.setSystemTime(new Date("2026-11-19T06:55:00.000Z"));
    const visitId = newUuid();
    await saveVisit(couple.second, visitId, "2026-11-19", "2026-11-19");
    expect(await deliveryOptions(couple.first)).toMatchObject({ next_visit_start_date: null, next_visit_too_soon: true });

    await sweepAt(t, "2026-11-19T07:05:00.000Z");
    await sweepAt(t, "2026-11-20T07:05:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    expect(await lettersFor(couple.second)).toEqual([]);
  });

  test("in Oslo and New York, a visit the recipient plans early on its first day brings nothing on by time", async () => {
    const { t, couple } = await farApartCouple("America/New_York", "Europe/Oslo");
    const { letterId } = await send(t, couple, { delivery: "together" });
    // Thursday 19 November 05:30 in Oslo is Wednesday 18 November 23:30 in New York.
    vi.setSystemTime(new Date("2026-11-19T04:30:00.000Z"));
    await saveVisit(couple.second, newUuid(), "2026-11-19", "2026-11-20");
    expect(await deliveryOptions(couple.first)).toMatchObject({ next_visit_start_date: null, next_visit_too_soon: true });

    await sweepAt(t, "2026-11-19T19:00:00.000Z");
    await sweepAt(t, "2026-11-20T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
  });

  test("in far zones, a visit planned before the recipient's first day starts arrives on its evening", async () => {
    const { t, couple } = await farApartCouple("America/Los_Angeles", "Pacific/Auckland");
    const { letterId } = await send(t, couple, { delivery: "together" });
    // 23:59 on Wednesday 18 November in Auckland, 20 hours and a minute before 20:00 on the 19th there.
    vi.setSystemTime(new Date("2026-11-18T10:59:00.000Z"));
    await saveVisit(couple.second, newUuid(), "2026-11-19", "2026-11-20");
    expect(await deliveryOptions(couple.first)).toMatchObject({ next_visit_start_date: "2026-11-19", next_visit_too_soon: false });

    await sweepAt(t, "2026-11-19T06:59:59.999Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    await sweepAt(t, "2026-11-19T07:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  test("a letter written after a one-day visit is not brought on by it when the recipient's phone moves west", async () => {
    const { t, couple } = await sharingCouple();
    await addDevice(t, couple.second.userId, { timeZone: "Europe/Oslo" });
    await saveVisit(couple.second, newUuid(), "2026-11-14", "2026-11-14");
    // Sunday 15 November 00:30 in Oslo, after the visit.
    vi.setSystemTime(new Date("2026-11-14T23:30:00.000Z"));
    const { letterId } = await send(t, couple, { delivery: "together" });
    await sweepAt(t, "2026-11-15T00:05:00.000Z");
    // The recipient lands in New York, where it is still 20:00 on the 14th at 01:00 UTC on the 15th.
    vi.setSystemTime(new Date("2026-11-15T14:00:00.000Z"));
    await addDevice(t, couple.second.userId, { timeZone: "America/New_York" });
    await sweepAt(t, "2026-11-15T14:05:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    expect(await lettersFor(couple.second)).toEqual([]);
  });

  test("a letter for the visit the composer named after a one-day visit waits for that visit, whatever the recipient's zone", async () => {
    const { t, couple } = await visitingCouple("2026-11-14", "2026-11-14");
    await addDevice(t, couple.second.userId, { timeZone: "Europe/Oslo" });
    await saveVisit(couple.first, newUuid(), "2026-12-12", "2026-12-14");
    vi.setSystemTime(new Date("2026-11-14T23:30:00.000Z"));
    expect(await deliveryOptions(couple.first)).toMatchObject({ next_visit_start_date: "2026-12-12" });
    const { letterId } = await send(t, couple, { delivery: "together" });
    vi.setSystemTime(new Date("2026-11-15T07:00:00.000Z"));
    await addDevice(t, couple.second.userId, { timeZone: "Pacific/Pago_Pago" });
    await sweepAt(t, "2026-11-15T07:05:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    // 20:00 on 12 December in Pago Pago.
    await sweepAt(t, "2026-12-13T07:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  test("a letter the composer took on the last minute of the day before the visit, 12 hours behind UTC, arrives that evening", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Etc/GMT+12", "Etc/GMT+12"] });
    await addDevice(t, couple.second.userId, { timeZone: "Etc/GMT+12" });
    await saveVisit(couple.second, newUuid(), "2026-11-19", "2026-11-20");
    // 23:59 on 18 November in UTC-12.
    vi.setSystemTime(new Date("2026-11-19T11:59:00.000Z"));
    expect(await deliveryOptions(couple.first)).toMatchObject({ together_now: false, next_visit_start_date: "2026-11-19" });
    const { letterId } = await send(t, couple, { delivery: "together" });
    await sweepAt(t, "2026-11-20T07:59:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    await sweepAt(t, "2026-11-20T08:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  test("a visit planned ahead and made longer or moved somewhere else on its first day still arrives that evening", async () => {
    const { t, couple, visitId } = await visitingCouple("2026-11-14", "2026-11-15");
    const { letterId } = await send(t, couple, { delivery: "together" });
    vi.setSystemTime(new Date("2026-11-14T09:00:00.000Z"));
    await saveVisit(couple.second, visitId, "2026-11-14", "2026-11-16");
    await couple.second.as.mutation(api.visits.save_visit, {
      p_visit_id: visitId,
      p_place: { name: "Bergen", latitude: 60.39, longitude: 5.32 },
      ...op(),
    });
    await sweepAt(t, "2026-11-14T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  test("a moved visit arrives on its new first day, a deleted one never, and neither leaves a run behind", async () => {
    const { t, couple, visitId } = await visitingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });
    await saveVisit(couple.first, visitId, "2026-11-21", "2026-11-23");
    await sweepAt(t, "2026-11-14T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");

    await deleteVisit(couple.first, visitId);
    expect(await pendingLetterJobs(t)).toEqual([]);
    await sweepAt(t, "2026-11-21T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    expect((await getLetters(couple.first)).sent.letters[0]).toMatchObject({ id: letterId, state: "sealed", delivery_kind: "together" });
    expect(await lettersFor(couple.second)).toEqual([]);

    const later = newUuid();
    vi.setSystemTime(new Date(NOW));
    await saveVisit(couple.first, later, "2026-11-28", "2026-11-29");
    await saveVisit(couple.first, later, "2026-11-30", "2026-12-01");
    await saveVisit(couple.first, newUuid(), "2100-12-01", "2100-12-02");
    expect(await pendingLetterJobs(t)).toEqual([]);
    await sweepAt(t, "2026-11-28T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
    await sweepAt(t, "2026-11-30T19:00:00.000Z");
    expect(await stateOf(t, letterId)).toBe("delivered");
  });

  test("a visit that ended before the letter was written does not deliver it", async () => {
    vi.setSystemTime(new Date("2026-10-25T12:00:00.000Z"));
    const { t, couple } = await visitingCouple("2026-11-01", "2026-11-03");
    vi.setSystemTime(new Date(NOW));
    await saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02");
    const { letterId } = await send(t, couple, { delivery: "together" });
    await sweepAt(t, "2026-11-10T20:05:00.000Z");
    expect(await stateOf(t, letterId)).toBe("sealed");
  });

  test("send refuses one the composer would not offer, and stores nothing", async () => {
    const t = newTest();
    const apart = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    expect(await deliveryOptions(apart.first)).toMatchObject({ next_visit_start_date: null, both_share_location: false });
    expect((await failure(send(t, apart, { delivery: "together" }))).code).toBe("55000");

    const visiting = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await saveVisit(visiting.first, newUuid(), "2026-11-09", "2026-11-12");
    expect(await deliveryOptions(visiting.first)).toMatchObject({ together_now: true });
    expect((await failure(send(t, visiting, { delivery: "together" }))).code).toBe("55000");
    expect(await letterRows(t)).toEqual([]);
  });

  test("the composer offers it only while apart, with a visit ahead or both sharing location", async () => {
    const { t, couple } = await sharingCouple();
    expect(await deliveryOptions(couple.first)).toEqual({
      partner_time_zone_id: "Europe/Oslo",
      partner_birthday: null,
      together_now: false,
      next_visit_start_date: null,
      next_visit_too_soon: false,
      both_share_location: true,
    });
    await saveVisit(couple.second, newUuid(), "2026-11-20", "2026-11-22");
    await saveVisit(couple.second, newUuid(), "2026-11-14", "2026-11-15");
    expect(await deliveryOptions(couple.first)).toMatchObject({ together_now: false, next_visit_start_date: "2026-11-14" });

    await moveTo(couple.first, couple, HOME);
    expect(await deliveryOptions(couple.first)).toMatchObject({ together_now: true });
    const apart = await createCouple(t);
    expect(await deliveryOptions(apart.first)).toMatchObject({ together_now: false, both_share_location: false });
  });

  test("after the relationship ends it is never delivered, and the cleanup takes it and its photo", async () => {
    const { t, couple } = await visitingCouple();
    await addDevice(t, couple.second.userId);
    const { letterId, imageId } = await send(t, couple, { delivery: "together", withImage: true });
    await couple.second.as.mutation(api.relationship.leave_relationship, op());

    await sweepAt(t, "2026-11-14T19:00:00.000Z");
    await t.mutation(internal.letters.deliver_meeting_letters, { couple_id: couple.coupleId, recipient_user_id: couple.second.userId });
    expect(await stateOf(t, letterId)).toBe("sealed");
    expect(await pendingLetterJobs(t)).toEqual([]);

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, "2026-11-14T19:00:00.000Z"));
    expect((await letterRows(t))[0].deleted_at).toBe("2026-11-14T19:00:00.000Z");
    const asset = await t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", imageId!)).unique());
    expect(asset?.storage_delete_status).toBe("pending");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await arrivedPushes(t)).toEqual([]);
  });
});

type EditOptions = {
  user?: TestUser;
  body?: string;
  template?: string;
  imageId?: string | null;
  delivery?: "now" | "at" | "morning" | "together";
  deliverAt?: string;
  operation?: ReturnType<typeof op>;
};

/** Changes the letter `letterId` as the app does, with every part of it given again. */
const edit = (couple: TestCouple, letterId: string, options: EditOptions = {}) =>
  (options.user ?? couple.first).as.mutation(api.letters.edit_letter, {
    p_letter_id: letterId,
    p_template_key: options.template ?? "good_morning",
    p_body: options.body ?? SECRET,
    ...(options.imageId ? { p_media_asset_id: options.imageId } : {}),
    p_delivery_kind: options.delivery ?? "at",
    ...(options.deliverAt ? { p_deliver_at: options.deliverAt } : {}),
    ...(options.operation ?? op()),
  });
/** Moves the clock to `iso` and runs the jobs that came due on the way, as the scheduler does. */
async function runJobsUntil(t: TestConvex, iso: string) {
  await vi.advanceTimersByTimeAsync(Date.parse(iso) - Date.now());
  await t.finishInProgressScheduledFunctions();
}
const assetStatus = (t: TestConvex, id: string) =>
  t.run(async (ctx) =>
    (await ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", id)).unique())?.storage_delete_status);

describe("edit_letter", () => {
  const LATER = "2026-11-11T20:00:00.000Z";
  const NEW_WORDS = "The train gets in at six";

  test("only the author changes a letter, and only while it is sealed", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const lapsed = await createCouple(t, { entitled: false });
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt: LATER });
    const changed = { body: NEW_WORDS, deliverAt: LATER };

    for (const user of [stranger, lapsed.first, other.first, other.second, couple.second]) {
      expect((await failure(edit(couple, letterId, { ...changed, user }))).code).toBe("42501");
    }
    expect((await failure(edit(couple, newUuid(), changed))).code).toBe("P0002");

    const arrived = await send(t, couple);
    expect((await failure(edit(couple, arrived.letterId, changed))).code).toBe("40001");
    expect((await failure(edit(couple, arrived.letterId, { ...changed, user: couple.second }))).code).toBe("42501");
    await remove(couple.first, letterId);
    expect((await failure(edit(couple, letterId, changed))).code).toBe("P0002");

    expect((await letterRows(t)).map((row) => row.body)).toEqual([SECRET, SECRET]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a letter moved later arrives once, with the new words, at the new time, and the partner sees nothing before", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en" });
    const badges = (user: TestUser) => user.as.query(api.badges.get_badges, {});
    const { letterId, imageId } = await send(t, couple, { delivery: "at", deliverAt: LATER, withImage: true });
    const partnerBefore = { mail: await getLetters(couple.second), badges: await badges(couple.second) };

    const newer = await uploadAsset(t, couple.first, { ...photo(couple.coupleId, "letter", "letter_image"), parentId: letterId });
    const movedTo = "2026-11-12T09:30:00.000Z";
    const operation = op();
    const changed = await edit(couple, letterId, {
      template: "miss_you", body: NEW_WORDS, imageId: newer.assetId, deliverAt: movedTo, operation,
    });
    expect(changed).toMatchObject({
      template_key: "miss_you", body: NEW_WORDS, media_asset_id: newer.assetId, state: "sealed", deliver_at: movedTo,
    });
    expect(await assetStatus(t, imageId!)).toBe("pending");
    expect(await assetStatus(t, newer.assetId)).not.toBe("pending");
    expect(await getLetters(couple.second)).toEqual(partnerBefore.mail);
    expect(await badges(couple.second)).toEqual(partnerBefore.badges);
    expect((await failure(signImage(couple.second, newer.assetId))).code).toBe("42501");

    await runJobsUntil(t, LATER);
    await t.mutation(internal.letters.deliver_due_letters, {});
    expect(await lettersFor(couple.second)).toEqual([]);
    expect(await deliverDuePushes(t)).toEqual([]);

    await runJobsUntil(t, movedTo);
    await runDueJobs(t);
    const [row] = await letterRows(t);
    expect(row).toMatchObject({ state: "delivered", body: NEW_WORDS, delivered_at: expect.stringMatching(/^2026-11-12T09:30/) });
    expect((await outbox(t)).filter((push) => push.kind === "letter_arrived")).toHaveLength(1);
    const opened = await open(couple.second, letterId);
    expect(opened).toMatchObject({ body: NEW_WORDS, template_key: "miss_you", media_asset_id: newer.assetId });
    expect(JSON.stringify(await getLetters(couple.second))).not.toContain(SECRET);

    const replay = await couple.first.as.mutation(api.letters.edit_letter, {
      p_letter_id: letterId, p_template_key: "miss_you", p_body: NEW_WORDS, p_media_asset_id: newer.assetId,
      p_delivery_kind: "at", p_deliver_at: movedTo, ...operation,
    });
    expect(replay).toMatchObject({ id: letterId, state: "opened", body: NEW_WORDS });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a letter moved earlier arrives at the new time and the old job writes nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt: LATER });
    const earlier = "2026-11-10T22:00:00.000Z";
    await edit(couple, letterId, { body: NEW_WORDS, deliverAt: earlier });

    await runJobsUntil(t, earlier);
    await runDueJobs(t);
    const [row] = await letterRows(t);
    expect(row.state).toBe("delivered");
    expect(row.delivered_at?.startsWith("2026-11-10T22:00")).toBe(true);
    await runJobsUntil(t, LATER);
    expect((await letterRows(t))[0].delivered_at).toBe(row.delivered_at);
    expect((await outbox(t)).filter((push) => push.kind === "letter_arrived")).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("changing to now delivers at once, and removing the image queues it for deletion", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { letterId, imageId } = await send(t, couple, { delivery: "morning", withImage: true });
    const changed = await edit(couple, letterId, { body: NEW_WORDS, delivery: "now" });
    expect(changed).toMatchObject({ state: "delivered", media_asset_id: null, body: NEW_WORDS });
    expect(await assetStatus(t, imageId!)).toBe("pending");
    expect(await lettersFor(couple.second)).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await letterRows(t))[0].state).toBe("delivered");
  });

  test("new words for a morning letter whose 08:00 came before its job ran keep that morning, and it arrives at once", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const { letterId, letter } = await send(t, couple, { delivery: "morning" });
    expect(letter?.deliver_at).toBe("2026-11-11T07:00:00.000Z");

    // The clock passes 08:00 in Oslo before the scheduler runs the job, as when it is late or lost.
    vi.setSystemTime(new Date("2026-11-11T07:00:30.000Z"));
    const changed = await edit(couple, letterId, { body: NEW_WORDS, delivery: "morning" });
    expect(changed).toMatchObject({ deliver_at: "2026-11-11T07:00:00.000Z", state: "delivered", body: NEW_WORDS });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await letterRows(t))[0].delivered_at?.startsWith("2026-11-11T07:00")).toBe(true);
  });

  test("keeping the image keeps it, and a borrowed image is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { letterId, imageId } = await send(t, couple, { delivery: "at", deliverAt: LATER, withImage: true });
    const other = await send(t, couple, { delivery: "at", deliverAt: LATER, withImage: true });
    expect(await edit(couple, letterId, { body: NEW_WORDS, deliverAt: LATER, imageId })).toMatchObject({ media_asset_id: imageId });
    expect(await assetStatus(t, imageId!)).not.toBe("pending");
    expect((await failure(edit(couple, letterId, { deliverAt: LATER, imageId: other.imageId }))).code).toBe("23514");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("a birthday card", () => {
  test("the composer reads the partner's saved birthday with their time zone", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Pacific/Kiritimati"] });
    await couple.first.as.mutation(api.countdowns.set_birthday, {
      p_user_id: couple.second.userId, p_birthday: "1999-02-28", ...op(),
    });
    expect(await deliveryOptions(couple.first)).toMatchObject({
      partner_time_zone_id: "Pacific/Kiritimati", partner_birthday: "1999-02-28",
    });
    expect(await deliveryOptions(couple.second)).toMatchObject({ partner_birthday: null });
  });

  test("the latest birthday morning the app can pick fits the year a letter may wait", async () => {
    vi.setSystemTime(new Date("2027-03-01T10:00:00.000Z"));
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Pacific/Pago_Pago", "Pacific/Kiritimati"] });
    const nextBirthday = "2028-02-29T18:00:00.000Z";
    const { letter } = await send(t, couple, { template: "birthday", delivery: "at", deliverAt: nextBirthday });
    expect(letter).toMatchObject({ state: "sealed", deliver_at: nextBirthday });
    const tooFar = new Date(Date.parse("2027-03-01T10:00:00.000Z") + 366 * 86_400_000 + 60_000).toISOString();
    expect((await failure(send(t, couple, { delivery: "at", deliverAt: tooFar }))).code).toBe("23514");
  });
});

describe("changing a letter for the next meeting", () => {
  const HOME = { latitude: 59.9, longitude: 10.75 };
  const AWAY = { latitude: 60.9, longitude: 10.75 };
  const EVENING = "2026-11-14T19:00:00.000Z";
  const NEW_WORDS = "The train gets in at six";

  const share = (user: TestUser, couple: TestCouple) =>
    user.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId, p_is_enabled: true, p_consent_version: "test-v1", p_source: "settings_toggle", ...op(),
    });
  const moveTo = (user: TestUser, couple: TestCouple, at: typeof HOME) =>
    user.as.mutation(api.location.update_latest_partner_location, {
      p_couple_id: couple.coupleId, p_latitude: at.latitude, p_longitude: at.longitude, p_accuracy_m: 20,
      p_captured_at: new Date(Date.now() - 60_000).toISOString(), p_source: "foreground_open", ...op(),
    });
  const saveVisit = (user: TestUser, start: string, end: string) =>
    user.as.mutation(api.visits.save_visit, { p_visit_id: newUuid(), p_start_date: start, p_end_date: end, p_place: null, ...op() });
  const sweepAt = async (t: TestConvex, at: string) => {
    await runJobsUntil(t, at);
    await t.mutation(internal.letters.sweep_letters_for_visits, {});
    await t.mutation(internal.letters.deliver_due_letters, {});
  };
  const pendingLetterJobs = (t: TestConvex) =>
    t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").collect())
        .filter((job) => job.name.includes("letters") && job.state.kind === "pending"));
  const rowOf = async (t: TestConvex, letterId: string) => (await letterRows(t)).find((row) => row.id === letterId)!;
  const arrivedPushes = async (t: TestConvex) => (await outbox(t)).filter((row) => row.kind === "letter_arrived");

  /** A couple in Oslo with a visit from 14 to 16 November planned now, so its evening is `EVENING`. */
  async function visitingCouple() {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await addDevice(t, couple.second.userId, { locale: "en" });
    await saveVisit(couple.first, "2026-11-14", "2026-11-16");
    return { t, couple };
  }
  /** A couple apart who both share their location, with no visit planned. */
  async function sharingCouple() {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await addDevice(t, couple.second.userId, { locale: "en" });
    await share(couple.first, couple);
    await share(couple.second, couple);
    await moveTo(couple.first, couple, AWAY);
    await moveTo(couple.second, couple, HOME);
    return { t, couple };
  }

  test("only the author changes it, as with any sealed letter", async () => {
    const { t, couple } = await visitingCouple();
    const other = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const { letterId } = await send(t, couple, { delivery: "together" });
    for (const user of [stranger, other.first, couple.second]) {
      expect((await failure(edit(couple, letterId, { user, body: NEW_WORDS, delivery: "together" }))).code).toBe("42501");
    }
    expect((await rowOf(t, letterId)).body).toBe(SECRET);
  });

  test("new words keep it waiting, with no time and no job, and it arrives with them at the meeting", async () => {
    const { t, couple } = await visitingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });
    const partnerBefore = { mail: await getLetters(couple.second), badges: await couple.second.as.query(api.badges.get_badges, {}) };

    const changed = await edit(couple, letterId, { body: NEW_WORDS, template: "miss_you", delivery: "together" });
    expect(changed).toMatchObject({ delivery_kind: "together", deliver_at: null, state: "sealed", body: NEW_WORDS });
    expect(await pendingLetterJobs(t)).toEqual([]);
    expect(await getLetters(couple.second)).toEqual(partnerBefore.mail);
    expect(await couple.second.as.query(api.badges.get_badges, {})).toEqual(partnerBefore.badges);

    await sweepAt(t, "2026-11-14T18:59:00.000Z");
    expect((await rowOf(t, letterId)).state).toBe("sealed");
    await sweepAt(t, EVENING);
    await runDueJobs(t);
    expect(await arrivedPushes(t)).toHaveLength(1);
    expect(await open(couple.second, letterId)).toMatchObject({ body: NEW_WORDS, template_key: "miss_you" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a letter for a set time moves to the next meeting only when the composer would offer it", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt: "2026-11-12T09:00:00.000Z" });
    expect((await failure(edit(couple, letterId, { delivery: "together" }))).code).toBe("55000");
    expect(await rowOf(t, letterId)).toMatchObject({ delivery_kind: "at", deliver_at: "2026-11-12T09:00:00.000Z" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await rowOf(t, letterId)).state).toBe("delivered");
  });

  test("moved to the next meeting, neither its old job nor the time sweep delivers it, and the visit does once", async () => {
    const { t, couple } = await visitingCouple();
    const at = "2026-11-12T09:00:00.000Z";
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt: at });
    expect(await edit(couple, letterId, { delivery: "together" })).toMatchObject({ delivery_kind: "together", deliver_at: null });

    await sweepAt(t, "2026-11-12T09:01:00.000Z");
    expect((await rowOf(t, letterId)).state).toBe("sealed");
    expect(await lettersFor(couple.second)).toEqual([]);
    await sweepAt(t, EVENING);
    await sweepAt(t, "2026-11-14T19:05:00.000Z");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await rowOf(t, letterId)).delivered_at?.startsWith("2026-11-14T19:00")).toBe(true);
    expect(await arrivedPushes(t)).toHaveLength(1);
  });

  test("every letter row says when it started to wait, so the visit sweep never meets one without it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt: "2026-11-12T09:00:00.000Z" });
    expect((await rowOf(t, letterId)).waits_since).toBe((await rowOf(t, letterId)).created_at);
    await expect(t.run((ctx) => ctx.db.insert("letters", {
      id: newUuid(), couple_id: couple.coupleId, author_user_id: couple.first.userId,
      recipient_user_id: couple.second.userId, template_key: "blank", body: SECRET, delivery_kind: "together",
      state: "sealed", moderation_status: "visible", created_at: NOW,
    } as never))).rejects.toThrow(/waits_since/);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("moved to the next meeting after a visit's evening, it waits for the next meeting, not the one that passed", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await saveVisit(couple.first, "2026-11-14", "2026-11-14");
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt: "2026-11-20T09:00:00.000Z" });

    await runJobsUntil(t, "2026-11-15T12:00:00.000Z");
    await saveVisit(couple.first, "2026-11-25", "2026-11-26");
    await edit(couple, letterId, { delivery: "together" });
    await sweepAt(t, "2026-11-15T12:05:00.000Z");
    expect((await rowOf(t, letterId)).state).toBe("sealed");
    await sweepAt(t, "2026-11-20T09:01:00.000Z");
    expect((await rowOf(t, letterId)).state).toBe("sealed");
    await sweepAt(t, "2026-11-25T19:00:00.000Z");
    expect((await rowOf(t, letterId)).state).toBe("delivered");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("moved from the next meeting to a time, the meeting no longer brings it, and its time does", async () => {
    const { t, couple } = await sharingCouple();
    const { letterId } = await send(t, couple, { delivery: "together" });
    const at = "2026-11-11T09:00:00.000Z";
    expect(await edit(couple, letterId, { deliverAt: at })).toMatchObject({ delivery_kind: "at", deliver_at: at });

    await moveTo(couple.first, couple, HOME);
    expect((await rowOf(t, letterId)).state).toBe("sealed");
    await runJobsUntil(t, at);
    expect((await rowOf(t, letterId)).state).toBe("delivered");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await arrivedPushes(t)).toHaveLength(1);
  });

  test("after any back and forth between a time and the next meeting it arrives once, by one path", async () => {
    const { t, couple } = await sharingCouple();
    const first = "2026-11-11T09:00:00.000Z";
    const second = "2026-11-11T10:00:00.000Z";
    const { letterId } = await send(t, couple, { delivery: "at", deliverAt: first });
    await edit(couple, letterId, { delivery: "together" });
    await edit(couple, letterId, { deliverAt: second });
    await edit(couple, letterId, { delivery: "together", body: NEW_WORDS });

    // Both timed jobs and the time sweep pass by, and the letter still waits for the meeting.
    await runJobsUntil(t, "2026-11-11T10:01:00.000Z");
    await t.mutation(internal.letters.deliver_due_letters, {});
    expect((await rowOf(t, letterId)).state).toBe("sealed");

    // The partner's phone reports where she is now, then the author's phone shows them together.
    await moveTo(couple.second, couple, HOME);
    expect((await rowOf(t, letterId)).state).toBe("sealed");
    await moveTo(couple.first, couple, HOME);
    const delivered = (await rowOf(t, letterId)).delivered_at;
    expect(delivered).toBeDefined();
    await moveTo(couple.first, couple, HOME);
    await t.mutation(internal.letters.deliver_due_letters, {});
    await t.mutation(internal.letters.sweep_letters_for_visits, {});
    await t.mutation(internal.letters.deliver_letter, { letter_id: letterId });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await rowOf(t, letterId)).delivered_at).toBe(delivered);
    expect(await arrivedPushes(t)).toHaveLength(1);
    expect((await open(couple.second, letterId))?.body).toBe(NEW_WORDS);
  });

  test("moved from the next meeting to a time and back, the old time's job does not deliver it", async () => {
    const { t, couple } = await sharingCouple();
    const at = "2026-11-11T09:00:00.000Z";
    const { letterId } = await send(t, couple, { delivery: "together" });
    await edit(couple, letterId, { deliverAt: at });
    await edit(couple, letterId, { delivery: "together" });
    await runJobsUntil(t, "2026-11-11T09:01:00.000Z");
    await t.mutation(internal.letters.deliver_due_letters, {});
    expect((await rowOf(t, letterId)).state).toBe("sealed");
    await moveTo(couple.second, couple, HOME);
    await moveTo(couple.first, couple, HOME);
    expect((await rowOf(t, letterId)).state).toBe("delivered");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await arrivedPushes(t)).toHaveLength(1);
  });
});
