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
const open = (user: TestUser, id: string) => user.as.mutation(api.letters.open_letter, { p_letter_id: id });
const remove = (user: TestUser, id: string) => user.as.mutation(api.letters.delete_letter, { p_letter_id: id, ...op() });
const signImage = (user: TestUser, id: string) => user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: id });
const letterRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("letters").collect());
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
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
    expect((await getLetters(other.second)).letters).toEqual([]);
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
    expect((await getLetters(couple.first)).letters).toEqual([letter]);
  });

  test("trims the note, refuses an empty or too long one, and refuses an unknown template or delivery", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await send(t, couple, { body: "  hello  " })).letter?.body).toBe("hello");
    expect((await send(t, couple, { body: "😀".repeat(2000) })).letter?.body).toBe("😀".repeat(2000));
    expect((await failure(send(t, couple, { body: "   " }))).code).toBe("23514");
    expect((await failure(send(t, couple, { body: "a".repeat(2001) }))).code).toBe("23514");
    expect((await failure(send(t, couple, { template: "secret_admirer" }))).code).toBe("23514");
    expect((await failure(send(t, couple, { delivery: "at" }))).code).toBe("23514");
    expect((await failure(send(t, couple, { delivery: "at", deliverAt: "2027-11-12T20:00:00.000Z" }))).code).toBe("23514");
    expect(await letterRows(t)).toHaveLength(2);
  });

  test("a replay returns the letter as it is now and queues nothing twice", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const letterId = newUuid();
    const operation = op();
    const first = await send(t, couple, { letterId, operation });
    await open(couple.second, letterId);
    const again = await send(t, couple, { letterId, operation });
    expect(again.letter?.state).toBe("opened");
    expect((await send(t, couple, { letterId })).letter?.id).toBe(first.letterId);
    expect(await letterRows(t)).toHaveLength(1);
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
    expect(before.letters).toEqual([]);
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
    expect(after.letters).toHaveLength(1);
    expect(after.letters[0]).toMatchObject({ id: letterId, state: "delivered", body: null, media_asset_id: null, deliver_at: null });
    expect(JSON.stringify(after)).not.toContain(SECRET);
    expect(JSON.stringify(after)).not.toContain(imageId);
    expect((await failure(signImage(couple.second, imageId!))).code).toBe("42501");

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
    expect((await getLetters(couple.second)).letters[0]).toEqual(opened);
    const [row] = await signImage(couple.second, imageId!);
    expect(row.signed_url).toContain("/media?asset=");
    expect((await getLetters(couple.first)).letters[0]).toMatchObject({ state: "opened", opened_at: timestamp(NOW) });

    expect(await open(couple.second, letterId)).toEqual(opened);
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
    const sent = await send(t, couple, { delivery: "morning" });
    expect(sent.letter?.deliver_at).toBe("2026-11-10T23:00:00.000Z");
    const letters = await getLetters(couple.first);
    expect(letters.partner_time_zone_id).toBe("Asia/Tokyo");

    await addDevice(t, couple.second.userId, { timeZone: "America/Los_Angeles" });
    expect((await getLetters(couple.first)).partner_time_zone_id).toBe("America/Los_Angeles");
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
    expect((await getLetters(couple.first)).letters).toEqual([]);

    await t.finishAllScheduledFunctions(vi.runAllTimers);
    const [row] = await letterRows(t);
    expect(row.state).toBe("sealed");
    expect(row.delivered_at).toBeUndefined();
    expect((await getLetters(couple.second)).letters).toEqual([]);
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
    expect((await getLetters(couple.second)).letters).toEqual([]);
    expect((await failure(open(couple.second, letterId))).code).toBe("42501");
    expect(await deliverDuePushes(t)).toEqual([]);
    expect(await remove(couple.first, letterId)).toBeNull();
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
