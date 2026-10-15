import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { sha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op, photo, setMediaEnv, storeBlob, uploadAsset, type UploadSpec } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const asset = (t: TestConvex, id: string) =>
  t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", id)).unique());

function reserveArgs(coupleId: string, overrides: Record<string, unknown> = {}) {
  return {
    ...op(),
    p_reserved_parent_kind: "memory_media",
    p_reserved_parent_id: newUuid(),
    p_upload_purpose: "memory_photo",
    p_media_type: "image",
    p_file_extension: "jpg",
    p_couple_id: coupleId,
    ...overrides,
  };
}

/** Reserves an asset and uploads bytes, without finalizing. */
async function reserveAndStore(t: TestConvex, user: TestUser, coupleId: string, bytes = new TextEncoder().encode("photo")) {
  const operationId = newUuid();
  const parentId = newUuid();
  const reserve = reserveArgs(coupleId, { ...op(operationId), p_reserved_parent_id: parentId });
  const [row] = await user.as.mutation(api.media.create_pending_media_upload, reserve);
  const storageId = await storeBlob(t, bytes, "image/jpeg");
  const finalize = (overrides: Record<string, unknown> = {}) => ({
    ...op(),
    p_media_asset_id: row.media_asset_id,
    p_reserved_by_client_operation_id: operationId,
    p_bucket: row.bucket,
    p_storage_path: row.storage_path,
    p_storage_id: storageId,
    p_reserved_parent_kind: "memory_media",
    p_reserved_parent_id: parentId,
    p_upload_purpose: "memory_photo",
    p_media_type: "image",
    p_mime_type: "image/jpeg",
    p_byte_size: bytes.length,
    p_sha256_hex: "",
    p_width: 10,
    p_height: 10,
    ...overrides,
  });
  return { row, reserve, storageId, bytes, parentId, finalize, sha: await sha256Hex(bytes) };
}

