import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { endCouple, failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { newUuid } from "./lib/ids";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds = 60) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

function newMemory(user: TestUser, overrides: Record<string, unknown> = {}) {
  const memoryId = newUuid();
  const operation = op();
  const call = () =>
    user.as.mutation(api.memories.create_memory, {
      ...operation,
      p_memory_id: memoryId,
      p_title: "Beach weekend",
      p_memory_date: "2026-10-01",
      p_note_body: "Warm sand",
      p_media_asset_ids: [],
      ...overrides,
    });
  return { memoryId, call };
}

async function createMemory(user: TestUser, overrides: Record<string, unknown> = {}) {
  const memory = newMemory(user, overrides);
  await memory.call();
  return memory.memoryId;
}

const getMemories = (user: TestUser, args: Record<string, unknown> = {}) => user.as.query(api.memories.get_memories, args);
const memoryRow = async (t: TestConvex, id: string) =>
  await t.run((ctx) => ctx.db.query("memories").withIndex("by_uuid", (q) => q.eq("id", id)).unique());
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

describe("create_memory", () => {
  test("creates the memory and its note and returns the memory id", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = newUuid();
    const result = await couple.first.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: memoryId.toUpperCase(),
      p_title: "  Beach weekend  ",
      p_memory_date: "2026-10-01",
      p_note_body: "  Warm sand ",
      p_media_asset_ids: null,
    });
    expect(result).toBe(memoryId);
    expect(await memoryRow(t, memoryId)).toMatchObject({
      couple_id: couple.coupleId,
      title: "Beach weekend",
      memory_date: "2026-10-01",
      created_by_user_id: couple.first.userId,
      last_edited_by_user_id: couple.first.userId,
      revision: 1,
      moderation_status: "visible",
    });
    const notes = await t.run((ctx) => ctx.db.query("memory_notes").collect());
    expect(notes).toMatchObject([{ memory_id: memoryId, user_id: couple.first.userId, body: "Warm sand", revision: 1 }]);
  });

  test("a replay returns the same id without creating anything twice", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memory = newMemory(couple.first);
    expect(await memory.call()).toBe(memory.memoryId);
    expect(await memory.call()).toBe(memory.memoryId);
    expect(await t.run((ctx) => ctx.db.query("memories").collect())).toHaveLength(1);

    const args = { ...op(), p_memory_id: newUuid(), p_title: "A", p_memory_date: "2026-10-01", p_note_body: "x" };
    await couple.first.as.mutation(api.memories.create_memory, args);
    expect(await failure(couple.first.as.mutation(api.memories.create_memory, { ...args, p_title: "B" }))).toEqual({
      code: "23505",
      message: "client operation replay hash mismatch",
    });
  });

  test("reusing a memory id under a new operation is a duplicate key error", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const error = await failure(createMemory(couple.first, { p_memory_id: memoryId }));
    expect(error).toEqual({ code: "23505", message: 'duplicate key value violates unique constraint "memories_pkey"' });
  });

  test.each([
    ["a blank title", { p_title: "   " }, "23514", "memory title is required"],
    ["a long title", { p_title: "x".repeat(161) }, "23514", "memory title is too long"],
    ["a long note", { p_note_body: "x".repeat(4001) }, "23514", "memory note body is too long"],
    ["no note and no media", { p_note_body: "  " }, "23514", "memory must include a note or media"],
    ["a bad date", { p_memory_date: "2026-02-30" }, "22007", 'invalid input syntax for type date: "2026-02-30"'],
  ])("rejects %s", async (_name, overrides, code, message) => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await failure(newMemory(couple.first, overrides).call())).toEqual({ code, message });
  });

  test("rejects a signed-out caller", async () => {
    const t = newTest();
    await createCouple(t);
    expect(
      await failure(
        t.mutation(api.memories.create_memory, {
          ...op(),
          p_memory_id: newUuid(),
          p_title: "A",
          p_memory_date: "2026-10-01",
          p_note_body: "x",
        }),
      ),
    ).toEqual({ code: "42501", message: "authenticated user required" });
  });
});

