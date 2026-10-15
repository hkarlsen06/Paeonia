import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { seedCatalog, textQuestions } from "./daily.setup";
import { getByUuid } from "./lib/db";
import { hashString, isOnThisDay, sameDayYearsAgo } from "./lib/lookBack";
import { newUuid } from "./lib/ids";
import { nowIso } from "./lib/time";
import { failure } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple } from "./test.setup";

// "Today" is 2026-10-14 in UTC, so content from 2026-10-07 or earlier is old enough.
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-14T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const NOW = "2026-10-14T12:00:00.000Z";
const lookBackAt = (user: TestCouple["first"], now: string = NOW) => user.as.query(api.lookBack.get_look_back, { p_now: now });
const lookBack = async (user: TestCouple["first"], now: string = NOW) => (await lookBackAt(user, now)).item;

describe("helpers", () => {
  test("sameDayYearsAgo keeps the month and day and skips 29 February in other years", () => {
    expect(sameDayYearsAgo("2026-10-14", 1)).toBe("2025-10-14");
    expect(sameDayYearsAgo("2028-02-29", 4)).toBe("2024-02-29");
    expect(sameDayYearsAgo("2028-02-29", 1)).toBeNull();
  });

  test("isOnThisDay needs an earlier year with the same month and day", () => {
    expect(isOnThisDay("2025-10-14", "2026-10-14")).toBe(true);
    expect(isOnThisDay("2026-10-14", "2026-10-14")).toBe(false);
    expect(isOnThisDay("2025-10-13", "2026-10-14")).toBe(false);
  });

  test("hashString is stable", () => {
    expect(hashString("a:2026-10-14")).toBe(hashString("a:2026-10-14"));
    expect(hashString("a:2026-10-14")).not.toBe(hashString("a:2026-10-15"));
  });
});

// ---- fixtures ----

async function insertMemory(
  t: TestConvex,
  couple: TestCouple,
  date: string,
  overrides: Partial<Doc<"memories">> = {},
): Promise<string> {
  const id = newUuid();
  await t.run(async (ctx) => {
    const now = nowIso();
    await ctx.db.insert("memories", {
      id,
      couple_id: couple.coupleId,
      title: `Memory ${date}`,
      memory_date: date,
      created_by_user_id: couple.first.userId,
      last_edited_by_user_id: couple.first.userId,
      revision: 1,
      moderation_status: "visible",
      created_at: now,
      updated_at: now,
      ...overrides,
    });
  });
  return id;
}

async function insertAsset(
  t: TestConvex,
  couple: TestCouple,
  options: {
    parentKind: Doc<"media_assets">["reserved_parent_kind"];
    parentId: string;
    mediaType: "image" | "voice" | "drawing_payload";
    moderation?: Doc<"media_assets">["moderation_status"];
  },
): Promise<string> {
  const id = newUuid();
  await t.run(async (ctx) => {
    const now = nowIso();
    const drawing = options.mediaType === "drawing_payload";
    await ctx.db.insert("media_assets", {
      id,
      owner_user_id: couple.first.userId,
      couple_id: couple.coupleId,
      reserved_parent_kind: options.parentKind,
      reserved_parent_id: options.parentId,
      reserved_by_client_operation_id: newUuid(),
      bucket: drawing ? "widget-drawings" : "couple-media",
      storage_path: `${couple.coupleId}/${id}`,
      media_type: options.mediaType,
      upload_purpose: drawing
        ? "widget_drawing_payload"
        : options.parentKind === "memory_media"
          ? "memory_photo"
          : options.mediaType === "voice"
            ? "voice_note"
            : "daily_answer_media",
      expected_media_type: options.mediaType,
      expected_bucket: drawing ? "widget-drawings" : "couple-media",
      upload_status: "finalized",
      upload_expires_at: now,
      upload_finalized_at: now,
      moderation_status: options.moderation ?? "visible",
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      created_at: now,
      updated_at: now,
    });
  });
  return id;
}

