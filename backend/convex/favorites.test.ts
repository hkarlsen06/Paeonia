import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { seedCatalog, textQuestions } from "./daily.setup";
import { answeredRound, answerIdOf, seedQuestion } from "./dailyChat.setup";
import { newUuid } from "./lib/ids";
import { failure, op, setMediaEnv, uploadAsset } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds = 60) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

type Kind = "daily_question" | "daily_answer" | "widget_drawing" | "game_round" | "corpse_figure" | "story_chain_story";

const favorite = (user: TestUser, kind: Kind, targetId: string, favorited = true) =>
  user.as.mutation(api.favorites.set_favorite, { p_kind: kind, p_target_id: targetId, p_favorited: favorited });
const list = (user: TestUser) => user.as.query(api.favorites.list_favorites, {});
const summaries = (user: TestUser, items: { kind: Kind; target_id: string }[]) =>
  user.as.query(api.favorites.get_favorite_summaries, { p_items: items });
const rows = (t: TestConvex) => t.run((ctx) => ctx.db.query("favorites").collect());
const denied = { code: "23514", message: "this item cannot be saved" };

/** A widget drawing by `user`, through the same upload and submit calls the app makes. */
async function drawing(t: TestConvex, user: TestUser, couple: TestCouple): Promise<string> {
  const [canvas] = await user.as.mutation(api.widget.get_or_create_widget_canvas, {});
  const revisionId = newUuid();
  const up = await uploadAsset(t, user, {
    kind: "widget_drawing_revision",
    purpose: "widget_drawing_payload",
    mediaType: "drawing_payload",
    extension: "pkdrawing",
    mime: "application/octet-stream",
    parentId: revisionId,
    coupleId: couple.coupleId,
    canvasId: canvas.canvas_id,
  });
  const [row] = await user.as.mutation(api.widget.submit_widget_drawing_revision, {
    ...op(),
    p_canvas_id: canvas.canvas_id,
    p_payload_media_asset_id: up.assetId,
    p_parent_revision_id: null,
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
  });
  return row.revision_id;
}

describe("set_favorite", () => {
  test("saves a question, repeating a call changes nothing, and taking it back removes it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    await answeredRound(t, couple, question);

    expect(await favorite(couple.first, "daily_question", question.id)).toEqual({
      kind: "daily_question",
      target_id: question.id,
      favorited: true,
    });
    await favorite(couple.first, "daily_question", question.id);
    expect(await rows(t)).toMatchObject([{ couple_id: couple.coupleId, user_id: couple.first.userId, kind: "daily_question", target_id: question.id, ordinal: 0 }]);

    await favorite(couple.first, "daily_question", question.id, false);
    await favorite(couple.first, "daily_question", question.id, false);
    expect(await rows(t)).toEqual([]);
  });

  test("a favorite is private: the partner has their own list", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    await answeredRound(t, couple, question);

    await favorite(couple.first, "daily_question", question.id);
    expect(await list(couple.second)).toEqual([]);
    expect(await summaries(couple.second, [{ kind: "daily_question", target_id: question.id }])).toEqual([]);

    await favorite(couple.second, "daily_question", question.id);
    await favorite(couple.second, "daily_question", question.id, false);
    expect((await list(couple.first)).map((item) => item.target_id)).toEqual([question.id]);
  });

  test("saves an answer the caller can read, and refuses a partner's answer before the caller answered", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const waiting = await answeredRound(t, couple, question, { answeredBy: [couple.first] });
    const firstAnswer = await answerIdOf(t, waiting, couple.first);

    await favorite(couple.first, "daily_answer", firstAnswer);
    expect(await failure(favorite(couple.second, "daily_answer", firstAnswer))).toEqual(denied);

    const both = await answeredRound(t, couple, question);
    const partnerAnswer = await answerIdOf(t, both, couple.second);
    await favorite(couple.first, "daily_answer", partnerAnswer);
    expect((await rows(t)).map((row) => row.kind).sort()).toEqual(["daily_answer", "daily_answer"]);
  });

  test("refuses outsiders, other couples and unknown items", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const question = await seedQuestion(t);
    const round = await answeredRound(t, couple, question);
    const answerId = await answerIdOf(t, round, couple.first);
    const revisionId = await drawing(t, couple.first, couple);
    const stranger = await createSignedInUser(t);
    const items: [Kind, string][] = [
      ["daily_question", question.id],
      ["daily_answer", answerId],
      ["widget_drawing", revisionId],
      ["game_round", newUuid()],
      ["corpse_figure", newUuid()],
      ["story_chain_story", newUuid()],
    ];

    for (const [kind, id] of items) {
      expect((await failure(favorite(stranger, kind, id))).code).toBe("42501");
      expect(await failure(favorite(other.first, kind, id))).toEqual(denied);
      expect(await failure(favorite(other.second, kind, id))).toEqual(denied);
    }
    expect(await rows(t)).toEqual([]);
  });

  test("refuses a couple without a subscription", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(favorite(couple.first, "daily_question", newUuid()))).code).toBe("42501");
  });

  test("saves a widget drawing, and a drawing that was removed cannot be saved or shown", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const revisionId = await drawing(t, couple.first, couple);
    await favorite(couple.second, "widget_drawing", revisionId);
    expect(await summaries(couple.second, [{ kind: "widget_drawing", target_id: revisionId }])).toMatchObject([
      { kind: "widget_drawing", target_id: revisionId, summary: { author_user_id: couple.first.userId, media_asset_id: expect.any(String) } },
    ]);

    await t.run(async (ctx) => {
      const revision = await ctx.db
        .query("widget_drawing_revisions")
        .withIndex("by_uuid", (q) => q.eq("id", revisionId))
        .unique();
      await ctx.db.patch(revision!._id, { moderation_status: "removed" });
    });
    expect(await summaries(couple.second, [{ kind: "widget_drawing", target_id: revisionId }])).toEqual([]);
    await favorite(couple.second, "widget_drawing", revisionId, false);
    expect(await failure(favorite(couple.second, "widget_drawing", revisionId))).toEqual(denied);
  });

  test("a pending account deletion blocks saving", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run(async (ctx) => {
      await ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: couple.first.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
    });
    expect((await failure(favorite(couple.first, "daily_question", newUuid()))).message).toMatch(/account deletion/);
  });
});

