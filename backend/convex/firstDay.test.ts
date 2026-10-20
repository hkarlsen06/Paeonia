import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { seedCatalog, textQuestions } from "./daily.setup";
import { newUuid } from "./lib/ids";
import { mediaAssetHasLiveReference } from "./lib/mediaOrphans";
import { failure, op, setMediaEnv, uploadAsset, type Uploaded } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, grantLifetime, newTest, type TestConvex, type TestUser } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  setMediaEnv();
  process.env.INVITE_CODE_PEPPER = "test-pepper-value-for-pairing-invite-hashes";
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
  delete process.env.INVITE_CODE_PEPPER;
});

async function inviter(t: TestConvex, options: { entitled?: boolean } = {}): Promise<TestUser> {
  const user = await createSignedInUser(t, { name: "Inviter", timeZone: "Europe/Oslo" });
  if (options.entitled !== false) await grantLifetime(t, user.userId);
  return user;
}

async function uploadDraftDrawing(t: TestConvex, user: TestUser): Promise<Uploaded> {
  return await uploadAsset(t, user, {
    kind: "widget_drawing_revision",
    purpose: "widget_drawing_payload",
    mediaType: "drawing_payload",
    extension: "pkdrawing",
    mime: "application/octet-stream",
    pathContext: { first_day_draft: true },
  });
}

function drawingArgs(up: Uploaded) {
  return {
    ...op(),
    p_payload_media_asset_id: up.assetId,
    p_payload_bytes: up.bytes.length,
    p_uncompressed_bytes: up.bytes.length,
    p_compression: "none",
    p_stroke_count: 3,
    p_point_count: 40,
    p_bounds: { x: 0, y: 0, width: 10, height: 10 },
    p_sha256_hex: up.sha256,
    p_client_decode_validated_at: NOW,
    p_client_renderer_version: "r1",
    p_client_validation_version: "v1",
  };
}

const draftOf = (user: TestUser) => user.as.query(api.firstDay.get_first_day_draft, {});
const assetOf = (t: TestConvex, assetId: string) =>
  t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", assetId)).unique());

describe("start_first_day_draft", () => {
  test("picks two different written questions without partner choice, once", async () => {
    const t = newTest();
    await seedCatalog(t, [
      { key: "choice", kinds: ["text", "partner_choice"] },
      { key: "photo_only", kinds: ["photo"] },
      { key: "written" },
      { key: "written_or_photo", kinds: ["text", "photo"] },
    ]);
    const user = await inviter(t, { entitled: false });
    expect(await draftOf(user)).toBeNull();

    const draft = await user.as.mutation(api.firstDay.start_first_day_draft, {});
    expect(draft.questions.map((row) => row.slot_number)).toEqual([1, 2]);
    expect(draft.questions.map((row) => row.question_key).sort()).toEqual(["written", "written_or_photo"]);
    expect(draft.questions[0]).toMatchObject({ answer_text: null, answered_at: null, prompt_nb: expect.stringContaining("prompt nb") });
    expect(draft).toMatchObject({ started_on: null, drawing: null, updated_at: NOW });

    expect(await user.as.mutation(api.firstDay.start_first_day_draft, {})).toEqual(draft);
    expect(await draftOf(user)).toEqual(draft);
    expect(await t.run((ctx) => ctx.db.query("first_day_drafts").collect())).toHaveLength(1);
  });

  test("refuses a user who already has a couple", async () => {
    const t = newTest();
    await seedCatalog(t, textQuestions(4));
    const couple = await createCouple(t);
    expect(await failure(couple.first.as.mutation(api.firstDay.start_first_day_draft, {}))).toEqual({
      code: "23505",
      message: "user already has an active couple",
    });
  });
});

