import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { MAX_TOGETHER_ITEM_TITLE_CODE_POINTS } from "./lib/visits";
import { cleanupCoupleContent } from "./lib/relationshipCleanup";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const CLIENT_ID = "00000000-0000-0000-0000-00000000c002";
let sequence = 0;
const op = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: CLIENT_ID,
  p_client_sequence: ++sequence,
  p_local_created_at: NOW,
});

type Member = TestCouple["first"];
type Place = { name: string; latitude: number; longitude: number; city?: string | null; country_code?: string | null };

const bergen: Place = { name: "Bryggen", latitude: 60.397, longitude: 5.324, city: "Bergen", country_code: "NO" };

const saveVisit = (user: Member, id: string, start: string, end: string, place: Place | null = null, operation = op()) =>
  user.as.mutation(api.visits.save_visit, {
    p_visit_id: id,
    p_start_date: start,
    p_end_date: end,
    p_place: place,
    ...operation,
  });
const editVisit = (
  user: Member,
  id: string,
  fields: { p_start_date?: string; p_end_date?: string; p_place?: Place | null },
) => user.as.mutation(api.visits.save_visit, { p_visit_id: id, ...fields, ...op() });
const deleteVisit = (user: Member, id: string) => user.as.mutation(api.visits.delete_visit, { p_visit_id: id, ...op() });
const saveItem = (user: Member, id: string, title: string, operation = op()) =>
  user.as.mutation(api.visits.save_together_item, { p_item_id: id, p_title: title, ...operation });
const setDone = (user: Member, id: string, done: boolean, operation = op(), title = "Ice skating") =>
  user.as.mutation(api.visits.set_together_item_done, { p_item_id: id, p_title: title, p_done: done, ...operation });
const deleteItem = (user: Member, id: string) =>
  user.as.mutation(api.visits.delete_together_item, { p_item_id: id, ...op() });
const read = (user: Member) => user.as.query(api.visits.get_visits, {});

async function failure(promise: Promise<unknown>) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  return error?.data;
}

/** A couple, someone without a couple, and a couple whose access ended. */
async function outsiders(t: TestConvex) {
  return {
    stranger: await createCouple(t),
    loner: await createSignedInUser(t, { name: "Loner" }),
    unentitled: await createCouple(t, { entitled: false }),
  };
}

describe("get_visits", () => {
  test("both partners see the visits earliest first and the list oldest first", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const later = newUuid();
    const sooner = newUuid();
    await saveVisit(couple.first, later, "2026-12-20", "2026-12-27");
    await saveVisit(couple.second, sooner, "2026-11-20", "2026-11-23", bergen);
    const first = newUuid();
    await saveItem(couple.second, first, "Ice skating");
    vi.setSystemTime(new Date("2026-10-10T12:01:00.000Z"));
    await saveItem(couple.first, newUuid(), "  Cook ramen ");

    const seen = await read(couple.first);
    expect(seen.couple_id).toBe(couple.coupleId);
    expect(seen.visits.map((visit) => visit.id)).toEqual([sooner, later]);
    expect(seen.visits[0]).toMatchObject({
      start_date: "2026-11-20",
      end_date: "2026-11-23",
      place: bergen,
      created_by_user_id: couple.second.userId,
    });
    expect(seen.visits[1].place).toBeNull();
    expect(seen.items.map((item) => item.title)).toEqual(["Ice skating", "Cook ramen"]);
    expect(seen.items[0]).toMatchObject({ id: first, added_by_user_id: couple.second.userId, done_at: null });
  });

  test("sends every visit that is not over and the 10 that ended last, without a bound on the couple's history", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const ended = [];
    for (let day = 1; day <= 15; day += 1) {
      const date = `2026-09-${String(day).padStart(2, "0")}`;
      ended.push(date);
      await saveVisit(couple.first, newUuid(), date, date);
    }
    for (let index = 0; index < 20; index += 1) await saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-22");

    const visits = (await read(couple.second)).visits;
    expect(visits).toHaveLength(30);
    expect(visits.slice(0, 10).map((visit) => visit.start_date)).toEqual(ended.slice(5));
    expect(visits.slice(10).every((visit) => visit.start_date === "2026-11-20")).toBe(true);
  });

  test("refuses someone outside the couple and someone without access", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-23");
    const { stranger, loner, unentitled } = await outsiders(t);

    expect((await read(stranger.first)).visits).toEqual([]);
    expect(await failure(read(loner))).toMatchObject({ code: "42501" });
    expect(await failure(read(unentitled.first))).toMatchObject({ code: "42501" });
  });
});