describe("memory created notifications", () => {
  async function setup() {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en", token: "a" });
    await addDevice(t, couple.second.userId, { locale: "nb-NO", token: "b" });
    await addDevice(t, couple.first.userId, { locale: "en", token: "c" });
    return { t, couple };
  }

  test("queues one alert per partner device without the memory content", async () => {
    const { t, couple } = await setup();
    const memoryId = await createMemory(couple.first, { p_title: "Private beach weekend", p_note_body: "Private note" });
    const rows = await outbox(t);
    expect(rows).toHaveLength(2);
    expect(new Set(rows.map((row) => row.recipient_user_id))).toEqual(new Set([couple.second.userId]));
    expect(rows.map((row) => row.title).sort()).toEqual(["First Partner added a memory", "First Partner la til et minne"]);
    expect(rows[0].payload).toEqual({
      type: "memory_created",
      couple_id: couple.coupleId,
      memory_id: memoryId,
      actor_user_id: couple.first.userId,
      route: "memories",
      deeplink: `paeonia://memories/memory?memoryId=${memoryId}`,
    });
    expect(rows[0].apns_collapse_id).toBe(`memory:${memoryId}`);
    expect(rows.every((row) => row.dedupe_key?.startsWith(`memory_created:${memoryId}:`))).toBe(true);
    expect(JSON.stringify(rows)).not.toContain("Private");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("editing the memory does not notify again, and a disabled preference suppresses the alert", async () => {
    const { t, couple } = await setup();
    const memoryId = await createMemory(couple.first);
    tick();
    await couple.first.as.mutation(api.memories.update_memory, {
      ...op(),
      p_memory_id: memoryId,
      p_expected_revision: 1,
      p_title: "Edited",
      p_memory_date: "2026-10-02",
    });
    expect(await outbox(t)).toHaveLength(2);

    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").withIndex("by_user_id", (q) => q.eq("user_id", couple.second.userId)).unique();
      await ctx.db.patch(preference!._id, { memories_enabled: false });
    });
    await createMemory(couple.first);
    expect(await outbox(t)).toHaveLength(2);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("memory media", () => {
  test("create_memory attaches uploaded media in order", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const a = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const b = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const memoryId = await createMemory(couple.first, { p_note_body: null, p_media_asset_ids: [a.assetId, b.assetId.toUpperCase()] });
    const links = await t.run((ctx) => ctx.db.query("memory_media").collect());
    expect(links.map((link) => [link.id, link.media_asset_id, link.sort_order, link.owner_user_id, link.memory_id])).toEqual([
      [a.parentId, a.assetId, 1, couple.first.userId, memoryId],
      [b.parentId, b.assetId, 2, couple.first.userId, memoryId],
    ]);
    const [row] = await getMemories(couple.second);
    expect(row.memory_media_ids).toEqual([a.parentId, b.parentId]);
    expect(row.media_asset_ids).toEqual([a.assetId, b.assetId]);
    expect(row.memory_media_states).toHaveLength(2);
    expect(row.memory_media_states[0]).toMatchObject({
      memory_media_id: a.parentId,
      owner_user_id: couple.first.userId,
      sort_order: 1,
      deleted_at: null,
      moderation_status: "visible",
      asset_deleted_at: null,
      asset_moderation_status: "visible",
      asset_storage_delete_status: "none",
    });
  });

  test("attach_memory_media appends after existing media and returns the new ids", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const first = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const memoryId = await createMemory(couple.first, { p_media_asset_ids: [first.assetId] });
    const second = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const partnerPhoto = await uploadAsset(t, couple.second, photo(couple.coupleId));

    const ids = await couple.first.as.mutation(api.memories.attach_memory_media, {
      ...op(),
      p_memory_id: memoryId,
      p_media_asset_ids: [second.assetId],
    });
    expect(ids).toEqual([second.parentId]);
    await couple.second.as.mutation(api.memories.attach_memory_media, {
      ...op(),
      p_memory_id: memoryId,
      p_media_asset_ids: [partnerPhoto.assetId],
    });
    const links = await t.run((ctx) => ctx.db.query("memory_media").collect());
    expect(links.map((link) => [link.media_asset_id, link.owner_user_id === couple.first.userId, link.sort_order])).toEqual([
      [first.assetId, true, 1],
      [second.assetId, true, 2],
      [partnerPhoto.assetId, false, 1],
    ]);
  });

  test("attach_memory_media is idempotent for a repeated operation", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const photoAsset = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const args = { ...op(), p_memory_id: memoryId, p_media_asset_ids: [photoAsset.assetId] };
    const first = await couple.first.as.mutation(api.memories.attach_memory_media, args);
    expect(await couple.first.as.mutation(api.memories.attach_memory_media, args)).toEqual(first);
    expect(await t.run((ctx) => ctx.db.query("memory_media").collect())).toHaveLength(1);
  });

  test("enforces the media limits", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const attach = (ids: string[]) =>
      failure(couple.first.as.mutation(api.memories.attach_memory_media, { ...op(), p_memory_id: memoryId, p_media_asset_ids: ids }));
    const photos = [];
    for (let i = 0; i < 6; i += 1) photos.push((await uploadAsset(t, couple.first, photo(couple.coupleId))).assetId);

    expect(await attach([])).toEqual({ code: "23514", message: "memory media asset ids are required" });
    expect(await attach([photos[0], photos[0]])).toEqual({ code: "23514", message: "memory media asset ids must be unique" });
    expect(await attach(Array.from({ length: 11 }, () => newUuid()))).toEqual({
      code: "23514",
      message: "a memory can attach at most 10 media assets at once",
    });
    expect(await attach(photos)).toEqual({ code: "23514", message: "each partner can add at most 5 photos to a memory" });
    expect(await t.run((ctx) => ctx.db.query("memory_media").collect())).toHaveLength(0);
    await couple.first.as.mutation(api.memories.attach_memory_media, {
      ...op(),
      p_memory_id: memoryId,
      p_media_asset_ids: photos.slice(0, 5),
    });
  });

  test("rejects assets that are not the caller's finalized memory media", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const partnerPhoto = await uploadAsset(t, couple.second, photo(couple.coupleId));
    const threadPhoto = await uploadAsset(t, couple.first, photo(couple.coupleId, "thread_message_media", "thread_media"));
    const [pending] = await couple.first.as.mutation(api.media.create_pending_media_upload, {
      ...op(),
      p_reserved_parent_kind: "memory_media",
      p_reserved_parent_id: newUuid(),
      p_upload_purpose: "memory_photo",
      p_media_type: "image",
      p_file_extension: "jpg",
      p_couple_id: couple.coupleId,
    });
    const unusable = { code: "23514", message: "memory media asset is not usable" };
    for (const id of [partnerPhoto.assetId, threadPhoto.assetId, pending.media_asset_id, newUuid()]) {
      expect(
        await failure(
          couple.first.as.mutation(api.memories.attach_memory_media, { ...op(), p_memory_id: memoryId, p_media_asset_ids: [id] }),
        ),
      ).toEqual(unusable);
    }
  });

  test("remove_memory_media hides the media and queues the file for deletion", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId));
    await createMemory(couple.first, { p_media_asset_ids: [up.assetId] });
    const remove = (user: TestUser, id: string) =>
      user.as.mutation(api.memories.remove_memory_media, { ...op(), p_memory_media_id: id });

    expect(await failure(remove(couple.second, up.parentId))).toEqual({ code: "42501", message: "memory media is not removable" });
    tick();
    expect(await remove(couple.first, up.parentId)).toBe(up.parentId);
    const link = await t.run((ctx) => ctx.db.query("memory_media").first());
    expect(link?.deleted_at).toBe(new Date().toISOString());
    const asset = await t.run((ctx) => ctx.db.query("media_assets").first());
    expect(asset).toMatchObject({ storage_delete_status: "pending", deleted_at: new Date().toISOString() });
    const [row] = await getMemories(couple.second);
    expect(row.memory_media_ids).toEqual([]);
    expect(row.memory_media_states[0].deleted_at).toBe(new Date().toISOString());
    expect(await failure(remove(couple.first, up.parentId))).toEqual({ code: "42501", message: "memory media is not removable" });
  });
});