describe("set_first_day_started_on", () => {
  test("saves and clears the date without a subscription and refuses a future date", async () => {
    const t = newTest();
    const user = await inviter(t, { entitled: false });
    await user.as.mutation(api.firstDay.set_first_day_started_on, { ...op(), p_started_on: "2026-10-10" });
    expect(await draftOf(user)).toMatchObject({ started_on: "2026-10-10", questions: [] });

    expect(await failure(user.as.mutation(api.firstDay.set_first_day_started_on, { ...op(), p_started_on: "2026-10-11" }))).toEqual({
      code: "23514",
      message: "relationship start date must be today or earlier",
    });

    await user.as.mutation(api.firstDay.set_first_day_started_on, { ...op(), p_started_on: null });
    expect(await draftOf(user)).toMatchObject({ started_on: null });
  });
});

describe("save_first_day_answer", () => {
  test("needs a subscription, a drafted question, and 1 to 2000 characters, and replaces an earlier answer", async () => {
    const t = newTest();
    await seedCatalog(t, textQuestions(4));
    const unpaid = await inviter(t, { entitled: false });
    const unpaidDraft = await unpaid.as.mutation(api.firstDay.start_first_day_draft, {});
    expect(
      await failure(
        unpaid.as.mutation(api.firstDay.save_first_day_answer, {
          ...op(),
          p_question_version_id: unpaidDraft.questions[0].question_version_id,
          p_text: "Hello",
        }),
      ),
    ).toEqual({ code: "42501", message: "direct entitlement is required for first day content" });

    const user = await inviter(t);
    const draft = await user.as.mutation(api.firstDay.start_first_day_draft, {});
    const versionId = draft.questions[0].question_version_id;
    const save = (text: string, id = versionId) =>
      user.as.mutation(api.firstDay.save_first_day_answer, { ...op(), p_question_version_id: id.toUpperCase(), p_text: text });

    expect(await failure(save("Hello", newUuid()))).toEqual({ code: "22023", message: "first day question was not found" });
    expect(await failure(save("   "))).toEqual({ code: "23514", message: "answer text is required" });
    expect(await failure(save("x".repeat(2001)))).toEqual({ code: "23514", message: "answer text is too long" });

    await save("  Hello  ");
    expect((await draftOf(user))!.questions[0]).toMatchObject({ answer_text: "Hello", answered_at: NOW });
    await save("Edited");
    const saved = await draftOf(user);
    expect(saved!.questions.map((row) => row.answer_text)).toEqual(["Edited", null]);
    const [row] = await t.run((ctx) => ctx.db.query("first_day_drafts").withIndex("by_user_id", (q) => q.eq("user_id", user.userId)).collect());
    expect(row.answers).toHaveLength(1);
  });
});