describe("save_visit", () => {
  test("either partner edits a visit, and a visit in the past is fine", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    expect(await saveVisit(couple.first, id.toUpperCase(), "2026-09-01", "2026-09-03")).toMatchObject({
      id,
      start_date: "2026-09-01",
    });
    expect(await saveVisit(couple.second, id, "2026-11-20", "2026-11-20", bergen)).toMatchObject({
      start_date: "2026-11-20",
      end_date: "2026-11-20",
      place: bergen,
      created_by_user_id: couple.first.userId,
    });
    // An edit without a place removes it.
    expect(await saveVisit(couple.first, id, "2026-11-20", "2026-11-22")).toMatchObject({ place: null });
  });

  test("refuses a last day before the first day, and a bad place", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-19"))).toMatchObject({
      code: "23514",
    });
    expect(
      await failure(saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-21", { ...bergen, latitude: 91 })),
    ).toMatchObject({ code: "23514" });
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-11-31", "2026-12-01"))).toMatchObject({
      code: "22007",
    });
    expect((await read(couple.first)).visits).toEqual([]);
  });

  test("refuses a date before 2000 or after 2100, and a visit longer than 366 days", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const range = { code: "23514", message: expect.stringContaining("2000-01-01 to 2100-12-31, 366 days at most") };
    expect(await failure(saveVisit(couple.first, newUuid(), "1999-12-31", "2000-01-02"))).toMatchObject(range);
    expect(await failure(saveVisit(couple.first, newUuid(), "2100-12-30", "2101-01-01"))).toMatchObject(range);
    expect(await failure(saveVisit(couple.first, newUuid(), "2027-01-01", "2028-01-02"))).toMatchObject(range);
    await saveVisit(couple.first, newUuid(), "2000-01-01", "2000-01-02");
    await saveVisit(couple.first, newUuid(), "2100-12-30", "2100-12-31");
    await saveVisit(couple.first, newUuid(), "2027-01-01", "2028-01-01");
  });

  test("an edit keeps the fields it leaves out, so both partners keep their change", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveVisit(couple.first, id, "2026-11-20", "2026-11-23", bergen);

    await editVisit(couple.second, id, { p_start_date: "2026-11-19" });
    expect(await editVisit(couple.first, id, { p_end_date: "2026-11-25" })).toMatchObject({
      start_date: "2026-11-19",
      end_date: "2026-11-25",
      place: bergen,
    });
    expect(await editVisit(couple.second, id, { p_place: null })).toMatchObject({
      start_date: "2026-11-19",
      end_date: "2026-11-25",
      place: null,
    });
    // The two edits together put the last day before the first, so the later one is refused.
    expect(await failure(editVisit(couple.first, id, { p_start_date: "2026-11-30" }))).toMatchObject({
      code: "23514",
    });
    expect(await failure(editVisit(couple.first, newUuid(), { p_place: bergen }))).toMatchObject({
      code: "23514",
      message: expect.stringContaining("needs its first and last day"),
    });
  });

  test("a late retry does not overwrite a newer edit, and a deleted visit stays deleted", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    const older = op();
    const newer = op();
    await saveVisit(couple.first, id, "2026-11-20", "2026-11-23", null, newer);
    expect(await saveVisit(couple.first, id, "2026-11-01", "2026-11-02", null, older)).toMatchObject({
      start_date: "2026-11-20",
    });
    expect(await deleteVisit(couple.second, id)).toBeNull();
    expect(await saveVisit(couple.first, id, "2026-11-20", "2026-11-23")).toBeNull();
    expect((await read(couple.first)).visits).toEqual([]);
  });

  test("caps a couple at 20 visits that may not be over on some phone, and visits that ended never count", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (let index = 0; index < 25; index += 1) await saveVisit(couple.first, newUuid(), "2026-09-01", "2026-09-03");
    const ids = Array.from({ length: 19 }, () => newUuid());
    for (const id of ids) await saveVisit(couple.first, id, "2026-11-20", "2026-11-21");
    // At noon UTC on 10 October it is still 9 October on a phone 12 hours behind, so this one counts.
    const lastDay = newUuid();
    await saveVisit(couple.second, lastDay, "2026-10-08", "2026-10-09");

    const full = { code: "23514", message: expect.stringContaining("at most 20 visits") };
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02"))).toMatchObject(full);
    // An ended visit can still be added, and a counted one edited, but not one moved out of the past.
    await saveVisit(couple.first, newUuid(), "2026-10-01", "2026-10-08");
    await saveVisit(couple.first, ids[0], "2026-11-21", "2026-11-22");
    await saveVisit(couple.second, lastDay, "2026-12-08", "2026-12-09");
    const past = newUuid();
    await saveVisit(couple.first, past, "2026-08-01", "2026-08-02");
    expect(await failure(saveVisit(couple.first, past, "2026-12-01", "2026-12-02"))).toMatchObject(full);

    await deleteVisit(couple.first, ids[1]);
    await saveVisit(couple.first, past, "2026-12-01", "2026-12-02");
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02"))).toMatchObject(full);
  });

  test("a visit stops counting once its last day is over on every phone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (let index = 0; index < 19; index += 1) await saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-21");
    await saveVisit(couple.first, newUuid(), "2026-10-08", "2026-10-09");
    const full = { code: "23514", message: expect.stringContaining("at most 20 visits") };

    // 23:00 UTC on 10 October is still 9 October in UTC-12.
    vi.setSystemTime(new Date("2026-10-10T23:00:00.000Z"));
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02"))).toMatchObject(full);
    // 9 October is over everywhere once it is 11 October in UTC.
    vi.setSystemTime(new Date("2026-10-11T00:00:00.000Z"));
    await saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02");
  });

  // 20:00 UTC is 22:00 on 10 October in Oslo and 07:00 on the 11th in Sydney. 10:30 UTC is 23:30 on
  // 9 October in Pago Pago and 00:30 on the 11th in Kiritimati, two calendar days apart.
  test.each([
    { now: "2026-10-10T20:00:00.000Z", behind: "Europe/Oslo", ahead: "Australia/Sydney", behindToday: "2026-10-10" },
    { now: "2026-10-10T10:30:00.000Z", behind: "Pacific/Pago_Pago", ahead: "Pacific/Kiritimati", behindToday: "2026-10-09" },
  ])("$behind and $ahead cannot get past 20 visits not over on either day, and get_visits sends every one", async ({
    now,
    behind,
    ahead,
    behindToday,
  }) => {
    vi.setSystemTime(new Date(now));
    const t = newTest();
    const couple = await createCouple(t, { timeZones: [behind, ahead] });
    const [late, early] = [couple.first, couple.second];
    const aheadYesterday = "2026-10-10";
    // These are over for the partner ahead and not for the one behind.
    const overAhead = Array.from({ length: 11 }, () => newUuid());
    for (const id of overAhead) await saveVisit(late, id, aheadYesterday, aheadYesterday).catch(() => null);
    for (let index = 0; index < 12; index += 1) {
      await saveVisit(early, newUuid(), aheadYesterday, aheadYesterday).catch(() => null);
    }
    for (let index = 0; index < 20; index += 1) {
      await saveVisit(early, newUuid(), "2026-12-01", "2026-12-02").catch(() => null);
    }
    const [next, ...rest] = overAhead;
    await saveVisit(late, next, "2026-10-12", "2026-10-13").catch(() => null);
    for (const id of rest) await saveVisit(late, id, "2026-12-10", "2026-12-11").catch(() => null);

    const notOverBehind = await t.run(async (ctx) =>
      (await ctx.db.query("visits").collect()).filter((row) => row.end_date >= behindToday).map((row) => row.id),
    );
    expect(notOverBehind.length).toBeLessThanOrEqual(20);
    for (const partner of [late, early]) {
      expect((await read(partner)).visits.map((visit) => visit.id)).toEqual(expect.arrayContaining(notOverBehind));
    }
  });

  test("partners in Oslo and Los Angeles get the same answer for the same new visit", async () => {
    // 05:00 UTC is 07:00 on 10 October in Oslo and 22:00 on 9 October in Los Angeles.
    vi.setSystemTime(new Date("2026-10-10T05:00:00.000Z"));
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "America/Los_Angeles"] });
    for (let index = 0; index < 19; index += 1) await saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02");
    await saveVisit(couple.second, newUuid(), "2026-10-08", "2026-10-09");

    const answers = [];
    for (const partner of [couple.first, couple.second]) {
      answers.push((await failure(saveVisit(partner, newUuid(), "2026-12-10", "2026-12-11")))?.code ?? "saved");
    }
    expect(answers).toEqual(["23514", "23514"]);
  });

  test("refuses someone outside the couple and someone without access", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveVisit(couple.first, id, "2026-11-20", "2026-11-23");
    const { stranger, loner, unentitled } = await outsiders(t);

    expect(await failure(saveVisit(stranger.first, id, "2026-01-01", "2026-01-02"))).toMatchObject({ code: "42501" });
    expect(await failure(saveVisit(loner, newUuid(), "2026-11-20", "2026-11-23"))).toMatchObject({ code: "42501" });
    expect(await failure(saveVisit(unentitled.first, newUuid(), "2026-11-20", "2026-11-23"))).toMatchObject({
      code: "42501",
    });
    expect((await read(couple.first)).visits[0]).toMatchObject({ start_date: "2026-11-20" });
  });
});

