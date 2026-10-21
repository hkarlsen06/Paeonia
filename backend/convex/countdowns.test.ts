import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { createCouple, createSignedInUser, newTest, type TestCouple } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const CLIENT_ID = "00000000-0000-0000-0000-00000000c001";
let sequence = 0;
const op = (clientId = CLIENT_ID) => ({
  p_client_operation_id: newUuid(),
  p_client_id: clientId,
  p_client_sequence: ++sequence,
  p_local_created_at: NOW,
});

type Member = TestCouple["first"];

const save = (user: Member, id: string, title: string, date: string, operation = op(), repeatsYearly = false) =>
  user.as.mutation(api.countdowns.save_countdown, {
    p_countdown_id: id,
    p_title: title,
    p_target_date: date,
    p_repeats_yearly: repeatsYearly,
    ...operation,
  });
const remove = (user: Member, id: string, operation = op()) =>
  user.as.mutation(api.countdowns.delete_countdown, { p_countdown_id: id, ...operation });
const setBirthday = (user: Member, userId: string, birthday: string | null, operation = op()) =>
  user.as.mutation(api.countdowns.set_birthday, { p_user_id: userId, p_birthday: birthday, ...operation });
const read = (user: Member) => user.as.query(api.countdowns.get_countdowns, {});

async function failure(promise: Promise<unknown>) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  return error?.data;
}

describe("save_countdown", () => {
  test("creates and edits a countdown both partners see, soonest first", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const trip = newUuid();
    const concert = newUuid();

    const saved = await save(couple.first, trip, "  Trip to Bergen ", "2026-12-20");
    expect(saved).toMatchObject({ id: trip, title: "Trip to Bergen", target_date: "2026-12-20" });
    await save(couple.second, concert, "Concert", "2026-11-02");

    const seen = await read(couple.second);
    expect(seen.couple_id).toBe(couple.coupleId);
    expect(seen.countdowns.map((row) => row.title)).toEqual(["Concert", "Trip to Bergen"]);

    // The partner edits the first partner's countdown.
    await save(couple.second, trip, "Bergen!", "2026-12-21");
    expect((await read(couple.first)).countdowns.find((row) => row.id === trip)).toMatchObject({
      title: "Bergen!",
      target_date: "2026-12-21",
      created_by_user_id: couple.first.userId,
    });
  });

  test("a countdown can repeat every year, and an edit can turn that off", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();

    expect(await save(couple.first, id, "The day we met", "2023-06-12", op(), true)).toMatchObject({
      id,
      target_date: "2023-06-12",
      repeats_yearly: true,
    });
    expect((await read(couple.second)).countdowns[0]).toMatchObject({ repeats_yearly: true });

    expect(await save(couple.second, id, "The day we met", "2023-06-12")).toMatchObject({ repeats_yearly: false });
    expect((await read(couple.first)).countdowns[0]).toMatchObject({ repeats_yearly: false });
  });

  test("accepts an uppercase id from the phone and stores it lowercase", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await save(couple.first, id.toUpperCase(), "Trip", "2026-12-20");
    expect((await read(couple.first)).countdowns.map((row) => row.id)).toEqual([id]);
  });

  test("rejects an empty title and an invalid date", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await failure(save(couple.first, newUuid(), "   ", "2026-12-20"))).toMatchObject({ code: "23514" });
    expect(await failure(save(couple.first, newUuid(), "x".repeat(81), "2026-12-20"))).toMatchObject({ code: "23514" });
    expect(await failure(save(couple.first, newUuid(), "Trip", "2026-02-30"))).toMatchObject({ code: "22007" });
    expect((await read(couple.first)).countdowns).toEqual([]);
  });

  test("a late retry does not overwrite a newer edit from the same phone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await save(couple.first, id, "Trip", "2026-12-20");
    const older = op();
    const newer = op();
    await save(couple.first, id, "Newest", "2026-12-24", newer);
    expect(await save(couple.first, id, "Older", "2026-12-22", older)).toMatchObject({ title: "Newest" });
    expect((await read(couple.first)).countdowns[0]).toMatchObject({ title: "Newest", target_date: "2026-12-24" });
  });

  test("a create whose first send failed stays deleted after the delete behind it went through", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    const create = op();
    // The create never reached the server. The delete queued after it did.
    expect(await remove(couple.first, id)).toBeNull();
    expect(await save(couple.first, id, "Trip", "2026-12-20", create)).toBeNull();
    expect((await read(couple.first)).countdowns).toEqual([]);
  });

  test("a replay returns the countdown as it is now, not the stored answer", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    const create = op();
    await save(couple.first, id, "Trip", "2026-12-20", create);
    await save(couple.second, id, "Bergen", "2026-12-21");
    expect(await save(couple.first, id, "Trip", "2026-12-20", create)).toMatchObject({ title: "Bergen" });
    await remove(couple.second, id);
    expect(await save(couple.first, id, "Trip", "2026-12-20", create)).toBeNull();
  });

  test("a save after a delete does not bring the countdown back", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await save(couple.first, id, "Trip", "2026-12-20");
    await remove(couple.second, id);
    expect(await save(couple.first, id, "Trip again", "2026-12-20")).toBeNull();
    expect((await read(couple.first)).countdowns).toEqual([]);
  });

  test("caps a couple at 50 countdowns", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (let index = 0; index < 50; index += 1) await save(couple.first, newUuid(), `Day ${index}`, "2026-12-20");
    expect(await failure(save(couple.first, newUuid(), "One more", "2026-12-20"))).toMatchObject({ code: "23514" });
    // A deleted one frees a place.
    const [first] = (await read(couple.first)).countdowns;
    await remove(couple.first, first.id);
    await save(couple.first, newUuid(), "One more", "2026-12-20");
  });

  test("needs an entitled couple and never reaches another couple's countdown", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const loner = await createSignedInUser(t, { name: "Loner" });
    const id = newUuid();
    await save(couple.first, id, "Trip", "2026-12-20");

    expect(await failure(save(loner, newUuid(), "Trip", "2026-12-20"))).toMatchObject({ code: "42501" });
    expect(await failure(read(loner))).toMatchObject({ code: "42501" });
    const unentitled = await createCouple(t, { entitled: false });
    expect(await failure(read(unentitled.first))).toMatchObject({ code: "42501" });

    expect(await failure(save(other.first, id, "Mine now", "2026-12-20"))).toMatchObject({ code: "42501" });
    expect(await failure(remove(other.first, id))).toMatchObject({ code: "42501" });
    expect((await read(couple.first)).countdowns[0].title).toBe("Trip");
    expect((await read(other.first)).countdowns).toEqual([]);
  });
});