describe("first day drawing", () => {
  test("reserves the upload under the user's drafts path without a couple, and needs a subscription", async () => {
    const t = newTest();
    const unpaid = await inviter(t, { entitled: false });
    expect(await failure(uploadDraftDrawing(t, unpaid))).toEqual({
      code: "42501",
      message: "direct entitlement is required for first day content",
    });
    const couple = await createCouple(t);
    expect(await failure(uploadDraftDrawing(t, couple.first))).toEqual({ code: "23505", message: "user already has an active couple" });

    const user = await inviter(t);
    const up = await uploadDraftDrawing(t, user);
    expect(up.storagePath).toBe(`drafts/${user.userId}/revisions/${up.parentId}/drawing.pkdrawing`);
    expect(up.bucket).toBe("widget-drawings");
    const asset = await assetOf(t, up.assetId);
    expect(asset?.couple_id).toBeUndefined();
    expect(asset?.upload_status).toBe("finalized");
  });

  test("saves the drawing on the draft and queues a replaced one for deletion", async () => {
    const t = newTest();
    const user = await inviter(t);
    const first = await uploadDraftDrawing(t, user);
    expect(await user.as.mutation(api.firstDay.save_first_day_drawing, drawingArgs(first))).toEqual({
      revision_id: first.parentId,
      media_asset_id: first.assetId,
      saved_at: NOW,
    });
    expect((await draftOf(user))!.drawing).toEqual({
      media_asset_id: first.assetId,
      revision_id: first.parentId,
      saved_at: NOW,
      bounds: { x: 0, y: 0, width: 10, height: 10 },
    });
    expect(await t.run((ctx) => mediaAssetHasLiveReference(ctx, first.assetId))).toBe(true);

    // Before pairing, only the inviter can read their saved drawing.
    const [signed] = await user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: first.assetId });
    expect(signed.media_asset_id).toBe(first.assetId);
    const stranger = await inviter(t);
    expect(await failure(stranger.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: first.assetId }))).toEqual({
      code: "42501",
      message: "media asset is not available",
    });

    expect(
      await failure(user.as.mutation(api.firstDay.save_first_day_drawing, { ...drawingArgs(first), p_payload_bytes: first.bytes.length + 1, p_uncompressed_bytes: first.bytes.length + 1 })),
    ).toEqual({ code: "23514", message: "widget drawing payload asset is not usable" });

    const second = await uploadDraftDrawing(t, user);
    await user.as.mutation(api.firstDay.save_first_day_drawing, drawingArgs(second));
    expect((await draftOf(user))!.drawing?.media_asset_id).toBe(second.assetId);
    expect(await assetOf(t, first.assetId)).toMatchObject({ storage_delete_status: "pending" });
    expect(await assetOf(t, second.assetId)).toMatchObject({ storage_delete_status: "none" });
  });
});