async function attachMemoryPhoto(
  t: TestConvex,
  couple: TestCouple,
  memoryId: string,
  sortOrder: number,
  moderation: Doc<"media_assets">["moderation_status"] = "visible",
): Promise<string> {
  const linkId = newUuid();
  const assetId = await insertAsset(t, couple, { parentKind: "memory_media", parentId: linkId, mediaType: "image", moderation });
  await t.run(async (ctx) => {
    const now = nowIso();
    await ctx.db.insert("memory_media", {
      id: linkId,
      memory_id: memoryId,
      media_asset_id: assetId,
      owner_user_id: couple.first.userId,
      sort_order: sortOrder,
      moderation_status: "visible",
      created_at: now,
      updated_at: now,
    });
  });
  return assetId;
}

async function insertDrawing(
  t: TestConvex,
  couple: TestCouple,
  createdAt: string,
  overrides: Partial<Doc<"widget_drawing_revisions">> = {},
): Promise<{ revisionId: string; assetId: string }> {
  const revisionId = newUuid();
  const assetId = await insertAsset(t, couple, {
    parentKind: "widget_drawing_revision",
    parentId: revisionId,
    mediaType: "drawing_payload",
  });
  await t.run(async (ctx) => {
    let canvas = await ctx.db
      .query("widget_canvases")
      .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.coupleId))
      .unique();
    if (!canvas) {
      const canvasId = await ctx.db.insert("widget_canvases", {
        id: newUuid(),
        couple_id: couple.coupleId,
        created_at: createdAt,
        updated_at: createdAt,
      });
      canvas = (await ctx.db.get(canvasId))!;
    }
    await ctx.db.insert("widget_drawing_revisions", {
      id: revisionId,
      canvas_id: canvas.id,
      author_user_id: couple.second.userId,
      format: "pkdrawing",
      format_version: 1,
      payload_media_asset_id: assetId,
      payload_bytes: 10,
      uncompressed_bytes: 10,
      compression: "none",
      bounds: { canvasSide: 320 },
      renderer_version: 1,
      client_decode_validated_at: createdAt,
      client_renderer_version: "r1",
      client_validation_version: "v1",
      moderation_status: "visible",
      created_at: createdAt,
      updated_at: createdAt,
      ...overrides,
    });
  });
  return { revisionId, assetId };
}

type RoundOptions = {
  ownText?: string | null;
  partnerText?: string | null;
  partnerAnswer?: Partial<Doc<"daily_question_answers">> | false;
  status?: Doc<"daily_question_instances">["status"];
};

/** A couple day with one question both partners answered (unless `partnerAnswer` is false). */
async function insertRound(
  t: TestConvex,
  couple: TestCouple,
  localDate: string,
  versionId: string,
  options: RoundOptions = {},
): Promise<string> {
  const instanceId = newUuid();
  await t.run(async (ctx) => {
    const dayStart = `${localDate}T00:00:00.000Z`;
    const dayEnd = new Date(Date.parse(dayStart) + 86_400_000).toISOString();
    const day = await ctx.db.insert("couple_days", {
      id: newUuid(),
      couple_id: couple.coupleId,
      local_date: localDate,
      anchor_time_zone_id: "UTC",
      starts_at: dayStart,
      ends_at: dayEnd,
      created_at: dayStart,
    });
    const dayId = (await ctx.db.get(day))!.id;
    await ctx.db.insert("daily_question_instances", {
      id: instanceId,
      couple_day_id: dayId,
      couple_id: couple.coupleId,
      question_id: (await getByUuid(ctx, "question_versions", versionId))!.question_id,
      question_version_id: versionId,
      seeded_for_user_id: couple.first.userId,
      slot_number: 1,
      status: options.status ?? "answered",
      created_at: dayStart,
    });
    const answered = `${localDate}T10:00:00.000Z`;
    const answers: [string, string | null, Partial<Doc<"daily_question_answers">>][] = [
      [couple.first.userId, options.ownText === undefined ? "Our first trip" : options.ownText, {}],
    ];
    if (options.partnerAnswer !== false) {
      answers.push([
        couple.second.userId,
        options.partnerText === undefined ? "The beach" : options.partnerText,
        options.partnerAnswer ?? {},
      ]);
    }
    for (const [userId, text, overrides] of answers) {
      const answerId = newUuid();
      await ctx.db.insert("daily_question_answers", {
        id: answerId,
        instance_id: instanceId,
        user_id: userId,
        created_at: answered,
        updated_at: answered,
        moderation_status: "visible",
        ...overrides,
      });
      if (text !== null) await ctx.db.insert("daily_answer_text", { answer_id: answerId, body: text });
    }
  });
  return instanceId;
}

