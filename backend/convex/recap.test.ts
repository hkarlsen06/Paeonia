import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { seedCatalog, textQuestions } from "./daily.setup";
import { getByUuid } from "./lib/db";
import { newUuid } from "./lib/ids";
import { countRecapStep, startRecap } from "./lib/recap";
import { failure } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple } from "./test.setup";

const NOW = "2026-11-11T12:00:00.000Z";
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const ensure = (user: TestCouple["first"]) => user.as.action(api.recap.ensure_anniversary_recap, {});
const recaps = async (user: TestCouple["first"]) => (await user.as.query(api.recap.get_recaps, {})).recaps;
const moments = (user: TestCouple["first"], date = "2026-11-11") =>
  user.as.query(api.recap.get_recap_moments, { p_anniversary_date: date });

async function patchCouple(t: TestConvex, coupleId: string, fields: Partial<Doc<"couples">>) {
  await t.run(async (ctx) => {
    const row = (await getByUuid(ctx, "couples", coupleId))!;
    await ctx.db.patch(row._id, fields);
  });
}

async function readyCouple(options: { entitled?: boolean } = {}) {
  const t = newTest();
  const [question] = await seedCatalog(t, textQuestions(1));
  const couple = await createCouple(t, options);
  await patchCouple(t, couple.coupleId, { started_on: "2025-11-11", created_at: "2025-06-01T08:00:00.000Z" });
  return { t, couple, versionId: question.versionId };
}

async function insertRound(
  t: TestConvex,
  coupleId: string,
  localDate: string,
  versionId: string,
  answeredBy: string[],
): Promise<string> {
  const instanceId = newUuid();
  await t.run(async (ctx) => {
    const dayStart = `${localDate}T00:00:00.000Z`;
    const dayId = newUuid();
    await ctx.db.insert("couple_days", {
      id: dayId,
      couple_id: coupleId,
      local_date: localDate,
      anchor_time_zone_id: "UTC",
      starts_at: dayStart,
      ends_at: new Date(Date.parse(dayStart) + 86_400_000).toISOString(),
      created_at: dayStart,
    });
    await ctx.db.insert("daily_question_instances", {
      id: instanceId,
      couple_day_id: dayId,
      couple_id: coupleId,
      question_id: (await getByUuid(ctx, "question_versions", versionId))!.question_id,
      question_version_id: versionId,
      status: "active",
      created_at: dayStart,
    });
    for (const userId of answeredBy) {
      const answerId = newUuid();
      const answered = `${localDate}T10:00:00.000Z`;
      await ctx.db.insert("daily_question_answers", {
        id: answerId,
        instance_id: instanceId,
        user_id: userId,
        created_at: answered,
        updated_at: answered,
        moderation_status: "visible",
      });
      await ctx.db.insert("daily_answer_text", { answer_id: answerId, couple_id: coupleId, body: "Our walk" });
    }
  });
  return instanceId;
}

async function insertMemory(t: TestConvex, couple: TestCouple, date: string, fields: Partial<Doc<"memories">> = {}) {
  const id = newUuid();
  await t.run(async (ctx) => {
    await ctx.db.insert("memories", {
      id,
      couple_id: couple.coupleId,
      title: `Memory ${date}`,
      memory_date: date,
      created_by_user_id: couple.first.userId,
      last_edited_by_user_id: couple.first.userId,
      revision: 1,
      moderation_status: "visible",
      created_at: NOW,
      updated_at: NOW,
      ...fields,
    });
  });
  return id;
}

async function insertPhotoLink(t: TestConvex, couple: TestCouple, memoryId: string, sortOrder: number) {
  await t.run(async (ctx) => {
    await ctx.db.insert("memory_media", {
      id: newUuid(),
      memory_id: memoryId,
      media_asset_id: newUuid(),
      owner_user_id: couple.second.userId,
      sort_order: sortOrder,
      moderation_status: "visible",
      created_at: NOW,
      updated_at: NOW,
    });
  });
}