describe("delete_visit", () => {
  test("hides the visit for both partners and keeps the list", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveVisit(couple.first, id, "2026-11-20", "2026-11-23");
    await saveItem(couple.first, newUuid(), "Ice skating");
    expect(await deleteVisit(couple.second, id)).toBeNull();
    expect(await deleteVisit(couple.second, id)).toBeNull();
    const seen = await read(couple.first);
    expect(seen.visits).toEqual([]);
    expect(seen.items.map((item) => item.title)).toEqual(["Ice skating"]);
  });

  test("refuses someone outside the couple and someone without access", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveVisit(couple.first, id, "2026-11-20", "2026-11-23");
    const { stranger, loner, unentitled } = await outsiders(t);

    expect(await failure(deleteVisit(stranger.first, id))).toMatchObject({ code: "42501" });
    expect(await failure(deleteVisit(loner, id))).toMatchObject({ code: "42501" });
    expect(await failure(deleteVisit(unentitled.first, id))).toMatchObject({ code: "42501" });
    expect((await read(couple.first)).visits).toHaveLength(1);
  });
});

describe("save_together_item", () => {
  test("adds an item once, keeps its title, and caps the list at 100", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    expect(await saveItem(couple.first, id, " Ice skating ")).toMatchObject({ id, title: "Ice skating" });
    expect(await saveItem(couple.second, id, "Ice skating at Frogner")).toMatchObject({
      title: "Ice skating",
      added_by_user_id: couple.first.userId,
    });

    for (let index = 1; index < 100; index += 1) await saveItem(couple.first, newUuid(), `Idea ${index}`);
    expect(await failure(saveItem(couple.first, newUuid(), "One more"))).toMatchObject({ code: "23514" });
    await deleteItem(couple.first, id);
    await saveItem(couple.first, newUuid(), "One more");
  });

  test("a title counts code points after trimming, as the app does, so a long emoji uses up several", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const kiss = "👩‍❤️‍💋‍👨";
    const perKiss = Array.from(kiss).length;
    const full = kiss.repeat(Math.floor(MAX_TOGETHER_ITEM_TITLE_CODE_POINTS / perKiss)) +
      "x".repeat(MAX_TOGETHER_ITEM_TITLE_CODE_POINTS % perKiss);
    expect(await saveItem(couple.first, newUuid(), ` ${full} `)).toMatchObject({ title: full });
    for (const title of ["   ", `${full}x`]) {
      expect(await failure(saveItem(couple.first, newUuid(), title))).toMatchObject({ code: "23514" });
    }
    expect(await failure(setDone(couple.first, newUuid(), true, op(), `${full}x`))).toMatchObject({ code: "23514" });
    expect((await read(couple.first)).items).toHaveLength(1);
  });

  test("a deleted item stays deleted", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveItem(couple.first, id, "Ice skating");
    await deleteItem(couple.second, id);
    expect(await saveItem(couple.first, id, "Ice skating")).toBeNull();
    expect((await read(couple.first)).items).toEqual([]);
  });

  test("refuses someone outside the couple and someone without access", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveItem(couple.first, id, "Ice skating");
    const { stranger, loner, unentitled } = await outsiders(t);

    expect(await failure(saveItem(stranger.first, id, "Mine now"))).toMatchObject({ code: "42501" });
    expect(await failure(saveItem(loner, newUuid(), "Ice skating"))).toMatchObject({ code: "42501" });
    expect(await failure(saveItem(unentitled.first, newUuid(), "Ice skating"))).toMatchObject({ code: "42501" });
    expect((await read(couple.first)).items.map((item) => item.title)).toEqual(["Ice skating"]);
  });
});

