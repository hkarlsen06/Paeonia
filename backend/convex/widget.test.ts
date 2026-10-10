import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op, setMediaEnv, uploadAsset } from "./media.testing";
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
const canvasOf = async (user: TestUser) => (await user.as.mutation(api.widget.get_or_create_widget_canvas, {}))[0];

type Submitted = { canvas_id: string; revision_id: string; active_revision_id: string; payload_media_asset_id: string; created_at: string; updated_at: string };

/** Uploads a drawing payload and submits it as the next revision. */
async function submitDrawing(
  t: TestConvex,
  user: TestUser,
  couple: TestCouple,
  canvasId: string,
  parent: string | null,
  overrides: Record<string, unknown> = {},
): Promise<{ row: Submitted; revisionId: string; assetId: string }> {
  const revisionId = newUuid();
  const up = await uploadAsset(t, user, {
    kind: "widget_drawing_revision",
    purpose: "widget_drawing_payload",
    mediaType: "drawing_payload",
    extension: "pkdrawing",
    mime: "application/octet-stream",
    parentId: revisionId,
    coupleId: couple.coupleId,
    canvasId,
  });
  const [row] = await user.as.mutation(api.widget.submit_widget_drawing_revision, {
    ...op(),
    p_canvas_id: canvasId,
    p_payload_media_asset_id: up.assetId,
    p_parent_revision_id: parent,
    p_payload_bytes: up.bytes.length,
    p_uncompressed_bytes: up.bytes.length,
    p_compression: "none",
    p_stroke_count: 3,
    p_point_count: 40,
    p_bounds: { x: 0, y: 0, width: 10, height: 10 },
    p_sha256_hex: up.sha256,
    p_client_decode_validated_at: new Date().toISOString(),
    p_client_renderer_version: "r1",
    p_client_validation_version: "v1",
    ...overrides,
  });
  return { row, revisionId, assetId: up.assetId };
}

/** Submit arguments for an asset that is already uploaded. */
async function prepared(t: TestConvex, user: TestUser, couple: TestCouple, canvasId: string, parent: string | null = null) {
  const revisionId = newUuid();
  const up = await uploadAsset(t, user, {
    kind: "widget_drawing_revision",
    purpose: "widget_drawing_payload",
    mediaType: "drawing_payload",
    extension: "pkdrawing",
    mime: "application/octet-stream",
    parentId: revisionId,
    coupleId: couple.coupleId,
    canvasId,
  });
  const args = {
    p_canvas_id: canvasId,
    p_payload_media_asset_id: up.assetId,
    p_parent_revision_id: parent,
    p_payload_bytes: up.bytes.length,
    p_uncompressed_bytes: up.bytes.length,
    p_compression: "none",
    p_stroke_count: 3,
    p_point_count: 40,
    p_bounds: { x: 0, y: 0 },
    p_sha256_hex: up.sha256,
    p_client_decode_validated_at: new Date().toISOString(),
    p_client_renderer_version: "r1",
    p_client_validation_version: "v1",
  };
  return { up, revisionId, submit: (overrides: Record<string, unknown> = {}) => user.as.mutation(api.widget.submit_widget_drawing_revision, { ...op(), ...args, ...overrides }) };
}

describe("get_or_create_widget_canvas", () => {
  test("creates one canvas per couple and returns it every time", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const first = await couple.first.as.mutation(api.widget.get_or_create_widget_canvas, {});
    expect(first).toEqual([
      {
        canvas_id: expect.any(String),
        couple_id: couple.coupleId,
        active_revision_id: null,
        created_at: "2026-10-10T12:00:00.000Z",
        updated_at: "2026-10-10T12:00:00.000Z",
      },
    ]);
    expect(await couple.second.as.mutation(api.widget.get_or_create_widget_canvas, { p_couple_id: couple.coupleId.toUpperCase() })).toEqual(first);
    expect(await couple.first.as.mutation(api.widget.get_or_create_widget_canvas, { p_couple_id: null })).toEqual(first);
    expect(await t.run((ctx) => ctx.db.query("widget_canvases").collect())).toHaveLength(1);
  });

  test("refuses strangers, former partners, and unentitled couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const unentitled = await createCouple(t, { entitled: false });
    const denied = { code: "42501", message: "active entitled couple access is required" };
    expect(await failure(stranger.as.mutation(api.widget.get_or_create_widget_canvas, {}))).toEqual(denied);
    expect(await failure(stranger.as.mutation(api.widget.get_or_create_widget_canvas, { p_couple_id: couple.coupleId }))).toEqual(denied);
    expect(await failure(unentitled.first.as.mutation(api.widget.get_or_create_widget_canvas, {}))).toEqual(denied);
    expect(await failure(unentitled.first.as.query(api.widget.get_widget_canvas, {}))).toEqual(denied);
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(couple.second.as.mutation(api.widget.get_or_create_widget_canvas, {}))).toEqual(denied);
    expect(await failure(couple.first.as.mutation(api.widget.get_or_create_widget_canvas, { p_couple_id: couple.coupleId }))).toEqual(denied);
    expect(await t.run((ctx) => ctx.db.query("widget_canvases").collect())).toHaveLength(0);
  });
});