async function insertLetter(
  t: TestConvex,
  couple: TestCouple,
  fields: Pick<Doc<"letters">, "state"> & Partial<Doc<"letters">>,
) {
  await t.run(async (ctx) => {
    await ctx.db.insert("letters", {
      id: newUuid(),
      couple_id: couple.coupleId,
      author_user_id: couple.second.userId,
      recipient_user_id: couple.first.userId,
      template_key: "blank",
      body: "{}",
      delivery_kind: "at",
      moderation_status: "visible",
      created_at: "2026-03-01T09:00:00.000Z",
      waits_since: "2026-03-01T09:00:00.000Z",
      ...fields,
    });
  });
}

describe("ensure_anniversary_recap", () => {
  test("counts only what both partners can see, and makes one recap that both read", async () => {
    const { t, couple, versionId } = await readyCouple();
    const { first, second } = couple;
    const both = [first.userId, second.userId];

    await insertRound(t, couple.coupleId, "2026-01-10", versionId, both);
    await insertRound(t, couple.coupleId, "2026-05-02", versionId, both);
    await insertRound(t, couple.coupleId, "2026-05-03", versionId, [second.userId]);
    await insertRound(t, couple.coupleId, "2025-11-10", versionId, both);
    await insertRound(t, couple.coupleId, "2026-11-11", versionId, both);
    const earlier = newUuid();
    await t.run(async (ctx) => {
      await ctx.db.insert("couples", {
        id: earlier,
        pair_id: couple.pairId,
        status: "ended",
        created_by_user_id: first.userId,
        created_at: "2025-01-01T00:00:00.000Z",
        updated_at: NOW,
      });
    });
    await insertRound(t, earlier, "2026-02-02", versionId, both);

    const withPhotos = await insertMemory(t, couple, "2026-07-01");
    await insertPhotoLink(t, couple, withPhotos, 0);
    await insertPhotoLink(t, couple, withPhotos, 1);
    await insertMemory(t, couple, "2026-08-01");
    await insertMemory(t, couple, "2026-08-02", { deleted_at: NOW });
    await insertMemory(t, couple, "2026-08-03", { moderation_status: "hidden" });

    await insertLetter(t, couple, { state: "delivered", delivered_at: "2026-03-02T09:00:00.000Z" });
    await insertLetter(t, couple, { state: "sealed", deliver_at: "2027-01-01T09:00:00.000Z" });
    await insertLetter(t, couple, {
      author_user_id: first.userId,
      recipient_user_id: second.userId,
      state: "opened",
      delivered_at: "2026-04-02T09:00:00.000Z",
      opened_at: "2026-04-02T10:00:00.000Z",
    });

    await t.run(async (ctx) => {
      for (const [start, end] of [["2025-11-05", "2025-11-14"], ["2026-06-01", "2026-06-03"]]) {
        await ctx.db.insert("visits", {
          id: newUuid(),
          couple_id: couple.coupleId,
          start_date: start,
          end_date: end,
          together_from: start,
          first_day_set_at: NOW,
          created_by_user_id: first.userId,
          last_edited_by_user_id: first.userId,
          created_at: NOW,
          updated_at: NOW,
        });
      }
      await ctx.db.insert("stories", {
        id: newUuid(),
        couple_id: couple.coupleId,
        author_user_id: second.userId,
        media_asset_id: newUuid(),
        created_at: "2026-09-09T09:00:00.000Z",
      });
      await ctx.db.insert("game_play_days", { couple_id: couple.coupleId, day: "2026-02-14", user_ids: both });
      await ctx.db.insert("game_play_days", { couple_id: couple.coupleId, day: "2026-02-15", user_ids: [first.userId] });
      for (const [sender, total] of [[first.userId, 40], [second.userId, 2]] as const) {
        await ctx.db.insert("couple_hearts", {
          couple_id: couple.coupleId,
          sender_user_id: sender,
          sent_total: total,
          seen_total: 0,
          created_at: NOW,
          updated_at: NOW,
        });
      }
      await ctx.db.insert("streak_states", {
        couple_id: couple.coupleId,
        current_count: 3,
        longest_count: 21,
        restorable_count: 0,
        updated_at: NOW,
      });
    });

    const recap = await ensure(first);
    expect(recap).toEqual({
      anniversary_date: "2026-11-11",
      years: 1,
      period_start: "2025-11-11",
      period_end: "2026-11-11",
      since_joined: false,
      counted_on: "2026-11-11",
      counts: {
        answered_together: 2,
        drawings: 0,
        memories: 2,
        memory_photos: 2,
        stories: 1,
        letters: 2,
        visits: 2,
        visit_days: 7,
        game_days: 1,
        longest_streak_all_time: 21,
        hearts_all_time: 42,
      },
    });
    expect(await ensure(second)).toEqual(recap);
    expect(await recaps(second)).toEqual([recap]);
    expect(await t.run(async (ctx) => (await ctx.db.query("anniversary_recaps").collect()).length)).toBe(1);
  });

  test("is null outside the days after the anniversary, and for a couple without a start date", async () => {
    const { t, couple } = await readyCouple();
    vi.setSystemTime(new Date("2026-11-25T12:00:00.000Z"));
    expect(await ensure(couple.first)).toBeNull();
    vi.setSystemTime(new Date("2026-11-10T12:00:00.000Z"));
    expect(await ensure(couple.first)).toBeNull();
    vi.setSystemTime(new Date(NOW));
    await patchCouple(t, couple.coupleId, { started_on: undefined });
    expect(await ensure(couple.first)).toBeNull();
    expect(await recaps(couple.first)).toEqual([]);
  });

  test("a couple that joined three months before covers the time since it joined", async () => {
    const { t, couple } = await readyCouple();
    await patchCouple(t, couple.coupleId, { created_at: "2026-08-11T08:00:00.000Z" });
    expect(await ensure(couple.first)).toMatchObject({ period_start: "2026-08-11", since_joined: true });
  });
});