describe("set_together_item_done", () => {
  test("a tick shows for both partners with who ticked it, and an untick clears it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveItem(couple.first, id, "Ice skating");
    const ticked = await setDone(couple.second, id, true);
    expect(ticked).toMatchObject({ done_by_user_id: couple.second.userId });
    expect(ticked?.done_at).toEqual(expect.any(String));
    // Ticking again keeps the first tick.
    vi.setSystemTime(new Date("2026-10-11T12:00:00.000Z"));
    expect(await setDone(couple.first, id, true)).toMatchObject({ done_by_user_id: couple.second.userId });
    expect((await read(couple.first)).items[0]).toMatchObject({ done_at: ticked?.done_at });

    expect(await setDone(couple.first, id, false)).toMatchObject({ done_at: null, done_by_user_id: null });
  });

  test("a late retry does not undo a newer tick from the same phone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveItem(couple.first, id, "Ice skating");
    const older = op();
    const newer = op();
    await setDone(couple.first, id, true, newer);
    expect(await setDone(couple.first, id, false, older)).toMatchObject({ done_by_user_id: couple.first.userId });
  });

  test("refuses someone outside the couple and someone without access", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveItem(couple.first, id, "Ice skating");
    const { stranger, loner, unentitled } = await outsiders(t);

    expect(await failure(setDone(stranger.first, id, true))).toMatchObject({ code: "42501" });
    expect(await failure(setDone(loner, id, true))).toMatchObject({ code: "42501" });
    expect(await failure(setDone(unentitled.first, id, true))).toMatchObject({ code: "42501" });
    expect((await read(couple.first)).items[0].done_at).toBeNull();
  });
});