async function readyCouple(options: { entitled?: boolean } = {}) {
  const t = newTest();
  const [question] = await seedCatalog(t, textQuestions(1));
  const couple = await createCouple(t, options);
  return { t, couple, versionId: question.versionId };
}

// ---- selection ----

describe("get_look_back", () => {
  test("is null when the couple has no old content", async () => {
    const { couple } = await readyCouple();
    expect(await lookBack(couple.first)).toBeNull();
  });

  test("ignores content younger than seven days and accepts content exactly seven days old", async () => {
    const { t, couple } = await readyCouple();
    await insertMemory(t, couple, "2026-10-08");
    await insertMemory(t, couple, "2026-10-14");
    expect(await lookBack(couple.first)).toBeNull();
    const old = await insertMemory(t, couple, "2026-10-07");
    expect(await lookBack(couple.first)).toMatchObject({
      kind: "memory",
      content_date: "2026-10-07",
      on_this_day: false,
      memory: { memory_id: old, title: "Memory 2026-10-07", photo_media_asset_id: null },
    });
  });

  test("gives both partners the same item, and the same item on every call that day", async () => {
    const { t, couple } = await readyCouple();
    for (let day = 1; day <= 12; day += 1) {
      await insertMemory(t, couple, `2026-09-${String(day).padStart(2, "0")}`);
    }
    const first = await lookBack(couple.first);
    expect(first).not.toBeNull();
    expect(await lookBack(couple.second)).toEqual(first);
    expect(await lookBack(couple.first)).toEqual(first);
    // The system clock plays no part, only the time the app passes.
    vi.setSystemTime(new Date("2026-12-31T12:00:00.000Z"));
    expect(await lookBack(couple.first)).toEqual(first);
  });

  test("changes from day to day", async () => {
    const { t, couple } = await readyCouple();
    for (let day = 1; day <= 12; day += 1) {
      await insertMemory(t, couple, `2026-08-${String(day).padStart(2, "0")}`);
    }
    const seen = new Set<string>();
    for (let offset = 0; offset < 14; offset += 1) {
      const item = await lookBack(couple.first, new Date(Date.parse(NOW) + offset * 86_400_000).toISOString());
      seen.add(item!.memory!.memory_id);
    }
    expect(seen.size).toBeGreaterThan(1);
  });

  test("prefers content from this day in an earlier year", async () => {
    const { t, couple } = await readyCouple();
    for (let day = 1; day <= 12; day += 1) {
      await insertMemory(t, couple, `2026-09-${String(day).padStart(2, "0")}`);
    }
    const anniversary = await insertMemory(t, couple, "2024-10-14");
    for (const user of [couple.first, couple.second]) {
      expect(await lookBack(user)).toMatchObject({
        kind: "memory",
        content_date: "2024-10-14",
        on_this_day: true,
        memory: { memory_id: anniversary },
      });
    }
  });

  test("falls back to other content when the on this day item is not showable", async () => {
    const { t, couple } = await readyCouple();
    await insertMemory(t, couple, "2025-10-14", { deleted_at: nowIso() });
    const other = await insertMemory(t, couple, "2026-09-01");
    expect(await lookBack(couple.first)).toMatchObject({ memory: { memory_id: other }, on_this_day: false });
  });

  test("picks among on this day items of every kind and ignores older items from other days", async () => {
    const { t, couple, versionId } = await readyCouple();
    await insertMemory(t, couple, "2025-10-14");
    await insertDrawing(t, couple, "2025-10-14T09:00:00.000Z");
    await insertRound(t, couple, "2025-10-14", versionId);
    await insertMemory(t, couple, "2025-10-15");
    const item = await lookBack(couple.first);
    expect(["memory", "drawing", "question"]).toContain(item!.kind);
    expect(item).toMatchObject({ content_date: "2025-10-14", on_this_day: true });
  });
  test("takes the couple date from the time the app passes, in the westmost partner's zone", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "America/New_York"] });
    const before = await insertMemory(t, couple, "2025-10-14");
    const after = await insertMemory(t, couple, "2025-10-15");
    // 01:00 UTC is 21:00 on the 14th in New York (the couple's date) and 03:00 on the 15th in Oslo.
    const evening = await lookBackAt(couple.second, "2026-10-15T01:00:00.000Z");
    expect(evening.item!.memory!.memory_id).toBe(before);
    expect(evening.ends_at).toBe("2026-10-15T04:00:00.000Z");
    // 05:00 UTC is 01:00 on the 15th in New York.
    const morning = await lookBackAt(couple.second, "2026-10-15T05:00:00.000Z");
    expect(morning.item!.memory!.memory_id).toBe(after);
    expect(morning.ends_at).toBe("2026-10-16T04:00:00.000Z");
    // Asking exactly at ends_at gives the next day.
    expect((await lookBackAt(couple.first, evening.ends_at)).item!.memory!.memory_id).toBe(after);
  });

  test("returns the day's end even without an item", async () => {
    const { couple } = await readyCouple();
    expect(await lookBackAt(couple.first)).toEqual({ item: null, ends_at: "2026-10-15T00:00:00.000Z" });
  });
});