describe("list_favorites", () => {
  test("lists the caller's favorites newest first and nothing for a user without a couple", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const one = await seedQuestion(t);
    const two = await seedQuestion(t);
    await answeredRound(t, couple, one);
    await answeredRound(t, couple, two);

    await favorite(couple.first, "daily_question", one.id);
    tick();
    await favorite(couple.first, "daily_question", two.id);
    expect(await list(couple.first)).toEqual([
      { kind: "daily_question", target_id: two.id, created_at: "2026-10-10T12:01:00.000Z" },
      { kind: "daily_question", target_id: one.id, created_at: "2026-10-10T12:00:00.000Z" },
    ]);
    expect(await list(await createSignedInUser(t))).toEqual([]);
  });
});

describe("get_favorite_summaries", () => {
  test("describes a question and an answer, and skips items that are not saved", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const round = await answeredRound(t, couple, question, {
      texts: { [couple.first.userId]: "Sunday pancakes", [couple.second.userId]: "Beach walks" },
    });
    const partnerAnswer = await answerIdOf(t, round, couple.second);
    const notSaved = await seedQuestion(t);
    await answeredRound(t, couple, notSaved);

    await favorite(couple.first, "daily_question", question.id);
    await favorite(couple.first, "daily_answer", partnerAnswer);
    const result = await summaries(couple.first, [
      { kind: "daily_answer", target_id: partnerAnswer },
      { kind: "daily_question", target_id: question.id },
      { kind: "daily_question", target_id: notSaved.id },
    ]);
    expect(result.map((item) => item.kind)).toEqual(["daily_answer", "daily_question"]);
    expect(result[0].summary).toMatchObject({
      question_id: question.id,
      author_user_id: couple.second.userId,
      answer_text: "Beach walks",
      prompt_en: expect.any(String),
      prompt_nb: expect.any(String),
    });
    expect(result[1].summary).toMatchObject({ question_id: question.id, answer_text: null });
  });

  test("drops an answer that was deleted and refuses a read that is too large", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const round = await answeredRound(t, couple, question);
    const answerId = await answerIdOf(t, round, couple.first);
    await favorite(couple.first, "daily_answer", answerId);

    await t.run(async (ctx) => {
      const answer = await ctx.db
        .query("daily_question_answers")
        .withIndex("by_uuid", (q) => q.eq("id", answerId))
        .unique();
      await ctx.db.patch(answer!._id, { deleted_at: new Date().toISOString() });
    });
    expect(await summaries(couple.first, [{ kind: "daily_answer", target_id: answerId }])).toEqual([]);

    const tooMany = Array.from({ length: 41 }, () => ({ kind: "daily_question" as const, target_id: newUuid() }));
    expect((await failure(summaries(couple.first, tooMany))).code).toBe("23514");
  });
});

describe("cleanup", () => {
  test("the day reset deletes the favorites of the answers and the question it removes", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    // The reset seeds new questions, so the catalog needs spare ones in the same collection.
    const [question] = await seedCatalog(t, textQuestions(12));
    const round = await answeredRound(t, couple, question);
    const answerId = await answerIdOf(t, round, couple.first);
    await favorite(couple.first, "daily_question", question.id);
    await favorite(couple.second, "daily_answer", answerId);
    expect(await rows(t)).toHaveLength(2);

    await t.mutation(internal.daily.reset_daily_challenge_for_testing, { p_couple_id: couple.coupleId });
    expect(await rows(t)).toEqual([]);
  });

  test("ending the relationship deletes the couple's favorites and keeps another couple's", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const keep = await createCouple(t);
    const question = await seedQuestion(t);
    await answeredRound(t, couple, question);
    await answeredRound(t, keep, question);
    await favorite(couple.first, "daily_question", question.id);
    await favorite(couple.second, "daily_question", question.id);
    await favorite(keep.first, "daily_question", question.id);

    await couple.first.as.mutation(api.relationship.leave_relationship, op());
    expect(await rows(t)).toHaveLength(3);
    await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" });
    expect(await rows(t)).toMatchObject([{ couple_id: keep.coupleId, user_id: keep.first.userId }]);
  });
});
