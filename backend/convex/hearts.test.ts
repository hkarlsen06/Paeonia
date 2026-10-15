import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { seenTotalAfterMark } from "./lib/hearts";
import { createCouple, createSignedInUser, newTest, type TestCouple } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

let sequence = 0;
const op = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: "00000000-0000-0000-0000-00000000d201",
  p_client_sequence: ++sequence,
  p_local_created_at: NOW,
});

type Sender = TestCouple["first"];

const send = (user: Sender, count: number, operation = op()) =>
  user.as.mutation(api.hearts.send_hearts, { p_count: count, ...operation });
const markSeen = (user: Sender, total: number) => user.as.mutation(api.hearts.mark_hearts_seen, { p_seen_total: total });
const received = (user: Sender) => user.as.query(api.hearts.get_hearts, {});

async function failure(promise: Promise<unknown>) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  return error?.data;
}

describe("seenTotalAfterMark", () => {
  test("never goes down and never passes the sent total", () => {
    expect(seenTotalAfterMark(0, 5, 14)).toBe(5);
    expect(seenTotalAfterMark(9, 5, 14)).toBe(9);
    expect(seenTotalAfterMark(0, 99, 14)).toBe(14);
    expect(seenTotalAfterMark(14, 14, 14)).toBe(14);
  });
});

describe("send_hearts and get_hearts", () => {
  test("adds to the sender's total and shows the partner the unseen difference", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await received(couple.second)).toEqual({ couple_id: couple.coupleId, received_total: 0, received_seen_total: 0 });

    expect(await send(couple.first, 14)).toEqual({ sent_total: 14 });
    expect(await send(couple.first, 3)).toEqual({ sent_total: 17 });

    expect(await received(couple.second)).toEqual({ couple_id: couple.coupleId, received_total: 17, received_seen_total: 0 });
    // The sender sees nothing of their own hearts, and the partner's row stays separate.
    expect(await received(couple.first)).toEqual({ couple_id: couple.coupleId, received_total: 0, received_seen_total: 0 });
    await send(couple.second, 2);
    expect((await received(couple.first)).received_total).toBe(2);
    expect((await received(couple.second)).received_total).toBe(17);
  });

  test("a replay of the same operation adds the hearts once", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const operation = op();
    expect(await send(couple.first, 5, operation)).toEqual({ sent_total: 5 });
    expect(await send(couple.first, 5, operation)).toEqual({ sent_total: 5 });
    expect((await received(couple.second)).received_total).toBe(5);
    await expect(send(couple.first, 6, operation)).rejects.toThrow(/client operation replay hash mismatch/);
  });

  test("takes 1 to 100 hearts per call", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (const count of [0, -1, 101, 1.5]) {
      expect(await failure(send(couple.first, count))).toEqual({
        code: "23514",
        message: "hearts count must be between 1 and 100",
      });
    }
    expect(await send(couple.first, 100)).toEqual({ sent_total: 100 });
    expect(await send(couple.first, 1)).toEqual({ sent_total: 101 });
  });

  test("fails with 53300 once the sender's calls run out, and the refused call changes nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (let call = 0; call < 60; call += 1) await send(couple.first, 1);
    expect(await failure(send(couple.first, 1))).toEqual({ code: "53300", message: "too many requests: heartsSend" });
    expect((await received(couple.second)).received_total).toBe(60);
    // The partner has their own bucket.
    expect(await send(couple.second, 1)).toEqual({ sent_total: 1 });
    // A token comes back after a minute (120 per hour).
    vi.setSystemTime(new Date(Date.parse(NOW) + 31_000));
    expect(await send(couple.first, 1)).toEqual({ sent_total: 61 });
  });

  test("needs an active entitled couple", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect(await failure(send(loner, 1))).toMatchObject({ code: "42501" });
    expect(await failure(markSeen(loner, 1))).toMatchObject({ code: "42501" });
    expect(await failure(received(loner))).toMatchObject({ code: "42501" });

    const unentitled = await createCouple(t, { entitled: false });
    expect(await failure(send(unentitled.first, 1))).toMatchObject({ code: "42501" });
    expect(await failure(received(unentitled.second))).toMatchObject({ code: "42501" });

    // The refused calls wrote nothing, and a stranger never reaches this couple's hearts.
    await send(couple.first, 4);
    expect(await t.run((ctx) => ctx.db.query("couple_hearts").collect())).toHaveLength(1);
  });

  test("a member whose partner left cannot send", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run(async (ctx) => {
      const member = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.coupleId).eq("user_id", couple.second.userId))
        .unique();
      await ctx.db.patch(member!._id, { status: "left" });
    });
    expect(await failure(send(couple.first, 1))).toEqual({
      code: "42501",
      message: "an active partner is required to send hearts",
    });
    expect(await received(couple.first)).toEqual({ couple_id: couple.coupleId, received_total: 0, received_seen_total: 0 });
  });
});