describe("create_pending_media_upload", () => {
  test("returns the reservation and an upload URL, and stores a pending asset", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const rows = await couple.first.as.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId));
    expect(rows).toHaveLength(1);
    const [row] = rows;
    expect(row.bucket).toBe("couple-media");
    expect(row.storage_path).toBe(`${couple.coupleId}/image/${row.media_asset_id}.jpg`);
    expect(row.upload_url).toMatch(/^https:\/\//);
    expect(Date.parse(row.upload_expires_at) - Date.now()).toBe(3_600_000);
    const stored = await asset(t, row.media_asset_id);
    expect(stored).toMatchObject({
      owner_user_id: couple.first.userId,
      couple_id: couple.coupleId,
      upload_status: "pending",
      storage_delete_status: "none",
      expected_bucket: "couple-media",
      expected_media_type: "image",
    });
  });

  test("a replay returns the same asset with a fresh upload URL", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const args = reserveArgs(couple.coupleId);
    const [first] = await couple.first.as.mutation(api.media.create_pending_media_upload, args);
    const [second] = await couple.first.as.mutation(api.media.create_pending_media_upload, args);
    expect(second.media_asset_id).toBe(first.media_asset_id);
    expect(second.storage_path).toBe(first.storage_path);
    expect(second.upload_url).toMatch(/^https:\/\//);
    expect(await t.run((ctx) => ctx.db.query("media_assets").collect())).toHaveLength(1);
  });

  test("a replay after losing couple access gets no upload URL", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const args = reserveArgs(couple.coupleId);
    await couple.first.as.mutation(api.media.create_pending_media_upload, args);
    await t.run(async (ctx) => {
      const member = await ctx.db
        .query("couple_members")
        .filter((q) => q.eq(q.field("user_id"), couple.first.userId))
        .first();
      await ctx.db.patch(member!._id, { status: "left", left_at: new Date().toISOString() });
    });
    const error = await failure(couple.first.as.mutation(api.media.create_pending_media_upload, args));
    expect(error).toEqual({ code: "42501", message: "active entitled couple access is required" });
  });

  test("a replay after finalize returns the finalized asset, so a retried send can finish", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const finalizeArgs = up.finalize({ p_sha256_hex: up.sha });
    const [finalized] = await couple.first.as.mutation(api.media.finalize_media_upload, finalizeArgs);
    // Sending the answer failed after finalize, so the app retries reserve, upload, and finalize.
    vi.setSystemTime(new Date("2026-10-10T14:00:00.000Z"));
    const [replay] = await couple.first.as.mutation(api.media.create_pending_media_upload, up.reserve);
    expect(replay).toMatchObject({ media_asset_id: up.row.media_asset_id, storage_path: up.row.storage_path });
    expect(replay.upload_url).toMatch(/^https:\/\//);
    expect(await couple.first.as.mutation(api.media.finalize_media_upload, finalizeArgs)).toEqual([finalized]);
    expect(await asset(t, up.row.media_asset_id)).toMatchObject({ upload_status: "finalized", storage_id: up.storageId });
  });

  test("a replay renews a reservation that ran out before the upload", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    // Past the expiry, before the cleanup job runs.
    vi.setSystemTime(new Date("2026-10-10T13:00:01.000Z"));
    const [renewed] = await couple.first.as.mutation(api.media.create_pending_media_upload, up.reserve);
    expect(renewed).toMatchObject({ media_asset_id: up.row.media_asset_id, upload_expires_at: "2026-10-10T14:00:01.000Z" });
    // After the cleanup job marked it expired.
    vi.setSystemTime(new Date("2026-10-10T15:00:00.000Z"));
    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ expired: 1 });
    const [again] = await couple.first.as.mutation(api.media.create_pending_media_upload, up.reserve);
    expect(again).toMatchObject({ media_asset_id: up.row.media_asset_id, upload_expires_at: "2026-10-10T16:00:00.000Z" });
    expect(await asset(t, up.row.media_asset_id)).toMatchObject({ upload_status: "pending", storage_delete_status: "none" });
    expect((await asset(t, up.row.media_asset_id))?.deleted_at).toBeUndefined();
    const [finalized] = await couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha }));
    expect(finalized.upload_status).toBe("finalized");
  });

  test("the same operation id with a different request is rejected", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const args = reserveArgs(couple.coupleId);
    await couple.first.as.mutation(api.media.create_pending_media_upload, args);
    const error = await failure(
      couple.first.as.mutation(api.media.create_pending_media_upload, { ...args, p_file_extension: "png" }),
    );
    expect(error).toEqual({ code: "23505", message: "client operation replay hash mismatch" });
  });

  test.each([
    ["an extension that does not match the type", { p_file_extension: "pkdrawing" }, "23514", "file extension does not match media type"],
    ["an unsupported extension", { p_file_extension: "j p g" }, "22023", "file extension is not supported"],
    ["a purpose the parent kind does not allow", { p_reserved_parent_kind: "daily_answer_media" }, "23514", "relationship media upload contract is invalid"],
    ["a purpose nobody supports", { p_upload_purpose: "banner" }, "23514", "upload purpose is not supported"],
    ["a report snapshot", { p_upload_purpose: "report_snapshot" }, "42501", "report snapshot uploads require a trusted service path"],
    ["relationship media without a couple", { p_couple_id: null }, "23514", "relationship media requires a couple id"],
    ["an expiry in the next five minutes", { p_upload_expires_at: "2026-10-10T12:04:00.000Z" }, "23514", "upload expiration is out of range"],
    ["an expiry more than a day away", { p_upload_expires_at: "2026-10-11T12:01:00.000Z" }, "23514", "upload expiration is out of range"],
    ["a path context that is not an object", { p_path_context: [1] }, "23514", "path context must be an object"],
  ])("rejects %s", async (_name, overrides, code, message) => {
    const t = newTest();
    const couple = await createCouple(t);
    const error = await failure(
      couple.first.as.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId, overrides)),
    );
    expect(error).toEqual({ code, message });
  });

  test("keeps jpeg as jpg and puts profile photos under the user id", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const [row] = await user.as.mutation(api.media.create_pending_media_upload, {
      ...op(),
      p_reserved_parent_kind: "profile_photo",
      p_reserved_parent_id: user.userId,
      p_upload_purpose: "profile_photo",
      p_media_type: "image",
      p_file_extension: ".JPEG",
    });
    expect(row.bucket).toBe("profile-photos");
    expect(row.storage_path).toBe(`${user.userId}/${row.media_asset_id}.jpg`);
    const stored = await asset(t, row.media_asset_id);
    expect(stored?.couple_id).toBeUndefined();
  });

  test("a profile photo must be reserved for the caller's own id", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const error = await failure(
      user.as.mutation(api.media.create_pending_media_upload, {
        ...op(),
        p_reserved_parent_kind: "profile_photo",
        p_reserved_parent_id: newUuid(),
        p_upload_purpose: "profile_photo",
        p_media_type: "image",
        p_file_extension: "jpg",
      }),
    );
    expect(error).toEqual({ code: "23514", message: "profile photo upload contract is invalid" });
  });

  test("widget drawings need a canvas id and are stored under the revision id", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const base = {
      ...op(),
      p_reserved_parent_kind: "widget_drawing_revision",
      p_upload_purpose: "widget_drawing_payload",
      p_media_type: "drawing_payload",
      p_file_extension: "pkdrawing",
      p_couple_id: couple.coupleId,
    };
    const revisionId = newUuid();
    const canvasId = newUuid();
    expect(
      await failure(couple.first.as.mutation(api.media.create_pending_media_upload, { ...base, p_reserved_parent_id: revisionId })),
    ).toEqual({ code: "23514", message: "widget drawing uploads require a canvas id" });
    const [row] = await couple.first.as.mutation(api.media.create_pending_media_upload, {
      ...base,
      ...op(),
      p_reserved_parent_id: revisionId,
      p_path_context: { canvas_id: canvasId.toUpperCase() },
    });
    expect(row.bucket).toBe("widget-drawings");
    expect(row.storage_path).toBe(`${couple.coupleId}/${canvasId}/revisions/${revisionId}/drawing.pkdrawing`);
  });

  test("requires an active, entitled couple member", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const unentitled = await createCouple(t, { entitled: false });
    const denied = { code: "42501", message: "active entitled couple access is required" };
    expect(
      await failure(stranger.as.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId))),
    ).toEqual(denied);
    expect(
      await failure(unentitled.first.as.mutation(api.media.create_pending_media_upload, reserveArgs(unentitled.coupleId))),
    ).toEqual(denied);
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(
      await failure(couple.first.as.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId))),
    ).toEqual(denied);
    expect(
      await failure(couple.second.as.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId))),
    ).toEqual(denied);
  });

  test("requires a signed-in user", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const error = await failure(t.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId)));
    expect(error).toEqual({ code: "42501", message: "authenticated user required" });
  });
});