describe("memories", () => {
  test("excludes deleted and hidden memories", async () => {
    const { t, couple } = await readyCouple();
    await insertMemory(t, couple, "2026-09-01", { deleted_at: nowIso() });
    await insertMemory(t, couple, "2026-09-02", { moderation_status: "hidden" });
    expect(await lookBack(couple.first)).toBeNull();
  });

  test("returns the first photo that is visible and skips hidden ones", async () => {
    const { t, couple } = await readyCouple();
    const memoryId = await insertMemory(t, couple, "2026-09-01");
    await attachMemoryPhoto(t, couple, memoryId, 1, "hidden");
    const shown = await attachMemoryPhoto(t, couple, memoryId, 2);
    await attachMemoryPhoto(t, couple, memoryId, 3);
    expect((await lookBack(couple.first))!.memory!.photo_media_asset_id).toBe(shown);
  });
});

describe("drawings", () => {
  test("returns what the history thumbnail needs", async () => {
    const { t, couple } = await readyCouple();
    const { revisionId, assetId } = await insertDrawing(t, couple, "2026-09-20T09:00:00.000Z");
    expect(await lookBack(couple.first)).toEqual({
      kind: "drawing",
      content_date: "2026-09-20",
      on_this_day: false,
      question: null,
      memory: null,
      drawing: {
        revision_id: revisionId,
        media_asset_id: assetId,
        author_user_id: couple.second.userId,
        canvas_side: 320,
      },
    });
  });

  test("excludes new, deleted, and hidden drawings", async () => {
    const { t, couple } = await readyCouple();
    await insertDrawing(t, couple, "2026-10-10T09:00:00.000Z");
    await insertDrawing(t, couple, "2026-09-01T09:00:00.000Z", { deleted_at: nowIso() });
    await insertDrawing(t, couple, "2026-09-02T09:00:00.000Z", { moderation_status: "removed" });
    expect(await lookBack(couple.first)).toBeNull();
  });

  test("excludes a drawing whose file is hidden", async () => {
    const { t, couple } = await readyCouple();
    const { assetId } = await insertDrawing(t, couple, "2026-09-01T09:00:00.000Z");
    await t.run(async (ctx) => {
      const asset = await ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", assetId)).unique();
      await ctx.db.patch(asset!._id, { moderation_status: "hidden" });
    });
    expect(await lookBack(couple.first)).toBeNull();
  });
});