describe("update_memory", () => {
  test("changes the title and date and bumps the revision", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    tick();
    const rows = await couple.second.as.mutation(api.memories.update_memory, {
      ...op(),
      p_memory_id: memoryId,
      p_expected_revision: 1,
      p_title: " New title ",
      p_memory_date: "2026-09-30",
    });
    expect(rows).toEqual([{ memory_id: memoryId, revision: 2, updated_at: new Date().toISOString() }]);
    expect(await memoryRow(t, memoryId)).toMatchObject({
      title: "New title",
      memory_date: "2026-09-30",
      last_edited_by_user_id: couple.second.userId,
      revision: 2,
    });
  });

  test("a stale revision is a conflict and changes nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const update = (revision: number, title: string) =>
      couple.first.as.mutation(api.memories.update_memory, {
        ...op(),
        p_memory_id: memoryId,
        p_expected_revision: revision,
        p_title: title,
        p_memory_date: "2026-10-01",
      });
    await update(1, "Second");
    const error = await failure(update(1, "Third"));
    expect(error).toEqual({ code: "40001", message: "memory revision conflict" });
    expect((await memoryRow(t, memoryId))?.title).toBe("Second");
    expect(await failure(update(0, "Zero"))).toEqual({ code: "23514", message: "expected memory revision is required" });
  });

  test("a replay returns the first answer even after more edits", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const args = { ...op(), p_memory_id: memoryId, p_expected_revision: 1, p_title: "Edit", p_memory_date: "2026-10-01" };
    const first = await couple.first.as.mutation(api.memories.update_memory, args);
    tick();
    await couple.first.as.mutation(api.memories.update_memory, { ...args, ...op(), p_expected_revision: 2, p_title: "Later" });
    expect(await couple.first.as.mutation(api.memories.update_memory, args)).toEqual(first);
    expect((await memoryRow(t, memoryId))?.title).toBe("Later");
  });
});