describe("finalize_media_upload", () => {
  test("finalizes an upload and records what the blob holds", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const rows = await couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha.toUpperCase() }));
    expect(rows).toEqual([
      { media_asset_id: up.row.media_asset_id, upload_status: "finalized", upload_finalized_at: "2026-10-10T12:00:00.000Z" },
    ]);
    expect(await asset(t, up.row.media_asset_id)).toMatchObject({
      upload_status: "finalized",
      mime_type: "image/jpeg",
      byte_size: up.bytes.length,
      sha256: up.sha,
      width: 10,
      height: 10,
      storage_id: up.storageId,
    });
  });

  test("rejects a blob whose size differs from the declared size, then accepts a correct retry", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const error = await failure(
      couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha, p_byte_size: up.bytes.length + 1 })),
    );
    expect(error).toEqual({ code: "23514", message: "byte size is out of range" });
    expect((await asset(t, up.row.media_asset_id))?.upload_status).toBe("pending");
    await couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha }));
    expect((await asset(t, up.row.media_asset_id))?.upload_status).toBe("finalized");
  });

  test("rejects a blob whose content type differs from the declared type", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const error = await failure(
      couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha, p_mime_type: "image/png" })),
    );
    expect(error).toEqual({ code: "23514", message: "mime type does not match media type" });
    const wrongType = await storeBlob(t, up.bytes, "text/html");
    const html = await failure(
      couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha, p_storage_id: wrongType })),
    );
    expect(html).toEqual({ code: "23514", message: "mime type does not match media type" });
    const noType = await storeBlob(t, up.bytes, "");
    const missing = await failure(
      couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha, p_storage_id: noType })),
    );
    expect(missing.message).toBe("mime type does not match media type");
  });

  test("rejects bytes that do not match the declared checksum", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const error = await failure(
      couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: "0".repeat(64) })),
    );
    expect(error).toEqual({ code: "23514", message: "uploaded file does not match its sha256 checksum" });
  });

  test("a storage id that is not an id is reported as a missing upload", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const error = await failure(
      couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha, p_storage_id: "not an id" })),
    );
    expect(error).toEqual({ code: "22023", message: "reserved storage object was not found" });
  });

  test("rejects an upload that never happened and a blob already used by another asset", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const missing = await t.run(async (ctx) => {
      const id = await ctx.storage.store(new Blob(["x"]));
      await ctx.storage.delete(id);
      return id;
    });
    expect(
      await failure(couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha, p_storage_id: missing }))),
    ).toEqual({ code: "22023", message: "reserved storage object was not found" });

    await couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha }));
    const other = await reserveAndStore(t, couple.first, couple.coupleId);
    const reuse = await failure(
      couple.first.as.mutation(
        api.media.finalize_media_upload,
        other.finalize({ p_sha256_hex: up.sha, p_storage_id: up.storageId, p_byte_size: up.bytes.length }),
      ),
    );
    expect(reuse.code).toBe("23505");
  });

  test("a replay returns the stored result, and different metadata is rejected", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const args = up.finalize({ p_sha256_hex: up.sha });
    const [first] = await couple.first.as.mutation(api.media.finalize_media_upload, args);
    vi.setSystemTime(new Date("2026-10-10T12:30:00.000Z"));
    const [replay] = await couple.first.as.mutation(api.media.finalize_media_upload, args);
    expect(replay).toEqual(first);

    const [again] = await couple.first.as.mutation(api.media.finalize_media_upload, { ...args, ...op() });
    expect(again).toEqual(first);

    const changed = await failure(
      couple.first.as.mutation(api.media.finalize_media_upload, { ...args, ...op(), p_width: 11 }),
    );
    expect(changed).toEqual({ code: "23505", message: "finalized media metadata cannot be changed" });
  });

  test("rejects an expired reservation without changing it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    vi.setSystemTime(new Date("2026-10-10T13:00:01.000Z"));
    const error = await failure(couple.first.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: up.sha })));
    expect(error).toEqual({ code: "22023", message: "media upload reservation is expired" });
  });

  test("checks ownership, the reservation, and the media rules", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await reserveAndStore(t, couple.first, couple.coupleId);
    const sha = up.sha;
    const finalize = (user: TestUser, overrides: Record<string, unknown>) =>
      failure(user.as.mutation(api.media.finalize_media_upload, up.finalize({ p_sha256_hex: sha, ...overrides })));
    expect(await finalize(couple.second, {})).toEqual({ code: "42501", message: "media asset is owned by another user" });
    expect(await finalize(couple.first, { p_media_asset_id: newUuid() })).toEqual({
      code: "22023",
      message: "media asset was not found",
    });
    expect(await finalize(couple.first, { p_storage_path: "elsewhere.jpg" })).toEqual({
      code: "23514",
      message: "finalize request does not match the reserved upload",
    });
    expect(await finalize(couple.first, { p_sha256_hex: "abc" })).toEqual({
      code: "22023",
      message: "sha256 must be a 64 character hex string",
    });
    expect(await finalize(couple.first, { p_byte_size: 20_000_000 })).toEqual({
      code: "23514",
      message: "byte size is out of range",
    });
    expect(await finalize(couple.first, { p_mime_type: "application/pdf" })).toEqual({
      code: "23514",
      message: "mime type does not match media type",
    });
    expect(await finalize(couple.first, { p_width: null })).toEqual({
      code: "23514",
      message: "image uploads require dimensions",
    });
  });

  test("a voice note needs a duration", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const operationId = newUuid();
    const parentId = newUuid();
    const [row] = await couple.first.as.mutation(api.media.create_pending_media_upload, {
      ...reserveArgs(couple.coupleId, { ...op(operationId), p_reserved_parent_id: parentId }),
      p_upload_purpose: "voice_note",
      p_media_type: "voice",
      p_file_extension: "m4a",
    });
    const bytes = new TextEncoder().encode("voice");
    const storageId = await storeBlob(t, bytes, "audio/mp4");
    const args = {
      ...op(),
      p_media_asset_id: row.media_asset_id,
      p_reserved_by_client_operation_id: operationId,
      p_bucket: row.bucket,
      p_storage_path: row.storage_path,
      p_storage_id: storageId,
      p_reserved_parent_kind: "memory_media",
      p_reserved_parent_id: parentId,
      p_upload_purpose: "voice_note",
      p_media_type: "voice",
      p_mime_type: "audio/mp4",
      p_byte_size: bytes.length,
      p_sha256_hex: await sha256Hex(bytes),
    };
    expect(await failure(couple.first.as.mutation(api.media.finalize_media_upload, args))).toEqual({
      code: "23514",
      message: "voice uploads require duration",
    });
    const [ok] = await couple.first.as.mutation(api.media.finalize_media_upload, { ...args, p_duration_ms: 900 });
    expect(ok.upload_status).toBe("finalized");
  });
});