describe("submit_widget_drawing_revision", () => {
  test("saves the revision and makes it the canvas's active revision", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    tick();
    const { row, revisionId, assetId } = await submitDrawing(t, couple.first, couple, canvas.canvas_id, null);
    expect(row).toEqual({
      canvas_id: canvas.canvas_id,
      revision_id: revisionId,
      active_revision_id: revisionId,
      payload_media_asset_id: assetId,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });
    const revision = await t.run((ctx) => ctx.db.query("widget_drawing_revisions").first());
    expect(revision).toMatchObject({
      id: revisionId,
      author_user_id: couple.first.userId,
      format: "pkdrawing",
      format_version: 1,
      compression: "none",
      stroke_count: 3,
      point_count: 40,
      bounds: { x: 0, y: 0, width: 10, height: 10 },
      renderer_version: 1,
      client_renderer_version: "r1",
      moderation_status: "visible",
    });
    expect(revision?.parent_revision_id).toBeUndefined();
    expect((await canvasOf(couple.second)).active_revision_id).toBe(revisionId);
  });

  test("a stale parent is a conflict, and the next revision chains to the latest", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const first = await submitDrawing(t, couple.first, couple, canvas.canvas_id, null);
    const stale = await prepared(t, couple.second, couple, canvas.canvas_id, null);
    expect(await failure(stale.submit())).toEqual({ code: "40001", message: "widget drawing parent revision conflict" });
    expect(await failure(stale.submit({ p_parent_revision_id: newUuid() }))).toEqual({
      code: "40001",
      message: "widget drawing parent revision conflict",
    });
    expect(await t.run((ctx) => ctx.db.query("widget_drawing_revisions").collect())).toHaveLength(1);

    tick();
    const [row] = await stale.submit({ p_parent_revision_id: first.revisionId.toUpperCase() });
    expect(row.active_revision_id).toBe(stale.revisionId);
    const revision = await t.run((ctx) => ctx.db.query("widget_drawing_revisions").withIndex("by_uuid", (q) => q.eq("id", stale.revisionId)).unique());
    expect(revision?.parent_revision_id).toBe(first.revisionId);
  });

  test("a replay returns the first answer and the same drawing is not saved twice", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const drawing = await prepared(t, couple.first, couple, canvas.canvas_id);
    const args = { ...op() };
    const [first] = await drawing.submit(args);
    expect(await drawing.submit(args)).toEqual([first]);
    expect(await t.run((ctx) => ctx.db.query("widget_drawing_revisions").collect())).toHaveLength(1);

    const second = await prepared(t, couple.first, couple, canvas.canvas_id, first.revision_id);
    await second.submit();
    expect(await failure(second.submit({ p_parent_revision_id: first.revision_id }))).toEqual({
      code: "40001",
      message: "widget drawing parent revision conflict",
    });
    expect(await failure(drawing.submit({ p_parent_revision_id: null }))).toEqual({
      code: "40001",
      message: "widget drawing parent revision conflict",
    });
  });

  test("records activity and queues the widget push, the silent refresh, and the alert", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const partnerDevice = await addDevice(t, couple.second.userId, { locale: "nb-NO", token: "p" });
    await addDevice(t, couple.first.userId, { token: "a" });
    await couple.second.as.mutation(api.widget.register_widget_push_device, {
      p_widget_kind: "PaeoniaWidget",
      p_widget_push_token: "w".repeat(64),
      p_apns_environment: "sandbox",
    });
    await couple.first.as.mutation(api.widget.register_widget_push_device, {
      p_widget_kind: "PaeoniaWidget",
      p_widget_push_token: "x".repeat(64),
      p_apns_environment: "sandbox",
    });
    const canvas = await canvasOf(couple.first);
    const { revisionId } = await submitDrawing(t, couple.first, couple, canvas.canvas_id, null);

    const events = await t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events).toMatchObject([
      { activity_kind: "widget_drawing_saved", dedupe_key: `widget_drawing_saved:${revisionId}`, metadata: { canvas_id: canvas.canvas_id }, user_id: couple.first.userId },
    ]);

    const payload = {
      type: "widget_updated",
      couple_id: couple.coupleId,
      canvas_id: canvas.canvas_id,
      revision_id: revisionId,
      actor_user_id: couple.first.userId,
      route: "widget",
      deeplink: "paeonia://widget/drawing",
    };
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.map((row) => [row.apns_push_type, row.recipient_user_id, row.title ?? null, row.body ?? null])).toEqual([
      ["background", couple.second.userId, null, null],
      ["alert", couple.second.userId, "First Partner", "La til en ny tegning"],
    ]);
    expect(outbox[0].payload).toEqual(payload);
    expect(outbox[0].dedupe_key).toBe(`widget_updated:${revisionId}:${partnerDevice.id}`);
    expect(outbox[0].apns_collapse_id).toBe(`widget:${couple.coupleId}`);
    expect(outbox[1].dedupe_key).toBe(`widget_updated_alert:${revisionId}:${partnerDevice.id}`);

    const pushes = await t.run((ctx) => ctx.db.query("widget_push_outbox").collect());
    expect(pushes).toHaveLength(1);
    expect(pushes[0]).toMatchObject({ recipient_user_id: couple.second.userId, payload, dedupe_key: `widgetkit:${revisionId}`, apns_collapse_id: `widget:${couple.coupleId}` });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the alert respects the partner's widget toggle but the silent refresh does not", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").withIndex("by_user_id", (q) => q.eq("user_id", couple.second.userId)).unique();
      await ctx.db.patch(preference!._id, { widget_updates_enabled: false });
    });
    const canvas = await canvasOf(couple.first);
    await submitDrawing(t, couple.first, couple, canvas.canvas_id, null);
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.map((row) => row.apns_push_type)).toEqual(["background"]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test.each([
    ["an unknown compression", { p_compression: "zip" }, "23514", "widget drawing compression is not supported"],
    ["zero bytes", { p_payload_bytes: 0 }, "23514", "widget drawing payload bytes are out of range"],
    ["a payload over 2 MiB", { p_payload_bytes: 2_097_153 }, "23514", "widget drawing payload bytes are out of range"],
    ["an uncompressed size over 2 MiB", { p_uncompressed_bytes: 2_097_153 }, "23514", "widget drawing uncompressed bytes are out of range"],
    ["uncompressed bytes that differ without compression", { p_uncompressed_bytes: 99 }, "23514", "widget drawing compression metadata is invalid"],
    ["gzip that grows smaller", { p_compression: "gzip", p_uncompressed_bytes: 1 }, "23514", "widget drawing compression metadata is invalid"],
    ["too many strokes", { p_stroke_count: 5001 }, "23514", "widget drawing stroke count is out of range"],
    ["too many points", { p_point_count: 200_001 }, "23514", "widget drawing point count is out of range"],
    ["bounds that are not an object", { p_bounds: [1] }, "23514", "widget drawing bounds metadata is invalid"],
    ["a short checksum", { p_sha256_hex: "abc" }, "22023", "widget drawing sha256 must be a 64 character hex string"],
    ["a blank renderer version", { p_client_renderer_version: "  " }, "23514", "widget drawing client validation metadata is invalid"],
    ["a long validation version", { p_client_validation_version: "v".repeat(81) }, "23514", "widget drawing client validation metadata is invalid"],
    ["a validation time in the future", { p_client_decode_validated_at: "2026-10-10T12:06:00.000Z" }, "23514", "widget drawing client decode validation timestamp is invalid"],
  ])("rejects %s", async (_name, overrides, code, message) => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const drawing = await prepared(t, couple.first, couple, canvas.canvas_id);
    expect(await failure(drawing.submit(overrides))).toEqual({ code, message });
    expect(await t.run((ctx) => ctx.db.query("widget_drawing_revisions").collect())).toHaveLength(0);
  });

  test("rejects payloads the caller does not own or that do not match", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const mine = await prepared(t, couple.first, couple, canvas.canvas_id);
    const unusable = { code: "23514", message: "widget drawing payload asset is not usable" };

    expect(await failure(mine.submit({ p_payload_media_asset_id: newUuid() }))).toEqual({
      code: "22023",
      message: "widget drawing payload asset was not found",
    });
    expect(await failure(mine.submit({ p_sha256_hex: "1".repeat(64) }))).toEqual(unusable);
    expect(await failure(mine.submit({ p_payload_bytes: mine.up.bytes.length + 1, p_uncompressed_bytes: mine.up.bytes.length + 1 }))).toEqual(unusable);
    const theirs = await prepared(t, couple.second, couple, canvas.canvas_id);
    expect(await failure(mine.submit({ p_payload_media_asset_id: theirs.up.assetId, p_sha256_hex: theirs.up.sha256 }))).toEqual(unusable);

    await mine.submit();
    const again = await failure(mine.submit({ p_parent_revision_id: mine.revisionId }));
    expect(again.code).toBe("23505");
    expect(again.message).toBe("widget drawing payload asset was already saved");
  });

  test("refuses strangers, former partners, and unentitled couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const drawing = await prepared(t, couple.first, couple, canvas.canvas_id);
    const stranger = await createSignedInUser(t);
    const denied = { code: "42501", message: "active entitled widget canvas access is required" };
    const asStranger = (overrides: Record<string, unknown> = {}) =>
      stranger.as.mutation(api.widget.submit_widget_drawing_revision, {
        ...op(),
        p_canvas_id: canvas.canvas_id,
        p_payload_media_asset_id: drawing.up.assetId,
        p_parent_revision_id: null,
        p_payload_bytes: drawing.up.bytes.length,
        p_sha256_hex: drawing.up.sha256,
        p_client_decode_validated_at: new Date().toISOString(),
        p_client_renderer_version: "r1",
        p_client_validation_version: "v1",
        ...overrides,
      });
    expect(await failure(asStranger())).toEqual(denied);
    expect(await failure(drawing.submit({ p_canvas_id: newUuid() }))).toEqual(denied);

    await t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect(await failure(drawing.submit())).toEqual(denied);
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      await ctx.db.insert("entitlement_grants", {
        id: newUuid(), user_id: couple.first.userId, grant_kind: "lifetime", status: "active", scope: "user", granted_at: now, created_at: now, updated_at: now,
      });
    });
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(drawing.submit())).toEqual(denied);
    expect(await t.run((ctx) => ctx.db.query("widget_drawing_revisions").collect())).toHaveLength(0);
  });
});