describe("a year too big for one call", () => {
  test("is counted exactly across calls, and both partners get the same numbers", async () => {
    const { t, couple, versionId } = await readyCouple();
    const both = [couple.first.userId, couple.second.userId];
    for (let day = 0; day < 260; day += 1) {
      const date = new Date(Date.parse("2025-12-01T00:00:00.000Z") + day * 86_400_000).toISOString().slice(0, 10);
      await insertRound(t, couple.coupleId, date, versionId, day % 50 === 0 ? [couple.first.userId] : both);
    }
    await t.run(async (ctx) => {
      const canvasId = newUuid();
      await ctx.db.insert("widget_canvases", { id: canvasId, couple_id: couple.coupleId, created_at: NOW, updated_at: NOW });
      for (let n = 0; n < 820; n += 1) {
        const at = new Date(Date.parse("2026-01-01T00:00:00.000Z") + n * 3_600_000).toISOString();
        await ctx.db.insert("widget_drawing_revisions", {
          id: newUuid(),
          canvas_id: canvasId,
          author_user_id: both[n % 2],
          format: "pkdrawing",
          format_version: 1,
          payload_media_asset_id: newUuid(),
          payload_bytes: 1,
          uncompressed_bytes: 1,
          compression: "none",
          renderer_version: 1,
          client_decode_validated_at: at,
          client_renderer_version: "1",
          client_validation_version: "1",
          moderation_status: n === 0 ? "hidden" : "visible",
          created_at: at,
          updated_at: at,
        });
      }
    });

    const made = await ensure(couple.first);
    expect(made?.counts).toMatchObject({ answered_together: 254, drawings: 819 });
    expect(await ensure(couple.second)).toEqual(made);
    expect(await recaps(couple.second)).toEqual([made]);
  }, 60_000);

  test("a recap the anniversary reminder started shows only once it is counted", async () => {
    const { t, couple } = await readyCouple();
    await t.mutation(internal.recap.start_recap, { couple_id: couple.coupleId, today: "2026-11-11", time_zone: "UTC" });
    expect(await recaps(couple.first)).toEqual([]);
    expect(await moments(couple.first)).toEqual([]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await recaps(couple.first)).toMatchObject([{ anniversary_date: "2026-11-11" }]);
    expect(await ensure(couple.second)).toEqual((await recaps(couple.first))[0]);
  });
});