describe("delete_together_item", () => {
  test("hides the item for both partners, and a repeat is fine", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveItem(couple.first, id, "Ice skating");
    expect(await deleteItem(couple.second, id)).toBeNull();
    expect(await deleteItem(couple.second, id)).toBeNull();
    expect((await read(couple.first)).items).toEqual([]);
  });

  test("refuses someone outside the couple and someone without access", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    await saveItem(couple.first, id, "Ice skating");
    const { stranger, loner, unentitled } = await outsiders(t);

    expect(await failure(deleteItem(stranger.first, id))).toMatchObject({ code: "42501" });
    expect(await failure(deleteItem(loner, id))).toMatchObject({ code: "42501" });
    expect(await failure(deleteItem(unentitled.first, id))).toMatchObject({ code: "42501" });
    expect((await read(couple.first)).items).toHaveLength(1);
  });
});

describe("writes that arrive in another order than the phone made them", () => {
  test("a tick that arrives before its add adds the item ticked, and the late add changes nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    const add = op();
    const tick = op();
    expect(await setDone(couple.first, id, true, tick)).toMatchObject({ title: "Ice skating", done_by_user_id: couple.first.userId });
    expect(await saveItem(couple.first, id, "Ice skating", add)).toMatchObject({ done_by_user_id: couple.first.userId });
    expect((await read(couple.second)).items).toMatchObject([{ id, title: "Ice skating", done_at: expect.any(String) }]);
  });

  test("an add, a tick and an untick sent last to first end unticked", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    const [add, tick, untick] = [op(), op(), op()];
    await setDone(couple.first, id, false, untick);
    await setDone(couple.first, id, true, tick);
    await saveItem(couple.first, id, "Ice skating", add);
    expect((await read(couple.first)).items).toMatchObject([{ id, done_at: null }]);
  });

  test("a delete that arrives first keeps the item deleted when its add and tick come later", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    const [add, tick] = [op(), op()];
    expect(await deleteItem(couple.first, id)).toBeNull();
    expect(await setDone(couple.first, id, true, tick)).toBeNull();
    expect(await saveItem(couple.first, id, "Ice skating", add)).toBeNull();
    expect((await read(couple.first)).items).toEqual([]);
  });

  test("a visit edit that arrives before the visit's create wins, and a delete that arrives first wins", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const edited = newUuid();
    const [create, edit] = [op(), op()];
    await saveVisit(couple.first, edited, "2026-11-21", "2026-11-25", bergen, edit);
    expect(await saveVisit(couple.first, edited, "2026-11-20", "2026-11-23", null, create)).toMatchObject({
      start_date: "2026-11-21",
      place: bergen,
    });

    const deleted = newUuid();
    const created = op();
    expect(await deleteVisit(couple.first, deleted)).toBeNull();
    expect(await saveVisit(couple.first, deleted, "2026-11-20", "2026-11-23", null, created)).toBeNull();
    expect((await read(couple.first)).visits.map((visit) => visit.id)).toEqual([edited]);
  });
});

