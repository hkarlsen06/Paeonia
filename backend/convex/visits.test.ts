import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
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

  test("caps a couple at 20 visits that are not over, and visits that ended never count", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (let index = 0; index < 25; index += 1) await saveVisit(couple.first, newUuid(), "2026-09-01", "2026-09-03");
    const ids = Array.from({ length: 19 }, () => newUuid());
    for (const id of ids) await saveVisit(couple.first, id, "2026-11-20", "2026-11-21");
    // Today, 10 October, is the last day of this one, so it is not over yet.
    const lastDay = newUuid();
    await saveVisit(couple.second, lastDay, "2026-10-08", "2026-10-10");

    const full = { code: "23514", message: expect.stringContaining("at most 20 visits") };
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02"))).toMatchObject(full);
    // An ended visit can still be added, and an open one edited, but not one moved out of the past.
    await saveVisit(couple.first, newUuid(), "2026-10-01", "2026-10-09");
    await saveVisit(couple.first, ids[0], "2026-11-21", "2026-11-22");
    const past = newUuid();
    await saveVisit(couple.first, past, "2026-08-01", "2026-08-02");
    expect(await failure(saveVisit(couple.first, past, "2026-12-01", "2026-12-02"))).toMatchObject(full);

    // The next day the visit that ended frees its place.
    vi.setSystemTime(new Date("2026-10-11T12:00:00.000Z"));
    await saveVisit(couple.first, past, "2026-12-01", "2026-12-02");
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02"))).toMatchObject(full);
    await deleteVisit(couple.first, ids[1]);
    await saveVisit(couple.first, newUuid(), "2026-12-01", "2026-12-02");
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

  test("a title is 1 to 80 code points after trimming, so 10 of this emoji fit and 11 do not", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const kiss = "👩‍❤️‍💋‍👨";
    expect(Array.from(kiss)).toHaveLength(8);
    expect(await saveItem(couple.first, newUuid(), kiss.repeat(10))).toMatchObject({ title: kiss.repeat(10) });
    expect(await saveItem(couple.first, newUuid(), ` ${"x".repeat(80)} `)).toMatchObject({ title: "x".repeat(80) });
    for (const title of ["   ", kiss.repeat(11), "x".repeat(81)]) {
      expect(await failure(saveItem(couple.first, newUuid(), title))).toMatchObject({
        code: "23514",
        message: "list item title must be 1 to 80 characters",
      });
    }
    expect(await failure(setDone(couple.first, newUuid(), true, op(), kiss.repeat(11)))).toMatchObject({
      code: "23514",
    });
    expect((await read(couple.first)).items).toHaveLength(2);
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
});