describe("accept_pairing_invite with a first day draft", () => {
  async function inviterWithDraft(t: TestConvex, options: { answered?: number } = {}) {
    await seedCatalog(t, textQuestions(8));
    const creator = await inviter(t);
    await addDevice(t, creator.userId, { locale: "en" });
    const draft = await creator.as.mutation(api.firstDay.start_first_day_draft, {});
    await creator.as.mutation(api.firstDay.set_first_day_started_on, { ...op(), p_started_on: "2026-09-01" });
    for (const [index, question] of draft.questions.slice(0, options.answered ?? 2).entries()) {
      await creator.as.mutation(api.firstDay.save_first_day_answer, {
        ...op(),
        p_question_version_id: question.question_version_id,
        p_text: `Answer ${index + 1}`,
      });
    }
    const drawing = await uploadDraftDrawing(t, creator);
    await creator.as.mutation(api.firstDay.save_first_day_drawing, drawingArgs(drawing));
    await creator.as.mutation(api.pairing.create_pairing_invite, { ...op(), p_invite_code: "ABC123" });
    const partner = await createSignedInUser(t, { name: "Partner", timeZone: "Europe/Oslo" });
    await addDevice(t, partner.userId, { locale: "en" });
    return { creator, partner, draft, drawing };
  }

  test("turns the draft into the couple's first day", async () => {
    const t = newTest();
    const { creator, partner, draft, drawing } = await inviterWithDraft(t);

    const coupleId = await partner.as.mutation(api.pairing.accept_pairing_invite, { ...op(), p_invite_code: "ABC123" });

    const state = await t.run(async (ctx) => ({
      couple: await ctx.db.query("couples").withIndex("by_uuid", (q) => q.eq("id", coupleId)).unique(),
      drafts: await ctx.db.query("first_day_drafts").collect(),
      challenges: await ctx.db.query("daily_challenges").collect(),
      outbox: await ctx.db.query("notification_outbox").collect(),
    }));
    expect(state.couple?.started_on).toBe("2026-09-01");
    expect(state.drafts).toEqual([]);
    const creatorChallenge = state.challenges.find((row) => row.user_id === creator.userId);
    expect(creatorChallenge?.completed_at).toBe(NOW);
    expect(creatorChallenge?.partner_notified_at).toBeUndefined();

    // The partner sees the inviter's answered questions, in their slots, and has their own two.
    const [snapshot] = await partner.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    const creatorRows = snapshot.questions.filter((row) => row.seeded_for_user_id === creator.userId);
    expect(creatorRows.map((row) => [row.slot_number, row.question_version_id])).toEqual(
      draft.questions.map((row) => [row.slot_number, row.question_version_id]),
    );
    expect(creatorRows.every((row) => row.partner_answer_id !== null && row.own_answer_id === null)).toBe(true);
    expect(snapshot.questions.filter((row) => row.seeded_for_user_id === partner.userId)).toHaveLength(2);
    const [own] = await creator.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    expect(own.answer_details.filter((row) => row.is_own_answer).map((row) => row.text_body).sort()).toEqual(["Answer 1", "Answer 2"]);

    // The drawing is the active widget revision, by the inviter, and the partner can open it.
    const [canvas] = await partner.as.query(api.widget.get_widget_canvas, {});
    expect(canvas).toMatchObject({
      active_revision_id: drawing.parentId,
      active_revision_author_user_id: creator.userId,
      payload_media_asset_id: drawing.assetId,
    });
    const [signed] = await partner.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: drawing.assetId });
    expect(signed.media_asset_id).toBe(drawing.assetId);

    // No visible pushes for the partner. The inviter hears that their partner joined.
    expect(state.outbox.filter((row) => row.recipient_user_id === partner.userId && row.apns_push_type === "alert")).toEqual([]);
    const joined = state.outbox.filter((row) => row.kind === "partner_joined");
    expect(joined).toEqual([
      expect.objectContaining({
        recipient_user_id: creator.userId,
        title: "Partner joined you",
        body: "See your first day together.",
        payload: expect.objectContaining({ couple_id: coupleId, deeplink: "paeonia://home" }),
      }),
    ]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an answer saved after the partner joined goes to the couple's first day question", async () => {
    const t = newTest();
    const { creator, partner, draft } = await inviterWithDraft(t, { answered: 1 });
    await partner.as.mutation(api.pairing.accept_pairing_invite, { ...op(), p_invite_code: "ABC123" });
    const save = (index: number, text: string) =>
      creator.as.mutation(api.firstDay.save_first_day_answer, {
        ...op(),
        p_question_version_id: draft.questions[index].question_version_id,
        p_text: text,
      });

    // The unanswered question gets its answer, which completes the inviter's day, and the
    // partner hears about it like any finished day.
    await save(1, "Late answer");
    // The one answered before pairing is edited in place.
    await save(0, "Edited after pairing");

    const [own] = await creator.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    const texts = own.answer_details.filter((row) => row.is_own_answer).map((row) => row.text_body);
    expect(texts.sort()).toEqual(["Edited after pairing", "Late answer"]);
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.filter((row) => row.recipient_user_id === partner.userId && row.kind === "daily_challenge_completed")).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the start date passed to accept wins over the draft's", async () => {
    const t = newTest();
    const { partner } = await inviterWithDraft(t);
    const coupleId = await partner.as.mutation(api.pairing.accept_pairing_invite, {
      ...op(),
      p_invite_code: "ABC123",
      p_started_on: "2025-01-01",
    });
    const couple = await t.run((ctx) => ctx.db.query("couples").withIndex("by_uuid", (q) => q.eq("id", coupleId)).unique());
    expect(couple?.started_on).toBe("2025-01-01");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("account deletion", () => {
  test("deletes the draft and queues its drawing for deletion", async () => {
    const t = newTest();
    const user = await inviter(t);
    const drawing = await uploadDraftDrawing(t, user);
    await user.as.mutation(api.firstDay.save_first_day_drawing, drawingArgs(drawing));

    await user.as.mutation(api.identity.request_account_deletion, {});

    expect(await t.run((ctx) => ctx.db.query("first_day_drafts").collect())).toEqual([]);
    expect(await assetOf(t, drawing.assetId)).toMatchObject({ storage_delete_status: "pending" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
