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
const setDone = (user: Member, id: string, done: boolean, operation = op()) =>
  user.as.mutation(api.visits.set_together_item_done, { p_item_id: id, p_done: done, ...operation });
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

  test("caps a couple at 20 visits, and a deleted one frees a place", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const ids = Array.from({ length: 20 }, () => newUuid());
    for (const id of ids) await saveVisit(couple.first, id, "2026-11-20", "2026-11-21");
    expect(await failure(saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-21"))).toMatchObject({
      code: "23514",
    });
    await deleteVisit(couple.first, ids[0]);
    await saveVisit(couple.first, newUuid(), "2026-11-20", "2026-11-21");
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
  test("adds and renames an item, refuses an empty or long title, and caps the list at 100", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = newUuid();
    expect(await saveItem(couple.first, id, "Ice skating")).toMatchObject({ id, title: "Ice skating" });
    expect(await saveItem(couple.second, id, "Ice skating at Frogner")).toMatchObject({
      title: "Ice skating at Frogner",
      added_by_user_id: couple.first.userId,
    });
    expect(await failure(saveItem(couple.first, newUuid(), "   "))).toMatchObject({ code: "23514" });
    expect(await failure(saveItem(couple.first, newUuid(), "x".repeat(81)))).toMatchObject({ code: "23514" });

    for (let index = 1; index < 100; index += 1) await saveItem(couple.first, newUuid(), `Idea ${index}`);
    expect(await failure(saveItem(couple.first, newUuid(), "One more"))).toMatchObject({ code: "23514" });
    await deleteItem(couple.first, id);
    await saveItem(couple.first, newUuid(), "One more");
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
    expect(await setDone(couple.first, newUuid(), true)).toBeNull();
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