describe("hide_memory", () => {
  test("soft deletes the memory and its thread and queues its media", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const memoryId = await createMemory(couple.first, { p_media_asset_ids: [up.assetId] });
    await couple.first.as.mutation(api.threads.create_memory_thread_with_message, {
      ...op(),
      p_memory_id: memoryId,
      p_body: "hello",
    });
    tick();
    const rows = await couple.second.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1 });
    expect(rows).toEqual([{ memory_id: memoryId, revision: 2, updated_at: new Date().toISOString() }]);
    expect(await memoryRow(t, memoryId)).toMatchObject({ deleted_at: new Date().toISOString(), last_edited_by_user_id: couple.second.userId });
    const thread = await t.run((ctx) => ctx.db.query("conversation_threads").first());
    expect(thread?.deleted_at).toBe(new Date().toISOString());
    expect((await t.run((ctx) => ctx.db.query("media_assets").first()))?.storage_delete_status).toBe("pending");

    const [row] = await getMemories(couple.first);
    expect(row).toMatchObject({ memory_id: memoryId, title: null, own_note_body: null, partner_note_body: null, media_asset_ids: [] });
    expect(row.deleted_at).toBe(new Date().toISOString());
    expect(
      await failure(couple.first.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 2 })),
    ).toEqual({ code: "42501", message: "active entitled memory access is required" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a stale revision is a conflict", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    expect(
      await failure(couple.first.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 5 })),
    ).toEqual({ code: "40001", message: "memory revision conflict" });
    expect((await memoryRow(t, memoryId))?.deleted_at).toBeUndefined();
  });
});