describe("question rounds", () => {
  test("returns both answers with the localized short prompts", async () => {
    const { t, couple, versionId } = await readyCouple();
    const instanceId = await insertRound(t, couple, "2026-09-01", versionId);
    const asset = await insertAsset(t, couple, { parentKind: "daily_answer_media", parentId: newUuid(), mediaType: "image" });
    await t.run(async (ctx) => {
      const answer = await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId).eq("user_id", couple.second.userId))
        .unique();
      await ctx.db.insert("daily_answer_media", { answer_id: answer!.id, media_asset_id: asset, sort_order: 1 });
      await ctx.db.insert("daily_answer_partner_choice", { answer_id: answer!.id, selected_user_id: couple.first.userId });
    });
    const item = await lookBack(couple.second);
    expect(item).toMatchObject({
      kind: "question",
      content_date: "2026-09-01",
      question: {
        instance_id: instanceId,
        short_prompt_en: "q_01 short en",
        short_prompt_nb: "q_01 short nb",
        own_answer: { user_id: couple.second.userId, text: "The beach", has_photo: true, has_voice: false },
        partner_answer: { user_id: couple.first.userId, text: "Our first trip", has_photo: false },
      },
    });
    const first = await lookBack(couple.first);
    expect(first!.question!.partner_answer).toMatchObject({
      user_id: couple.second.userId,
      selected_user_id: couple.first.userId,
      has_photo: true,
    });
  });

  test("cuts a long answer", async () => {
    const { t, couple, versionId } = await readyCouple();
    await insertRound(t, couple, "2026-09-01", versionId, { ownText: "x".repeat(500) });
    expect((await lookBack(couple.first))!.question!.own_answer.text).toHaveLength(200);
  });

  test("skips a round the partner has not answered", async () => {
    const { t, couple, versionId } = await readyCouple();
    await insertRound(t, couple, "2026-09-01", versionId, { partnerAnswer: false });
    expect(await lookBack(couple.first)).toBeNull();
    expect(await lookBack(couple.second)).toBeNull();
  });

  test("skips a round with a deleted or hidden answer", async () => {
    const { t, couple, versionId } = await readyCouple();
    await insertRound(t, couple, "2026-09-01", versionId, { partnerAnswer: { deleted_at: nowIso() } });
    await insertRound(t, couple, "2026-09-02", versionId, { partnerAnswer: { moderation_status: "hidden" } });
    expect(await lookBack(couple.first)).toBeNull();
  });

  test("skips a shuffled question and a round that is too new", async () => {
    const { t, couple, versionId } = await readyCouple();
    await insertRound(t, couple, "2026-09-01", versionId, { status: "shuffled" });
    await insertRound(t, couple, "2026-10-12", versionId);
    expect(await lookBack(couple.first)).toBeNull();
  });

  test("gives both partners the same round even when one of them answered many more questions", async () => {
    const { t, couple, versionId } = await readyCouple();
    const round = await insertRound(t, couple, "2026-01-01", versionId);
    // 65 newer questions only the first partner answered would fill that partner's own newest answers.
    for (let index = 0; index < 65; index += 1) {
      const date = new Date(Date.UTC(2026, 6, 1) - index * 86_400_000).toISOString().slice(0, 10);
      await insertRound(t, couple, date, versionId, { partnerAnswer: false });
    }
    for (const user of [couple.first, couple.second]) {
      expect(await lookBack(user)).toMatchObject({ kind: "question", question: { instance_id: round } });
    }
  });

  test("finds a round on this day from an earlier year", async () => {
    const { t, couple, versionId } = await readyCouple();
    const instanceId = await insertRound(t, couple, "2025-10-14", versionId);
    for (let day = 1; day <= 12; day += 1) {
      await insertMemory(t, couple, `2026-09-${String(day).padStart(2, "0")}`);
    }
    expect(await lookBack(couple.first)).toMatchObject({
      kind: "question",
      on_this_day: true,
      question: { instance_id: instanceId },
    });
  });
});

describe("authorization", () => {
  test("refuses a signed-out caller, a stranger, and an unentitled couple", async () => {
    const { t, couple } = await readyCouple();
    await insertMemory(t, couple, "2026-09-01");
    expect(await failure(t.query(api.lookBack.get_look_back, { p_now: NOW }))).toMatchObject({ code: "42501" });
    const stranger = await createSignedInUser(t);
    expect(await failure(lookBack(stranger))).toEqual({
      code: "42501",
      message: "active entitled couple access is required",
    });
    const unentitled = await createCouple(t, { entitled: false });
    expect(await failure(lookBack(unentitled.first))).toMatchObject({ code: "42501" });
  });

  test("never returns another couple's content", async () => {
    const { t, couple } = await readyCouple();
    await insertMemory(t, couple, "2026-09-01");
    const other = await createCouple(t);
    expect(await lookBack(other.first)).toBeNull();
  });
});