describe("changing the start date", () => {
  const op = () => ({
    p_client_operation_id: newUuid(),
    p_client_id: newUuid(),
    p_client_sequence: 1,
    p_local_created_at: NOW,
  });

  test("moving the day by a few days leaves one recap for the year", async () => {
    const { couple } = await readyCouple();
    await ensure(couple.first);
    vi.setSystemTime(new Date("2026-11-16T12:00:00.000Z"));
    await couple.first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2025-11-15", ...op() });
    await ensure(couple.second);
    expect(await recaps(couple.second)).toMatchObject([{ anniversary_date: "2026-11-15", period_start: "2025-11-15" }]);
  });

  test("fixing the year makes a recap with the right number of years", async () => {
    const { couple } = await readyCouple();
    await ensure(couple.first);
    vi.setSystemTime(new Date("2026-11-12T12:00:00.000Z"));
    await couple.first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2019-11-11", ...op() });
    expect(await ensure(couple.second)).toMatchObject({ years: 7, period_start: "2025-11-11" });
    expect(await recaps(couple.first)).toHaveLength(1);
  });
});

describe("what is counted once", () => {
  test("a memory whose date is moved past where the count stopped is counted once", async () => {
    const { t, couple } = await readyCouple();
    const ids: string[] = [];
    await t.run(async (ctx) => {
      for (let n = 0; n < 450; n += 1) {
        const id = newUuid();
        ids.push(id);
        const day = new Date(Date.parse("2025-11-12T00:00:00.000Z") + Math.floor(n * 0.8) * 86_400_000);
        await ctx.db.insert("memories", {
          id,
          couple_id: couple.coupleId,
          title: `Memory ${n}`,
          memory_date: day.toISOString().slice(0, 10),
          created_by_user_id: couple.first.userId,
          last_edited_by_user_id: couple.first.userId,
          revision: 1,
          moderation_status: "visible",
          created_at: NOW,
          updated_at: NOW,
        });
      }
    });
    const started = (await t.run(async (ctx) => await startRecap(ctx, couple.coupleId, "2026-11-11", "UTC")))!;
    const step = () => t.run(async (ctx) => await countRecapStep(ctx, started._id));
    let row = await step();
    while (row?.counting && row.counting.memories.length === 0) row = await step();
    // The first memory was counted. Its date now moves to a day the count has not reached.
    await t.run(async (ctx) => {
      const memory = (await getByUuid(ctx, "memories", ids[0]))!;
      await ctx.db.patch(memory._id, { memory_date: "2026-11-01" });
    });
    while (row?.counting) row = await step();
    expect(row?.counts.memories).toBe(450);
  }, 120_000);

  test("days that two planned visits share count once", async () => {
    const { t, couple } = await readyCouple();
    await t.run(async (ctx) => {
      for (const [start, end] of [["2026-06-01", "2026-06-05"], ["2026-06-04", "2026-06-08"], ["2026-07-01", "2026-07-01"]]) {
        await ctx.db.insert("visits", {
          id: newUuid(),
          couple_id: couple.coupleId,
          start_date: start,
          end_date: end,
          together_from: start,
          first_day_set_at: NOW,
          created_by_user_id: couple.first.userId,
          last_edited_by_user_id: couple.first.userId,
          created_at: NOW,
          updated_at: NOW,
        });
      }
    });
    expect((await ensure(couple.first))?.counts).toMatchObject({ visits: 3, visit_days: 9 });
  });
});