describe("reads", () => {
  test("get_widget_canvas is empty-valued before the first drawing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await couple.first.as.query(api.widget.get_widget_canvas, {})).toEqual([]);
    const canvas = await canvasOf(couple.first);
    const [row] = await couple.first.as.query(api.widget.get_widget_canvas, { p_couple_id: couple.coupleId });
    expect(row).toMatchObject({
      canvas_id: canvas.canvas_id,
      couple_id: couple.coupleId,
      active_revision_id: null,
      active_revision_moderation_status: null,
      active_revision_deleted_at: null,
      active_revision_author_user_id: null,
      payload_media_asset_id: null,
      payload_bucket: null,
      payload_sha256_hex: null,
      payload_bytes: null,
      bounds: null,
      revision_created_at: null,
      canvas_created_at: "2026-10-10T12:00:00.000Z",
      canvas_updated_at: "2026-10-10T12:00:00.000Z",
      sync_updated_at: "2026-10-10T12:00:00.000Z",
    });
  });

  test("get_widget_canvas returns the active payload, and hides it when the revision is hidden", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    tick();
    const { revisionId, assetId } = await submitDrawing(t, couple.first, couple, canvas.canvas_id, null);
    const asset = await t.run((ctx) => ctx.db.query("media_assets").first());
    const [row] = await couple.second.as.query(api.widget.get_widget_canvas, {});
    expect(row).toEqual({
      canvas_id: canvas.canvas_id,
      couple_id: couple.coupleId,
      active_revision_id: revisionId,
      active_revision_moderation_status: "visible",
      active_revision_deleted_at: null,
      active_revision_author_user_id: couple.first.userId,
      payload_media_asset_id: assetId,
      payload_bucket: "widget-drawings",
      payload_storage_path: asset?.storage_path,
      payload_sha256_hex: asset?.sha256,
      payload_bytes: asset?.byte_size,
      uncompressed_bytes: asset?.byte_size,
      compression: "none",
      stroke_count: 3,
      point_count: 40,
      bounds: { x: 0, y: 0, width: 10, height: 10 },
      format: "pkdrawing",
      format_version: 1,
      renderer_version: 1,
      client_decode_validated_at: expect.any(String),
      client_renderer_version: "r1",
      client_validation_version: "v1",
      revision_created_at: expect.any(String),
      canvas_created_at: "2026-10-10T12:00:00.000Z",
      canvas_updated_at: expect.any(String),
      sync_updated_at: expect.any(String),
    });

    await t.run(async (ctx) => {
      const revision = await ctx.db.query("widget_drawing_revisions").first();
      await ctx.db.patch(revision!._id, { moderation_status: "hidden" });
    });
    const [hidden] = await couple.second.as.query(api.widget.get_widget_canvas, {});
    expect(hidden).toMatchObject({
      active_revision_id: revisionId,
      active_revision_moderation_status: "hidden",
      active_revision_author_user_id: null,
      payload_media_asset_id: null,
      payload_storage_path: null,
      bounds: null,
    });
  });

  test("get_widget_drawing_revisions pages the history newest first and syncs by update time", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const ids: string[] = [];
    let parent: string | null = null;
    for (let i = 0; i < 3; i += 1) {
      tick();
      const drawing: { row: Submitted; revisionId: string } = await submitDrawing(t, i % 2 ? couple.second : couple.first, couple, canvas.canvas_id, parent);
      parent = drawing.revisionId;
      ids.push(drawing.revisionId);
    }
    const read = (args: Record<string, unknown>) =>
      couple.first.as.query(api.widget.get_widget_drawing_revisions, { p_canvas_id: canvas.canvas_id, ...args });

    const history = await read({});
    expect(history.map((row: { revision_id: string }) => row.revision_id)).toEqual([...ids].reverse());
    expect(history[0]).toMatchObject({
      canvas_id: canvas.canvas_id,
      author_user_id: couple.first.userId,
      parent_revision_id: ids[1],
      moderation_status: "visible",
      deleted_at: null,
      payload_bucket: "widget-drawings",
      compression: "none",
    });
    expect(history[2].parent_revision_id).toBeNull();

    const page = await read({ p_limit: 1 });
    const older = await read({ p_limit: 5, p_created_before: page[0].created_at, p_created_before_revision_id: page[0].revision_id });
    expect(older.map((row: { revision_id: string }) => row.revision_id)).toEqual([ids[1], ids[0]]);

    const sync = await read({ p_updated_after: history[2].sync_updated_at, p_updated_after_revision_id: history[2].revision_id });
    expect(sync.map((row: { revision_id: string }) => row.revision_id)).toEqual([ids[1], ids[2]]);
    const none = await read({ p_updated_after: history[0].sync_updated_at, p_updated_after_revision_id: history[0].revision_id });
    expect(none).toEqual([]);
  });

  test("validates the read arguments", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const read = (args: Record<string, unknown>) =>
      failure(couple.first.as.query(api.widget.get_widget_drawing_revisions, { p_canvas_id: canvas.canvas_id, ...args }));
    const now = new Date().toISOString();
    const id = newUuid();
    expect(await read({ p_limit: 0 })).toEqual({ code: "23514", message: "widget drawing revision read limit is out of range" });
    expect(await read({ p_limit: 201 })).toEqual({ code: "23514", message: "widget drawing revision read limit is out of range" });
    expect(await read({ p_limit: null })).toEqual({ code: "23514", message: "widget drawing revision read limit is out of range" });
    expect(await read({ p_updated_after: now, p_updated_after_revision_id: id, p_created_before: now, p_created_before_revision_id: id })).toEqual({
      code: "23514",
      message: "widget drawing sync and history cursors cannot be combined",
    });
    expect(await read({ p_updated_after: now })).toEqual({ code: "23514", message: "widget drawing sync cursor requires timestamp and revision id" });
    expect(await read({ p_created_before_revision_id: id })).toEqual({
      code: "23514",
      message: "widget drawing history cursor requires timestamp and revision id",
    });
  });

  test("refuses strangers, former partners, and unentitled couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const canvas = await canvasOf(couple.first);
    const stranger = await createSignedInUser(t);
    const denied = { code: "42501", message: "active entitled widget canvas access is required" };
    const read = (user: TestUser) => user.as.query(api.widget.get_widget_drawing_revisions, { p_canvas_id: canvas.canvas_id });
    expect(await failure(read(stranger))).toEqual(denied);
    expect(await read(couple.second)).toEqual([]);
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(read(couple.first))).toEqual(denied);
    expect(await failure(read(couple.second))).toEqual(denied);
    expect(await failure(stranger.as.query(api.widget.get_widget_canvas, { p_couple_id: couple.coupleId }))).toEqual({
      code: "42501",
      message: "active entitled couple access is required",
    });
  });
});

