import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { endCouple, op, setMediaEnv, uploadAsset } from "./media.testing";
import { createCouple, createSignedInUser, newTest } from "./test.setup";

beforeEach(() => { setMediaEnv(); vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z")); });
afterEach(() => vi.useRealTimers());

async function fixture() {
  const t = newTest();
  const couple = await createCouple(t);
  const [canvas] = await couple.first.as.mutation(api.widget.get_or_create_widget_canvas, {});
  const revisionId = newUuid();
  const upload = await uploadAsset(t, couple.first, {
    kind: "widget_drawing_revision", purpose: "widget_drawing_payload", mediaType: "drawing_payload",
    extension: "pkdrawing", mime: "application/octet-stream", parentId: revisionId,
    coupleId: couple.coupleId, canvasId: canvas.canvas_id,
  });
  await couple.first.as.mutation(api.widget.submit_widget_drawing_revision, {
    ...op(), p_canvas_id: canvas.canvas_id, p_payload_media_asset_id: upload.assetId, p_parent_revision_id: null,
    p_payload_bytes: upload.bytes.length, p_uncompressed_bytes: upload.bytes.length, p_compression: "none",
    p_stroke_count: 2, p_point_count: 20,
    p_bounds: { x: 2, y: 3, width: 40, height: 50, canvasSide: 320, accessibilityText: "The original sun" },
    p_sha256_hex: upload.sha256, p_client_decode_validated_at: new Date().toISOString(),
    p_client_renderer_version: "r1", p_client_validation_version: "v1",
  });
  const target = { kind: "widget_drawing", revision_id: revisionId } as const;
  const read = () => couple.second.as.query(api.widget.get_widget_canvas, {});
  return { t, couple, target, read, revisionId };
}

describe("widget drawing description corrections", () => {
  test("only the entitled author can correct a live drawing, including replay", async () => {
    const { t, couple, target, revisionId } = await fixture();
    const outsider = await createSignedInUser(t);
    const args = { ...op(), p_target: target, p_text: "Corrected sun" };
    for (const user of [couple.second, outsider]) {
      await expect(user.as.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
    }
    await expect(t.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
    await couple.first.as.mutation(api.media.update_accessibility_text, args);
    await t.run(async ctx => {
      const row = await ctx.db.query("widget_drawing_revisions").withIndex("by_uuid", q => q.eq("id", revisionId)).unique();
      if (!row) throw new Error("Missing test revision");
      await ctx.db.patch(row._id, { moderation_status: "hidden" });
    });
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
  });

  test("corrections and clear preserve strokes, attribution and time with a monotonic version", async () => {
    const { couple, target, read } = await fixture();
    const [before] = await read();
    const earlier = { ...op(), p_target: target, p_text: "Earlier" };
    const newer = { ...op(), p_target: target, p_text: "  A circle above a line  " };
    const accepted = await couple.first.as.mutation(api.media.update_accessibility_text, newer);
    const replay = await couple.first.as.mutation(api.media.update_accessibility_text, earlier);
    expect(replay).toEqual(accepted);
    const [after] = await read();
    expect(after.bounds).toEqual({ ...before.bounds, accessibilityText: "A circle above a line" });
    for (const key of ["active_revision_id", "active_revision_author_user_id", "payload_media_asset_id", "revision_created_at"] as const) {
      expect(after[key]).toEqual(before[key]);
    }
    expect(after.revision_description_version).toBeGreaterThan(before.revision_description_version!);
    const cleared = await couple.first.as.mutation(api.media.update_accessibility_text, { ...op(), p_target: target, p_text: " " });
    expect(cleared.accessibility_text).toBeNull();
    expect(cleared.revision_description_version).toBeGreaterThan(accepted.revision_description_version!);
    const [withoutDescription] = await read();
    expect(withoutDescription.bounds).toEqual({ x: 2, y: 3, width: 40, height: 50, canvasSide: 320 });
  });

  test("refuses overlong text and access after leaving", async () => {
    const { t, couple, target } = await fixture();
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, {
      ...op(), p_target: target, p_text: "a".repeat(501),
    })).rejects.toThrow(/23514/);
    const args = { ...op(), p_target: target, p_text: "An authored correction" };
    await couple.first.as.mutation(api.media.update_accessibility_text, args);
    await endCouple(t, couple.coupleId, couple.first.userId);
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
  });
});