describe("mark_hearts_seen", () => {
  test("marks the total the app showed, so a heart that arrives mid-animation stays unseen", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await send(couple.first, 14);
    // The recipient's phone started playing 14. Three more arrive before it marks.
    await send(couple.first, 3);

    expect(await markSeen(couple.second, 14)).toEqual({
      couple_id: couple.coupleId,
      received_total: 17,
      received_seen_total: 14,
    });
    expect(await received(couple.second)).toEqual({ couple_id: couple.coupleId, received_total: 17, received_seen_total: 14 });

    expect((await markSeen(couple.second, 17)).received_seen_total).toBe(17);
  });

  test("keeps the larger total for a late retry and caps a total above what was sent", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await send(couple.first, 10);
    await markSeen(couple.second, 10);
    expect((await markSeen(couple.second, 4)).received_seen_total).toBe(10);
    expect((await markSeen(couple.second, 500)).received_seen_total).toBe(10);
    expect(await failure(markSeen(couple.second, -1))).toMatchObject({ code: "23514" });
    expect(await failure(markSeen(couple.second, 2.5))).toMatchObject({ code: "23514" });
  });

  test("a mark writes the recipient's own row and leaves the sender's row alone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await send(couple.first, 6);
    const rows = () => t.run((ctx) => ctx.db.query("couple_hearts").collect());
    const [senderBefore] = await rows();
    await markSeen(couple.second, 4);
    const after = await rows();
    expect(after).toHaveLength(2);
    expect(after.find((row) => row.sender_user_id === couple.first.userId)).toEqual(senderBefore);
    expect(after.find((row) => row.sender_user_id === couple.second.userId)).toMatchObject({ sent_total: 0, seen_total: 4 });
    // Sending later does not disturb the recipient's seen total.
    await send(couple.second, 2);
    expect((await received(couple.second)).received_seen_total).toBe(4);
    expect((await received(couple.first)).received_total).toBe(2);
  });

  test("changes only the partner's row, and the sender's own hearts are not theirs to mark", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await send(couple.first, 6);
    expect(await markSeen(couple.first, 6)).toEqual({ couple_id: couple.coupleId, received_total: 0, received_seen_total: 0 });
    expect((await received(couple.second)).received_seen_total).toBe(0);
  });

  test("an unseen count is zero again after a mark, and a new send makes it grow from there", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await send(couple.first, 8);
    await markSeen(couple.second, 8);
    await send(couple.first, 2);
    const row = await received(couple.second);
    expect(row.received_total - row.received_seen_total).toBe(2);
  });
});

describe("cleanup", () => {
  async function withHearts() {
    const t = newTest();
    const couple = await createCouple(t);
    await send(couple.first, 3);
    await send(couple.second, 4);
    expect(await t.run((ctx) => ctx.db.query("couple_hearts").collect())).toHaveLength(2);
    return { t, couple };
  }

  test("ending the relationship deletes the couple's hearts", async () => {
    const { t, couple } = await withHearts();
    await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.first.userId, "user_left"));
    expect(await t.run((ctx) => ctx.db.query("couple_hearts").collect())).toHaveLength(0);
  });

  test("cleanup and purge delete hearts left behind, and spare other couples", async () => {
    const { t, couple } = await withHearts();
    const other = await createCouple(t);
    await send(other.first, 9);
    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    const left = await t.run((ctx) => ctx.db.query("couple_hearts").collect());
    expect(left.map((heart) => heart.couple_id)).toEqual([other.coupleId]);

    await t.run((ctx) => ctx.db.insert("couple_hearts", {
      couple_id: couple.coupleId,
      sender_user_id: couple.first.userId,
      sent_total: 1,
      seen_total: 0,
      last_sent_at: NOW,
      created_at: NOW,
      updated_at: NOW,
    }));
    await t.run((ctx) => purgeCoupleContent(ctx, row));
    const afterPurge = await t.run((ctx) => ctx.db.query("couple_hearts").collect());
    expect(afterPurge.map((heart) => heart.couple_id)).toEqual([other.coupleId]);
  });
});