describe("get_media_signed_url and GET /media", () => {
  async function memoryWithPhoto(t: TestConvex, couple: Awaited<ReturnType<typeof createCouple>>) {
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId));
    await couple.first.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: newUuid(),
      p_title: "Trip",
      p_memory_date: "2026-10-01",
      p_note_body: null,
      p_media_asset_ids: [up.assetId],
    });
    return up;
  }

  const pathOf = (signedUrl: string) => {
    const url = new URL(signedUrl);
    return `${url.pathname}${url.search}`;
  };

  test("returns the SQL columns plus a signed URL that serves the file", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    const [row] = await couple.second.as.mutation(api.media.get_media_signed_url, {
      p_media_asset_id: up.assetId.toUpperCase(),
      p_expires_in_seconds: 600,
    });
    expect(row).toMatchObject({
      media_asset_id: up.assetId,
      bucket: "couple-media",
      storage_path: up.storagePath,
      expires_in_seconds: 600,
      signed_url_expires_at: "2026-10-10T12:10:00.000Z",
    });
    expect(row.signed_url.startsWith("https://actions.example.test/media?asset=")).toBe(true);

    const response = await t.fetch(pathOf(row.signed_url));
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("image/jpeg");
    expect(response.headers.get("Cache-Control")).toMatch(/^private/);
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(up.bytes);
  });

  test("the default lifetime is 15 minutes", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    const [row] = await couple.first.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId });
    expect(row.expires_in_seconds).toBe(900);
    expect(row.signed_url_expires_at).toBe("2026-10-10T12:15:00.000Z");
  });

  test("an expired link is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    const [row] = await couple.first.as.mutation(api.media.get_media_signed_url, {
      p_media_asset_id: up.assetId,
      p_expires_in_seconds: 60,
    });
    vi.setSystemTime(new Date("2026-10-10T12:00:59.000Z"));
    expect((await t.fetch(pathOf(row.signed_url))).status).toBe(200);
    vi.setSystemTime(new Date("2026-10-10T12:01:01.000Z"));
    expect((await t.fetch(pathOf(row.signed_url))).status).toBe(403);
  });

  test("a tampered link is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    const other = await memoryWithPhoto(t, couple);
    const [row] = await couple.first.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId });
    const url = new URL(row.signed_url);
    const withParam = (name: string, value: string) => {
      const copy = new URL(url);
      copy.searchParams.set(name, value);
      return `${copy.pathname}${copy.search}`;
    };
    const exp = Number(url.searchParams.get("exp"));
    expect((await t.fetch(withParam("exp", String(exp + 3600)))).status).toBe(403);
    expect((await t.fetch(withParam("asset", other.assetId))).status).toBe(403);
    const sig = url.searchParams.get("sig")!;
    expect((await t.fetch(withParam("sig", `${sig.slice(0, 63)}${sig.endsWith("0") ? "1" : "0"}`))).status).toBe(403);
    expect((await t.fetch(withParam("sig", "0".repeat(64)))).status).toBe(403);
    expect((await t.fetch(withParam("sig", ""))).status).toBe(403);
    expect((await t.fetch(withParam("asset", "not-a-uuid"))).status).toBe(400);
    expect((await t.fetch("/media")).status).toBe(400);
    expect((await t.fetch(pathOf(row.signed_url))).status).toBe(200);
  });

  test("a signed link stops working once the file is deleted", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    const [row] = await couple.first.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId });
    await t.run(async (ctx) => {
      const found = await ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", up.assetId)).unique();
      await ctx.db.patch(found!._id, { storage_delete_status: "pending", deleted_at: new Date().toISOString() });
    });
    expect((await t.fetch(pathOf(row.signed_url))).status).toBe(404);
  });

  test("rejects an expiry outside 60 to 3600 seconds", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    for (const seconds of [59, 3601, 1.5]) {
      expect(
        await failure(couple.first.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId, p_expires_in_seconds: seconds })),
      ).toEqual({ code: "23514", message: "signed URL expiration is out of range" });
    }
  });

  test("refuses everyone who may not read the asset", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    const pending = (await couple.first.as.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId)))[0];
    const stranger = await createSignedInUser(t);
    const unavailable = { code: "42501", message: "media asset is not available" };
    const read = (user: TestUser, id: string) => failure(user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: id }));

    expect(await read(stranger, up.assetId)).toEqual(unavailable);
    expect(await read(couple.first, pending.media_asset_id)).toEqual(unavailable);
    expect(await read(couple.first, newUuid())).toEqual(unavailable);

    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await read(couple.first, up.assetId)).toEqual(unavailable);
    expect(await read(couple.second, up.assetId)).toEqual(unavailable);
  });

  test("an unentitled couple cannot read its media", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await memoryWithPhoto(t, couple);
    await t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    const error = await failure(couple.second.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId }));
    expect(error).toEqual({ code: "42501", message: "media asset is not available" });
  });

  test("a media asset not linked to a live memory is not readable", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId));
    expect(
      await failure(couple.first.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId })),
    ).toEqual({ code: "42501", message: "media asset is not available" });
  });

  test("a widget drawing payload is readable by the couple only", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const [canvas] = await couple.first.as.mutation(api.widget.get_or_create_widget_canvas, {});
    const revisionId = newUuid();
    const up = await uploadAsset(t, couple.first, {
      kind: "widget_drawing_revision",
      purpose: "widget_drawing_payload",
      mediaType: "drawing_payload",
      extension: "pkdrawing",
      mime: "application/x-pkdrawing",
      parentId: revisionId,
      coupleId: couple.coupleId,
      canvasId: canvas.canvas_id,
    });
    const read = (user: TestUser) => user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId });
    expect(await failure(read(couple.second))).toMatchObject({ code: "42501" });
    await couple.first.as.mutation(api.widget.submit_widget_drawing_revision, {
      ...op(),
      p_canvas_id: canvas.canvas_id,
      p_payload_media_asset_id: up.assetId,
      p_parent_revision_id: null,
      p_payload_bytes: up.bytes.length,
      p_sha256_hex: up.sha256,
      p_client_decode_validated_at: new Date().toISOString(),
      p_client_renderer_version: "r1",
      p_client_validation_version: "v1",
    });
    const [row] = await read(couple.second);
    expect(row).toMatchObject({ bucket: "widget-drawings" });
    const served = await t.fetch(pathOf(row.signed_url));
    expect(served.headers.get("Content-Type")).toBe("application/x-pkdrawing");
    expect(await failure(read(stranger))).toMatchObject({ code: "42501" });
  });

  test("a daily answer photo is readable once the viewer has answered too", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId, "daily_answer_media", "daily_answer_media"));
    const instanceId = newUuid();
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      const dayId = newUuid();
      await ctx.db.insert("couple_days", {
        id: dayId, couple_id: couple.coupleId, local_date: "2026-10-10", anchor_time_zone_id: "UTC",
        starts_at: "2026-10-10T00:00:00.000Z", ends_at: "2026-10-11T00:00:00.000Z", created_at: now,
      });
      await ctx.db.insert("daily_question_instances", {
        id: instanceId, couple_day_id: dayId, couple_id: couple.coupleId, question_id: newUuid(), question_version_id: newUuid(),
        seeded_for_user_id: couple.first.userId, slot_number: 1, status: "active", created_at: now,
      });
      const answerId = newUuid();
      await ctx.db.insert("daily_question_answers", {
        id: answerId, instance_id: instanceId, user_id: couple.first.userId, moderation_status: "visible", created_at: now, updated_at: now,
      });
      await ctx.db.insert("daily_answer_media", { answer_id: answerId, media_asset_id: up.assetId, sort_order: 1 });
    });
    const read = (user: TestUser) => user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId });
    expect(await read(couple.first)).toHaveLength(1);
    expect(await failure(read(couple.second))).toMatchObject({ code: "42501" });
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      await ctx.db.insert("daily_question_answers", {
        id: newUuid(), instance_id: instanceId, user_id: couple.second.userId, moderation_status: "visible", created_at: now, updated_at: now,
      });
    });
    expect(await read(couple.second)).toHaveLength(1);
  });

  test("a profile photo is readable by its owner and the partner only", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const spec: UploadSpec = {
      kind: "profile_photo",
      purpose: "profile_photo",
      mediaType: "image",
      extension: "jpg",
      mime: "image/jpeg",
      parentId: couple.first.userId,
    };
    const up = await uploadAsset(t, couple.first, spec);
    const read = (user: TestUser) => user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId });

    expect(await read(couple.first)).toHaveLength(1);
    expect(await failure(read(couple.second))).toMatchObject({ code: "42501" });

    await t.run(async (ctx) => {
      const profile = await ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", couple.first.userId)).unique();
      await ctx.db.patch(profile!._id, { profile_photo_asset_id: up.assetId });
    });
    expect(await read(couple.second)).toHaveLength(1);
    expect(await failure(read(stranger))).toMatchObject({ code: "42501" });

    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(read(couple.second))).toMatchObject({ code: "42501" });
  });
});