describe("register_widget_push_device", () => {
  const register = (user: TestUser, overrides: Record<string, unknown> = {}) =>
    user.as.mutation(api.widget.register_widget_push_device, {
      p_widget_kind: "PaeoniaWidget",
      p_widget_push_token: "t".repeat(64),
      p_apns_environment: "sandbox",
      ...overrides,
    });
  const devices = (t: TestConvex) => t.run((ctx) => ctx.db.query("widget_push_devices").collect());

  test("registers a device and returns its id", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const id = await register(user, { p_locale: " nb-NO ", p_time_zone_id: "Europe/Oslo", p_app_version: "1.2", p_widget_kind: " PaeoniaWidget " });
    const [device] = await devices(t);
    expect(device).toMatchObject({
      id,
      user_id: user.userId,
      widget_kind: "PaeoniaWidget",
      apns_environment: "sandbox",
      locale: "nb-NO",
      time_zone_id: "Europe/Oslo",
      app_version: "1.2",
      revision: 1,
    });
    expect(device.widget_push_token_hash).toMatch(/^[0-9a-f]{64}$/);
  });

  test("registering the same token again updates the device", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const id = await register(user, { p_locale: "en" });
    await t.run(async (ctx) => {
      const device = await ctx.db.query("widget_push_devices").first();
      await ctx.db.patch(device!._id, { disabled_at: new Date().toISOString() });
    });
    tick();
    expect(await register(user, { p_locale: "nb", p_app_version: "2.0" })).toBe(id);
    const all = await devices(t);
    expect(all).toHaveLength(1);
    expect(all[0]).toMatchObject({ locale: "nb", app_version: "2.0", revision: 2, last_seen_at: new Date().toISOString() });
    expect(all[0].disabled_at).toBeUndefined();
  });

  test("a token moves to the newest account and the old account's device is disabled", async () => {
    const t = newTest();
    const first = await createSignedInUser(t);
    const second = await createSignedInUser(t);
    const firstId = await register(first);
    tick();
    const secondId = await register(second);
    expect(secondId).not.toBe(firstId);
    const all = await devices(t);
    expect(all.find((device) => device.id === firstId)?.disabled_at).toBe(new Date().toISOString());
    expect(all.find((device) => device.id === secondId)?.disabled_at).toBeUndefined();
    tick();
    expect(await register(first)).toBe(firstId);
    expect((await devices(t)).find((device) => device.id === secondId)?.disabled_at).toBeDefined();
  });

  test.each([
    ["a blank kind", { p_widget_kind: "  " }, "invalid widget kind"],
    ["a long kind", { p_widget_kind: "k".repeat(129) }, "invalid widget kind"],
    ["a short token", { p_widget_push_token: "short" }, "invalid widget push token"],
    ["an unknown environment", { p_apns_environment: "staging" }, "unsupported APNs environment"],
  ])("rejects %s", async (_name, overrides, message) => {
    const t = newTest();
    const user = await createSignedInUser(t);
    expect(await failure(register(user, overrides))).toEqual({ code: "23514", message });
    expect(await devices(t)).toHaveLength(0);
  });

  test("refuses a user whose account is being deleted", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      await ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: user.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        auth_delete_attempts: 0,
        created_at: now,
        updated_at: now,
      });
    });
    expect(await failure(register(user))).toEqual({ code: "42501", message: "account deletion is in progress" });
    expect(await devices(t)).toHaveLength(0);
  });
});