describe("get_recaps", () => {
  test("comes in pages, newest first, so every recap of a long relationship is there", async () => {
    const { t, couple } = await readyCouple();
    await ensure(couple.first);
    const [made] = await t.run(async (ctx) => await ctx.db.query("anniversary_recaps").collect());
    await t.run(async (ctx) => {
      for (let year = 2016; year <= 2025; year += 1) {
        const { _id: _, _creationTime: __, ...row } = made;
        await ctx.db.insert("anniversary_recaps", { ...row, anniversary_date: `${year}-11-11` });
      }
    });
    const dates: string[] = [];
    let before: string | null = null;
    do {
      const page: { recaps: { anniversary_date: string }[]; next_before: string | null } =
        await couple.second.as.query(api.recap.get_recaps, { p_before: before });
      dates.push(...page.recaps.map((recap) => recap.anniversary_date));
      before = page.next_before;
    } while (before);
    expect(dates).toEqual(Array.from({ length: 11 }, (_, index) => `${2026 - index}-11-11`));
  });
});

describe("get_recap_moments", () => {
  test("shows the picked moments to both, and leaves out one that was deleted since", async () => {
    const { t, couple, versionId } = await readyCouple();
    const memoryId = await insertMemory(t, couple, "2026-07-01");
    const instanceId = await insertRound(t, couple.coupleId, "2026-01-10", versionId, [
      couple.first.userId,
      couple.second.userId,
    ]);
    await ensure(couple.first);

    const shown = await moments(couple.second);
    expect(shown.map((item) => item.kind)).toEqual(["memory", "question"]);
    expect(shown[0]).toMatchObject({ memory: { memory_id: memoryId, title: "Memory 2026-07-01" } });
    expect(shown[1]).toMatchObject({ question: { instance_id: instanceId } });
    expect(await moments(couple.first)).toHaveLength(2);

    await t.run(async (ctx) => {
      const memory = (await getByUuid(ctx, "memories", memoryId))!;
      await ctx.db.patch(memory._id, { deleted_at: NOW });
    });
    expect((await moments(couple.first)).map((item) => item.kind)).toEqual(["question"]);
    expect(await moments(couple.first, "2025-11-11")).toEqual([]);
  });
});

describe("authorization and the end of the relationship", () => {
  test("every function refuses a signed-out caller, a stranger, and an unentitled couple", async () => {
    const { t, couple } = await readyCouple();
    await ensure(couple.first);
    const stranger = await createSignedInUser(t);
    const { couple: unentitled } = await readyCouple({ entitled: false });
    const calls = [
      (user?: TestCouple["first"]) => (user ? ensure(user) : t.action(api.recap.ensure_anniversary_recap, {})),
      (user?: TestCouple["first"]) => (user ? recaps(user) : t.query(api.recap.get_recaps, {})),
      (user?: TestCouple["first"]) =>
        user ? moments(user) : t.query(api.recap.get_recap_moments, { p_anniversary_date: "2026-11-11" }),
    ];
    for (const call of calls) {
      expect(await failure(call())).toMatchObject({ code: "42501" });
      expect(await failure(call(stranger))).toMatchObject({ code: "42501" });
      expect(await failure(call(unentitled.first))).toMatchObject({ code: "42501" });
    }
  });

  test("leaving deletes the couple's recaps", async () => {
    const { t, couple } = await readyCouple();
    await ensure(couple.first);
    await couple.second.as.mutation(api.relationship.leave_relationship, {
      p_client_operation_id: newUuid(),
      p_client_id: newUuid(),
      p_client_sequence: 1,
      p_local_created_at: NOW,
    });
    expect(await t.run(async (ctx) => await ctx.db.query("anniversary_recaps").collect())).toEqual([]);
  });
});