describe("mark_media_for_deletion", () => {
  async function profilePhoto(t: TestConvex, user: TestUser) {
    return await uploadAsset(t, user, {
      kind: "profile_photo",
      purpose: "profile_photo",
      mediaType: "image",
      extension: "jpg",
      mime: "image/jpeg",
      parentId: user.userId,
    });
  }

  test("queues an unreferenced profile photo and nothing else", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await profilePhoto(t, couple.first);
    const mark = (user: TestUser, id: string) => user.as.mutation(api.media.mark_media_for_deletion, { p_media_asset_id: id });

    expect(await mark(couple.second, up.assetId)).toBe(false);
    expect(await mark(couple.first, newUuid())).toBe(false);
    expect(await mark(couple.first, up.assetId)).toBe(true);
    expect(await asset(t, up.assetId)).toMatchObject({ storage_delete_status: "pending", deleted_at: "2026-10-10T12:00:00.000Z" });
    expect(await mark(couple.first, up.assetId)).toBe(true);
  });

  test("keeps a photo the profile still uses", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const up = await profilePhoto(t, user);
    await t.run(async (ctx) => {
      const profile = await ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", user.userId)).unique();
      await ctx.db.patch(profile!._id, { profile_photo_asset_id: up.assetId });
    });
    expect(await user.as.mutation(api.media.mark_media_for_deletion, { p_media_asset_id: up.assetId })).toBe(false);
    expect((await asset(t, up.assetId))?.storage_delete_status).toBe("none");
  });

  test("does not touch couple media", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId));
    expect(await couple.first.as.mutation(api.media.mark_media_for_deletion, { p_media_asset_id: up.assetId })).toBe(false);
  });
});