describe("delete_countdown", () => {
  test("hides the countdown for both partners, and a repeat is fine", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await save(couple.first, id, "Trip", "2026-12-20");
    expect(await remove(couple.second, id)).toBeNull();
    expect(await remove(couple.second, id)).toBeNull();
    expect(await remove(couple.second, newUuid())).toBeNull();
    expect((await read(couple.first)).countdowns).toEqual([]);
  });
});

describe("set_birthday", () => {
  test("either partner sets either birthday, and removing one clears it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await setBirthday(couple.first, couple.first.userId, "2000-03-14")).toEqual({
      user_id: couple.first.userId,
      birthday: "2000-03-14",
    });
    await setBirthday(couple.first, couple.second.userId.toUpperCase(), "2001-07-01");

    const birthdays = (await read(couple.second)).birthdays;
    expect(birthdays).toHaveLength(2);
    expect(birthdays).toEqual(
      expect.arrayContaining([
        { user_id: couple.first.userId, birthday: "2000-03-14" },
        { user_id: couple.second.userId, birthday: "2001-07-01" },
      ]),
    );

    expect(await setBirthday(couple.second, couple.second.userId, null)).toEqual({
      user_id: couple.second.userId,
      birthday: null,
    });
    expect((await read(couple.first)).birthdays).toEqual([{ user_id: couple.first.userId, birthday: "2000-03-14" }]);
  });

  test("refuses a future birthday and someone outside the relationship", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t, { name: "Stranger" });
    // Tomorrow in UTC passes, so a phone ahead of UTC can pick its today.
    await setBirthday(couple.first, couple.first.userId, "2026-10-11");
    expect(await failure(setBirthday(couple.first, couple.first.userId, "2026-10-12"))).toMatchObject({ code: "23514" });
    expect(await failure(setBirthday(couple.first, stranger.userId, "2000-01-01"))).toMatchObject({ code: "42501" });
    expect(await failure(setBirthday(stranger, couple.first.userId, "2000-01-01"))).toMatchObject({ code: "42501" });
  });

  test("a late retry does not overwrite a newer birthday from the same phone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const older = op();
    const newer = op();
    await setBirthday(couple.first, couple.second.userId, "2001-07-02", newer);
    expect(await setBirthday(couple.first, couple.second.userId, "2001-07-01", older)).toEqual({
      user_id: couple.second.userId,
      birthday: "2001-07-02",
    });
  });
});

describe("cleanup", () => {
  test("cleanup and purge delete the couple's countdowns and birthdays, and spare other couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    await save(couple.first, newUuid(), "Trip", "2026-12-20");
    await setBirthday(couple.first, couple.first.userId, "2000-03-14");
    await save(other.first, newUuid(), "Other trip", "2026-12-20");
    await setBirthday(other.first, other.first.userId, "1999-01-01");

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    const left = await t.run((ctx) => ctx.db.query("countdowns").collect());
    expect(left.map((countdown) => countdown.couple_id)).toEqual([other.coupleId]);
    const members = await t.run((ctx) => ctx.db.query("couple_members").collect());
    expect(members.filter((member) => member.birthday !== undefined).map((member) => member.couple_id)).toEqual([
      other.coupleId,
    ]);

    await t.run((ctx) =>
      ctx.db.insert("countdowns", {
        id: newUuid(),
        couple_id: couple.coupleId,
        title: "Left behind",
        target_date: "2026-12-20",
        created_by_user_id: couple.first.userId,
        last_edited_by_user_id: couple.first.userId,
        created_at: NOW,
        updated_at: NOW,
      }),
    );
    await t.run((ctx) => purgeCoupleContent(ctx, row));
    const afterPurge = await t.run((ctx) => ctx.db.query("countdowns").collect());
    expect(afterPurge.map((countdown) => countdown.couple_id)).toEqual([other.coupleId]);
  });
});