describe("upsert_memory_note", () => {
  const upsert = (user: TestUser, memoryId: string, expected: number | null, body: string) =>
    user.as.mutation(api.memories.upsert_memory_note, { ...op(), p_memory_id: memoryId, p_expected_revision: expected, p_body: body });

  test("creates the note, then edits it with the current revision", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const [created] = await upsert(couple.second, memoryId, null, " Me too ");
    expect(created).toMatchObject({ revision: 1, updated_at: new Date().toISOString() });
    tick();
    const [edited] = await upsert(couple.second, memoryId, 1, "Me three");
    expect(edited).toEqual({ note_id: created.note_id, revision: 2, updated_at: new Date().toISOString() });

    const [forFirst] = await getMemories(couple.first);
    expect(forFirst).toMatchObject({
      partner_note_id: created.note_id,
      partner_note_user_id: couple.second.userId,
      partner_note_body: "Me three",
      partner_note_revision: 2,
      own_note_body: "Warm sand",
    });
    const [forSecond] = await getMemories(couple.second);
    expect(forSecond).toMatchObject({ own_note_body: "Me three", partner_note_body: "Warm sand" });
  });

  test("reports revision conflicts", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const conflict = { code: "40001", message: "memory note revision conflict" };
    expect(await failure(upsert(couple.first, memoryId, null, "no revision"))).toEqual(conflict);
    expect(await failure(upsert(couple.first, memoryId, 3, "wrong revision"))).toEqual(conflict);
    expect(await failure(upsert(couple.second, memoryId, 2, "new note, stale revision"))).toEqual(conflict);
    await upsert(couple.second, memoryId, 0, "first note");
    expect(await failure(upsert(couple.second, memoryId, 0, "again"))).toEqual(conflict);
  });

  test("validates the body and refuses a hidden note", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    expect(await failure(upsert(couple.first, memoryId, 1, "   "))).toEqual({ code: "23514", message: "memory note body is required" });
    expect(await failure(upsert(couple.first, memoryId, 1, "x".repeat(4001)))).toEqual({
      code: "23514",
      message: "memory note body is too long",
    });
    await t.run(async (ctx) => {
      const note = await ctx.db.query("memory_notes").first();
      await ctx.db.patch(note!._id, { moderation_status: "hidden" });
    });
    expect(await failure(upsert(couple.first, memoryId, 1, "edit"))).toEqual({
      code: "42501",
      message: "memory note is not editable",
    });
  });
});

describe("get_memories", () => {
  test("pages by sync time and memory id", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const ids = [];
    for (let i = 0; i < 3; i += 1) {
      ids.push(await createMemory(couple.first, { p_title: `Memory ${i}` }));
      tick();
    }
    const all = await getMemories(couple.first, { p_limit: 200 });
    expect(all.map((row: { memory_id: string }) => row.memory_id)).toEqual(ids);
    const page = await getMemories(couple.first, { p_limit: 2 });
    expect(page).toHaveLength(2);
    const next = await getMemories(couple.first, {
      p_updated_after: page[1].sync_updated_at,
      p_cursor_memory_id: page[1].memory_id,
      p_limit: 2,
    });
    expect(next.map((row: { memory_id: string }) => row.memory_id)).toEqual([ids[2]]);
    expect(await getMemories(couple.first, { p_updated_after: all[2].sync_updated_at, p_cursor_memory_id: all[2].memory_id })).toEqual([]);
  });

  test("memories with the same sync time page by id without repeats or gaps", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const ids = [];
    for (let i = 0; i < 5; i += 1) ids.push(await createMemory(couple.first));
    const seen: string[] = [];
    let cursor: Record<string, unknown> = {};
    for (;;) {
      const page: { memory_id: string; sync_updated_at: string }[] = await getMemories(couple.first, { ...cursor, p_limit: 2 });
      if (page.length === 0) break;
      seen.push(...page.map((row) => row.memory_id));
      const last = page[page.length - 1];
      cursor = { p_updated_after: last.sync_updated_at, p_cursor_memory_id: last.memory_id };
    }
    expect(seen).toHaveLength(5);
    expect(new Set(seen)).toEqual(new Set(ids));
  });

  test("a note edit moves the memory in the sync order", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const first = await createMemory(couple.first);
    tick();
    const second = await createMemory(couple.first);
    tick();
    await couple.second.as.mutation(api.memories.upsert_memory_note, {
      ...op(),
      p_memory_id: first,
      p_expected_revision: null,
      p_body: "late",
    });
    const rows = await getMemories(couple.first);
    expect(rows.map((row: { memory_id: string }) => row.memory_id)).toEqual([second, first]);
  });

  test("returns the SQL columns for a bare memory", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = await createMemory(couple.first);
    const [row] = await getMemories(couple.second);
    expect(Object.keys(row).sort()).toEqual(
      [
        "memory_id", "couple_id", "title", "memory_date", "created_by_user_id", "last_edited_by_user_id", "revision",
        "moderation_status", "deleted_at", "created_at", "updated_at", "sync_updated_at", "own_note_id", "own_note_body",
        "own_note_revision", "own_note_updated_at", "own_note_deleted_at", "own_note_moderation_status", "partner_note_id",
        "partner_note_user_id", "partner_note_body", "partner_note_revision", "partner_note_updated_at",
        "partner_note_deleted_at", "partner_note_moderation_status", "memory_media_ids", "media_asset_ids",
        "memory_media_states", "thread_id", "place",
      ].sort(),
    );
    expect(row).toMatchObject({
      memory_id: id,
      own_note_id: null,
      own_note_body: null,
      partner_note_body: "Warm sand",
      deleted_at: null,
      thread_id: null,
      place: null,
      memory_media_ids: [],
      memory_media_states: [],
    });
  });

  test("rejects a limit outside 1 to 200", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (const limit of [0, 201]) {
      expect(await failure(getMemories(couple.first, { p_limit: limit }))).toEqual({
        code: "23514",
        message: "memory read limit is out of range",
      });
    }
  });
});