describe("cleanup", () => {
  test("the relationship cleanup deletes the couple's visits and list, and spares other couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    await saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-23");
    await saveItem(couple.first, newUuid(), "Ice skating");
    await saveVisit(other.first, newUuid(), "2026-11-20", "2026-11-23");
    await saveItem(other.first, newUuid(), "Cook ramen");

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    expect((await t.run((ctx) => ctx.db.query("visits").collect())).map((visit) => visit.couple_id)).toEqual([
      other.coupleId,
    ]);
    expect((await t.run((ctx) => ctx.db.query("together_list_items").collect())).map((item) => item.couple_id)).toEqual([
      other.coupleId,
    ]);
  });

  test("a couple with a long history is cleaned up in chunks", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await insertVisits(t, couple, 450, "2025-01-01");

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    expect((await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW, { left: 400 }))).done).toBe(false);
    expect((await t.run((ctx) => ctx.db.query("visits").collect())).length).toBe(50);
    expect((await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW, { left: 400 }))).done).toBe(true);
    expect(await t.run((ctx) => ctx.db.query("visits").collect())).toEqual([]);
  });
});

describe("Lock Screen", () => {
  test("reads at most 20 visits and still sends the next one", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await insertVisits(t, couple, 200, "2026-10-10");
    const next = newUuid();
    await t.run(async (ctx) => {
      await ctx.db.patch((await ctx.db.query("visits").first())!._id, { id: next, end_date: "2026-11-02" });
    });

    const state = await couple.first.as.query(api.widget.get_lock_screen_state, { p_now: NOW });
    expect(state!.dates.visits).toHaveLength(20);
    expect(state!.dates.visits.map((visit) => visit.id)).toContain(next);
  });
});

/** Writes `count` visits on `date` straight to the database, past the cap a save keeps. */
async function insertVisits(t: TestConvex, couple: TestCouple, count: number, date: string) {
  await t.run(async (ctx) => {
    for (let index = 0; index < count; index += 1) {
      await ctx.db.insert("visits", {
        id: newUuid(),
        couple_id: couple.coupleId,
        start_date: date,
        end_date: date,
        together_from: date,
        created_by_user_id: couple.first.userId,
        last_edited_by_user_id: couple.first.userId,
        created_at: NOW,
        updated_at: NOW,
      });
    }
  });
}