describe("storage cleanup", () => {
  const blobExists = (t: TestConvex, storageId: string) =>
    t.run(async (ctx) => (await ctx.db.system.get(storageId as never)) !== null);

  async function queueForDelete(t: TestConvex, assetId: string, patch: Record<string, unknown> = {}) {
    await t.run(async (ctx) => {
      const found = await ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", assetId)).unique();
      await ctx.db.patch(found!._id, {
        storage_delete_status: "pending",
        deleted_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        ...patch,
      } as never);
    });
  }

  test("deletes the blob of a queued asset and marks it deleted", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId));
    await queueForDelete(t, up.assetId);
    const result = await t.mutation(internal.media.cleanup_media_storage, {});
    expect(result).toEqual({ expired: 0, claimed: 1, deleted: 1, failed: 0 });
    expect(await blobExists(t, up.storageId)).toBe(false);
    const stored = await asset(t, up.assetId);
    expect(stored).toMatchObject({ storage_delete_status: "deleted", storage_delete_attempts: 1 });
    expect(stored?.storage_deleted_at).toBe("2026-10-10T12:00:00.000Z");
    expect(stored?.storage_id).toBeUndefined();
    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ claimed: 0 });
  });

  test("keeps the blob while a live row still references the asset", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await uploadAsset(t, couple.first, photo(couple.coupleId));
    await couple.first.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: newUuid(),
      p_title: "Kept",
      p_memory_date: "2026-10-01",
      p_media_asset_ids: [up.assetId],
    });
    await queueForDelete(t, up.assetId);
    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ claimed: 0, deleted: 0 });
    expect(await blobExists(t, up.storageId)).toBe(true);
    // It leaves the queue, and the orphan check queues it again once the memory is gone.
    expect((await asset(t, up.assetId))?.storage_delete_status).toBe("failed");
  });

  test("a retrying asset waits 15 minutes and a spent asset is skipped", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const waiting = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const spent = await uploadAsset(t, couple.first, photo(couple.coupleId));
    await queueForDelete(t, waiting.assetId, { storage_delete_status: "retrying", storage_delete_attempts: 1 });
    await queueForDelete(t, spent.assetId, { storage_delete_status: "retrying", storage_delete_attempts: 5, updated_at: "2026-10-10T10:00:00.000Z" });

    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ claimed: 0 });
    vi.setSystemTime(new Date("2026-10-10T12:15:01.000Z"));
    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ claimed: 1, deleted: 1 });
    expect((await asset(t, waiting.assetId))?.storage_delete_status).toBe("deleted");
    // The spent asset leaves the queue instead of being read again on every run.
    expect((await asset(t, spent.assetId))?.storage_delete_status).toBe("failed");
    expect(await blobExists(t, spent.storageId)).toBe(true);
  });

  test("expires reservations that were never uploaded", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const [row] = await couple.first.as.mutation(api.media.create_pending_media_upload, reserveArgs(couple.coupleId));
    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ expired: 0 });
    vi.setSystemTime(new Date("2026-10-10T13:00:01.000Z"));
    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ expired: 1 });
    expect(await asset(t, row.media_asset_id)).toMatchObject({
      upload_status: "expired",
      storage_delete_status: "deleted",
      deleted_at: "2026-10-10T13:00:01.000Z",
    });
  });

  test("the orphan sweep queues unreferenced assets and removes unreferenced blobs", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const orphanAsset = await uploadAsset(t, couple.first, photo(couple.coupleId));
    const rejected = await storeBlob(t, new TextEncoder().encode("rejected"), "image/jpeg");
    const recent = await storeBlob(t, new TextEncoder().encode("recent"), "image/jpeg");
    vi.setSystemTime(new Date("2026-10-11T14:00:00.000Z"));
    const fresh = await storeBlob(t, new TextEncoder().encode("fresh"), "image/jpeg");

    const result = await t.mutation(internal.media.sweep_orphan_storage, {});
    expect(result).toEqual({ queued: 0, blobs: 2 });
    expect(await blobExists(t, rejected)).toBe(false);
    expect(await blobExists(t, recent)).toBe(false);
    expect(await blobExists(t, fresh)).toBe(true);
    // A day-old upload may still be waiting for an offline write to attach it.
    expect((await asset(t, orphanAsset.assetId))?.storage_delete_status).toBe("none");

    vi.setSystemTime(new Date("2026-10-17T12:00:01.000Z"));
    expect(await t.mutation(internal.media.sweep_orphan_storage, {})).toMatchObject({ queued: 1 });
    // The finalized asset's blob is referenced, so the sweep keeps it until the asset is deleted.
    expect(await blobExists(t, orphanAsset.storageId)).toBe(true);
    expect((await asset(t, orphanAsset.assetId))?.storage_delete_status).toBe("pending");
    expect(await t.mutation(internal.media.cleanup_media_storage, {})).toMatchObject({ deleted: 1 });
    expect(await blobExists(t, orphanAsset.storageId)).toBe(false);
  });

  test("the sweep keeps blobs that a report snapshot uses", async () => {
    const t = newTest();
    const storageId = await storeBlob(t, new TextEncoder().encode("snapshot"), "application/json");
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      await ctx.db.insert("report_snapshot_assets", {
        id: newUuid(),
        report_id: newUuid(),
        source_bucket: "couple-media",
        source_storage_path: "a/b.jpg",
        bucket: "report-snapshots",
        storage_path: "r/b.jpg",
        media_type: "image",
        copy_status: "copied",
        storage_delete_status: "none",
        storage_delete_attempts: 0,
        storage_id: storageId as never,
        created_at: now,
        updated_at: now,
      });
    });
    vi.setSystemTime(new Date("2026-10-11T14:00:00.000Z"));
    expect(await t.mutation(internal.media.sweep_orphan_storage, {})).toMatchObject({ blobs: 0 });
    expect(await blobExists(t, storageId)).toBe(true);
  });
});