const bryggen = { name: "Bryggen", latitude: 60.3975, longitude: 5.3245, city: "Bergen", country_code: "NO" };

describe("memory places", () => {
  type Place = { name: string; latitude: number; longitude: number; city?: string | null; country_code?: string | null };
  const setPlace = (user: TestUser, memoryId: string, place: Place | null) =>
    user.as.mutation(api.memories.set_memory_place, { ...op(), p_memory_id: memoryId, p_place: place });

  test("create_memory stores a trimmed place and get_memories returns it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first, {
      p_place: { ...bryggen, name: "  Bryggen ", city: " Bergen " },
    });
    expect((await memoryRow(t, memoryId))?.place).toEqual(bryggen);
    const [row] = await getMemories(couple.second);
    expect(row.place).toEqual(bryggen);
  });

  test("a memory without a place returns null", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    expect((await memoryRow(t, memoryId))?.place).toBeUndefined();
    const [row] = await getMemories(couple.first);
    expect(row.place).toBeNull();
  });

  test("blank city and country are left out", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first, {
      p_place: { name: "Somewhere at sea", latitude: 59.1, longitude: 10.2, city: "  ", country_code: null },
    });
    expect((await memoryRow(t, memoryId))?.place).toEqual({ name: "Somewhere at sea", latitude: 59.1, longitude: 10.2 });
  });

  test("either partner sets and clears the place without a revision bump", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    tick();
    const rows = await setPlace(couple.second, memoryId, bryggen);
    expect(rows).toEqual([{ memory_id: memoryId, revision: 1, updated_at: new Date().toISOString() }]);
    expect(await memoryRow(t, memoryId)).toMatchObject({
      place: bryggen,
      revision: 1,
      last_edited_by_user_id: couple.second.userId,
      updated_at: new Date().toISOString(),
    });

    tick();
    await setPlace(couple.first, memoryId, null);
    const cleared = await memoryRow(t, memoryId);
    expect(cleared?.place).toBeUndefined();
    expect(cleared?.revision).toBe(1);
    expect(cleared?.updated_at).toBe(new Date().toISOString());
  });

  test("a place change does not conflict with a title edit", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    await setPlace(couple.second, memoryId, bryggen);
    await couple.first.as.mutation(api.memories.update_memory, {
      ...op(),
      p_memory_id: memoryId,
      p_expected_revision: 1,
      p_title: "Rain all weekend",
      p_memory_date: "2026-10-01",
    });
    expect(await memoryRow(t, memoryId)).toMatchObject({ title: "Rain all weekend", place: bryggen, revision: 2 });
  });

  test("a replay with a different place is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const args = { ...op(), p_memory_id: memoryId, p_place: bryggen };
    await couple.first.as.mutation(api.memories.set_memory_place, args);
    await couple.first.as.mutation(api.memories.set_memory_place, args);
    expect(
      await failure(couple.first.as.mutation(api.memories.set_memory_place, { ...args, p_place: { ...bryggen, name: "Fløyen" } })),
    ).toEqual({ code: "23505", message: "client operation replay hash mismatch" });
  });

  test.each([
    [{ ...bryggen, name: "   " }, "memory place name is required"],
    [{ ...bryggen, name: "x".repeat(161) }, "memory place name is too long"],
    [{ ...bryggen, latitude: 91 }, "memory place latitude is out of range"],
    [{ ...bryggen, latitude: Number.NaN }, "memory place latitude is out of range"],
    [{ ...bryggen, longitude: -180.5 }, "memory place longitude is out of range"],
    [{ ...bryggen, city: "x".repeat(121) }, "memory place city is too long"],
    [{ ...bryggen, country_code: "nor" }, "memory place country code is not valid"],
    [{ ...bryggen, country_code: "no" }, "memory place country code is not valid"],
  ])("refuses a bad place: %j", async (place, message) => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    expect(await failure(setPlace(couple.first, memoryId, place))).toEqual({ code: "23514", message });
    expect(await failure(newMemory(couple.first, { p_place: place }).call())).toEqual({ code: "23514", message });
  });

  test("a deleted memory hides its place and refuses a new one", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first, { p_place: bryggen });
    await couple.first.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1 });
    const [row] = await getMemories(couple.second);
    expect(row.place).toBeNull();
    expect(await failure(setPlace(couple.second, memoryId, bryggen))).toEqual({
      code: "42501",
      message: "active entitled memory access is required",
    });
  });
});

describe("access", () => {
  type Caller = { name: string; user: (couple: TestCouple, t: TestConvex) => Promise<TestUser> };
  const callers: Caller[] = [
    { name: "a stranger", user: async (_couple, t) => await createSignedInUser(t) },
    {
      name: "a former partner who left",
      user: async (couple, t) => {
        await endCouple(t, couple.coupleId, couple.first.userId);
        return couple.first;
      },
    },
    {
      name: "the partner of someone who left",
      user: async (couple, t) => {
        await endCouple(t, couple.coupleId, couple.first.userId);
        return couple.second;
      },
    },
  ];

  test.each(callers)("$name cannot read or change memories", async ({ user }) => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    const photoAsset = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const caller = await user(couple, t);
    const memoryDenied = { code: "42501", message: "active entitled memory access is required" };

    expect(
      await failure(caller.as.mutation(api.memories.update_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1, p_title: "x", p_memory_date: "2026-10-01" })),
    ).toEqual(memoryDenied);
    expect(
      await failure(caller.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1 })),
    ).toEqual(memoryDenied);
    expect(
      await failure(caller.as.mutation(api.memories.upsert_memory_note, { ...op(), p_memory_id: memoryId, p_expected_revision: null, p_body: "x" })),
    ).toEqual(memoryDenied);
    expect(
      await failure(caller.as.mutation(api.memories.attach_memory_media, { ...op(), p_memory_id: memoryId, p_media_asset_ids: [photoAsset.assetId] })),
    ).toEqual(memoryDenied);
    expect(
      await failure(caller.as.mutation(api.memories.set_memory_place, { ...op(), p_memory_id: memoryId, p_place: bryggen })),
    ).toEqual(memoryDenied);
    const denied = { code: "42501", message: "active entitled couple access is required" };
    expect(await failure(getMemories(caller))).toEqual(denied);
    expect(await failure(newMemory(caller).call())).toEqual(denied);
    expect((await memoryRow(t, memoryId))?.revision).toBe(1);
  });

  test("an unentitled couple cannot use memories", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    const denied = { code: "42501", message: "active entitled couple access is required" };
    expect(await failure(newMemory(couple.first).call())).toEqual(denied);
    expect(await failure(getMemories(couple.second))).toEqual(denied);

    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      await ctx.db.insert("memories", {
        id: "00000000-0000-4000-8000-000000000001",
        couple_id: couple.coupleId,
        title: "Old",
        memory_date: "2026-01-01",
        created_by_user_id: couple.first.userId,
        last_edited_by_user_id: couple.first.userId,
        revision: 1,
        moderation_status: "visible",
        created_at: now,
        updated_at: now,
      });
    });
    expect(
      await failure(
        couple.first.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: "00000000-0000-4000-8000-000000000001", p_expected_revision: 1 }),
      ),
    ).toEqual({ code: "42501", message: "active entitled memory access is required" });
  });

  test("a hidden memory cannot be edited by anyone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = await createMemory(couple.first);
    await t.run(async (ctx) => {
      const memory = await ctx.db.query("memories").first();
      await ctx.db.patch(memory!._id, { moderation_status: "hidden" });
    });
    expect(
      await failure(
        couple.first.as.mutation(api.memories.update_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1, p_title: "x", p_memory_date: "2026-10-01" }),
      ),
    ).toEqual({ code: "42501", message: "active entitled memory access is required" });
  });
});
