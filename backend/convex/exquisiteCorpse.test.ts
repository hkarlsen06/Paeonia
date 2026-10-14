import type { FunctionArgs } from "convex/server";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { dealIdeas } from "./lib/exquisiteCorpse";
import { EXQUISITE_CORPSE_IDEAS } from "./lib/exquisiteCorpseIdeas";
import { endCouple, failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import {
  addDevice,
  createCouple,
  createSignedInUser,
  newTest,
  type TestConvex,
  type TestCouple,
  type TestUser,
} from "./test.setup";

// These tests need the registry line `exquisite_corpse: exquisiteCorpseBackend` in lib/gameRegistry.ts,
// because the push drain, the reminder cron, and the relationship cleanup reach the game through it.

const START = Date.parse("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));
const HOUR = 3600;

type Setup = { t: TestConvex; couple: TestCouple; a: TestUser; b: TestUser; gameId: string };
type Purpose = "exquisite_corpse_drawing" | "exquisite_corpse_strip";

/** A couple with devices, settings, and a game. `a` starts. */
async function startGame(options: { language?: "en" | "nb"; t?: TestConvex } = {}): Promise<Setup> {
  const t = options.t ?? newTest();
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await addDevice(t, a.userId);
  await addDevice(t, b.userId);
  await a.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: options.language ?? "en" });
  const { game_id } = await a.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {});
  return { t, couple, a, b, gameId: game_id };
}

const view = (user: TestUser) => user.as.query(api.exquisiteCorpse.get_exquisite_corpse, {});
/** The game and the figure in progress, for tests that know both exist. */
const gameOf = async (user: TestUser) => (await view(user)).game!;
const currentOf = async (user: TestUser) => (await view(user)).current_figure!;
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
const settle = (s: Setup) => s.t.finishAllScheduledFunctions(vi.runAllTimers);

function upload(s: Setup, user: TestUser, partId: string, purpose: Purpose) {
  return uploadAsset(s.t, user, {
    kind: "exquisite_corpse_part",
    purpose,
    mediaType: "drawing_payload",
    extension: "pkdrawing",
    mime: "application/octet-stream",
    parentId: partId,
    coupleId: s.couple.coupleId,
    gameId: s.gameId,
  });
}

type PartSpec = { figureId: string; index: 0 | 1 | 2; partId?: string; ideaId?: string };

/** Uploads the drawing (and the strip for the head and body) and builds the submit arguments. */
async function prepare(s: Setup, user: TestUser, spec: PartSpec) {
  const partId = spec.partId ?? newUuid();
  const drawing = await upload(s, user, partId, "exquisite_corpse_drawing");
  const strip = spec.index < 2 ? await upload(s, user, partId, "exquisite_corpse_strip") : undefined;
  const args = {
    ...op(),
    p_game_id: s.gameId,
    p_figure_id: spec.figureId,
    p_part_id: partId,
    p_part_index: spec.index,
    p_drawing_media_asset_id: drawing.assetId,
    ...(strip ? { p_strip_media_asset_id: strip.assetId } : {}),
    ...(spec.ideaId ? { p_idea_id: spec.ideaId } : {}),
  };
  return { partId, drawing, strip, args };
}

type SubmitArgs = FunctionArgs<typeof api.exquisiteCorpse.submit_exquisite_corpse_part>;
const submit = (user: TestUser, args: SubmitArgs) => user.as.mutation(api.exquisiteCorpse.submit_exquisite_corpse_part, args);

async function send(s: Setup, user: TestUser, spec: PartSpec) {
  const prepared = await prepare(s, user, spec);
  return { ...prepared, result: await submit(user, prepared.args) };
}

/** A whole figure: `starter` draws the head and the legs, `other` the body. */
async function playFigure(s: Setup, starter: TestUser, other: TestUser, ideas: { head?: string; body?: string; legs?: string } = {}) {
  const figureId = newUuid();
  const head = await send(s, starter, { figureId, index: 0, ideaId: ideas.head });
  const body = await send(s, other, { figureId, index: 1, ideaId: ideas.body });
  const legs = await send(s, starter, { figureId, index: 2, ideaId: ideas.legs });
  return { figureId, head, body, legs };
}

const signed = (user: TestUser, assetId: string) =>
  user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: assetId, p_expires_in_seconds: 300 });

describe("access", () => {
  test("a user without a couple cannot use the game", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(loner.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {}))).code).toBe("42501");
    expect((await failure(loner.as.query(api.exquisiteCorpse.get_exquisite_corpse, {}))).code).toBe("42501");
    expect((await failure(loner.as.query(api.exquisiteCorpse.get_exquisite_corpse_history, { p_starred_only: false, p_limit: 10 }))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.exquisiteCorpse.mark_exquisite_corpse_reveal_seen, { p_figure_id: newUuid() }))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.exquisiteCorpse.set_exquisite_corpse_star, { p_figure_id: newUuid(), p_starred: true }))).code).toBe("42501");
  });

  test("a couple without a subscription cannot use the game", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {}))).code).toBe("42501");
  });

  test("another couple cannot send, mark, or star", async () => {
    const s = await startGame();
    const { figureId } = await playFigure(s, s.a, s.b);
    const other = await createCouple(s.t);
    const prepared = await prepare(s, s.b, { figureId: newUuid(), index: 0 });
    expect((await failure(submit(other.first, prepared.args))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.exquisiteCorpse.mark_exquisite_corpse_reveal_seen, { p_figure_id: figureId }))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.exquisiteCorpse.set_exquisite_corpse_star, { p_figure_id: figureId, p_starred: true }))).code).toBe("42501");
    expect(await other.first.as.query(api.exquisiteCorpse.get_exquisite_corpse, {})).toMatchObject({ game: null, current_figure: null, recent_figures: [] });
    await settle(s);
  });

  test("a partner whose relationship ended cannot send", async () => {
    const s = await startGame();
    const prepared = await prepare(s, s.a, { figureId: newUuid(), index: 0 });
    await endCouple(s.t, s.couple.coupleId, s.b.userId);
    expect((await failure(submit(s.a, prepared.args))).code).toBe("42501");
  });

  test("a pending account deletion blocks writes", async () => {
    const s = await startGame();
    await s.t.run(async (ctx) => {
      await ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: s.a.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
    });
    const args = {
      ...op(),
      p_game_id: s.gameId,
      p_figure_id: newUuid(),
      p_part_id: newUuid(),
      p_part_index: 0,
      p_drawing_media_asset_id: newUuid(),
      p_strip_media_asset_id: newUuid(),
    };
    expect((await failure(submit(s.a, args))).message).toMatch(/account deletion/);
    expect((await failure(s.a.as.mutation(api.exquisiteCorpse.mark_exquisite_corpse_reveal_seen, { p_figure_id: newUuid() }))).message).toMatch(/account deletion/);
    expect((await failure(s.a.as.mutation(api.exquisiteCorpse.set_exquisite_corpse_star, { p_figure_id: newUuid(), p_starred: true }))).message).toMatch(/account deletion/);
  });
});

describe("ensure_exquisite_corpse_game", () => {
  test("creates one game with the caller starting, and returns it again", async () => {
    const s = await startGame();
    expect(await s.a.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {})).toEqual({ game_id: s.gameId, created: false });
    expect(await s.b.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {})).toEqual({ game_id: s.gameId, created: false });

    const data = await view(s.b);
    expect(data).toMatchObject({
      user_id: s.b.userId,
      partner_user_id: s.a.userId,
      couple_id: s.couple.coupleId,
      current_figure: null,
      recent_figures: [],
      ideas: [],
    });
    expect(data.game).toEqual({
      id: s.gameId,
      turn_user_id: s.a.userId,
      turn_started_at: new Date(START).toISOString(),
      figure_id: null,
      figure_number: 1,
      part_index: 0,
      figures_finished: 0,
      version: 1,
      created_at: new Date(START).toISOString(),
      updated_at: new Date(START).toISOString(),
    });
    expect(await s.t.run((ctx) => ctx.db.query("exquisite_corpse_games").collect())).toHaveLength(1);
  });

  test("two partners opening at the same time still get one game", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    const [x, y] = await Promise.all([
      couple.first.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {}),
      couple.second.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {}),
    ]);
    expect(x.game_id).toBe(y.game_id);
    expect([x.created, y.created].sort()).toEqual([false, true]);
  });

  test("the game needs settings first", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await failure(couple.first.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {}))).code).toBe("23514");
  });
});

describe("ideas", () => {
  test("the person whose turn it is gets a deck of 12 for the next part, seeded by game, figure, and part", async () => {
    const s = await startGame();
    const { ideas } = await view(s.a);
    expect(ideas).toHaveLength(12);
    expect(new Set(ideas.map((idea: { id: string }) => idea.id)).size).toBe(12);
    expect(ideas).toEqual(dealIdeas("en", 0, `${s.gameId}:1:0`));
    expect((await view(s.a)).ideas).toEqual(ideas);
    expect((await view(s.b)).ideas).toEqual([]);
    const head = EXQUISITE_CORPSE_IDEAS.en.head.map((idea) => idea.id);
    expect(ideas.every((idea: { id: string }) => head.includes(idea.id))).toBe(true);
  });

  test("the deck follows the part and the turn", async () => {
    const s = await startGame();
    await send(s, s.a, { figureId: newUuid(), index: 0 });
    expect((await view(s.a)).ideas).toEqual([]);
    expect((await view(s.b)).ideas).toEqual(dealIdeas("en", 1, `${s.gameId}:1:1`));
    await settle(s);
  });

  test("the deck comes in the game language, and a new language changes the next deck", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    const { ideas } = await view(s.a);
    expect(ideas).toEqual(dealIdeas("nb", 0, `${s.gameId}:1:0`));
    const nbHead = EXQUISITE_CORPSE_IDEAS.nb.head.map((idea) => idea.id);
    expect(ideas.every((idea: { id: string }) => nbHead.includes(idea.id))).toBe(true);
  });

  test("an idea is stored with its text, hidden from the partner, and shown to both at the reveal", async () => {
    const s = await startGame();
    const idea = EXQUISITE_CORPSE_IDEAS.en.head[0];
    const figureId = newUuid();
    await send(s, s.a, { figureId, index: 0, ideaId: idea.id });
    await send(s, s.b, { figureId, index: 1 });

    expect((await currentOf(s.a)).parts[0].idea).toEqual({ id: idea.id, text: idea.text });
    expect((await currentOf(s.b)).parts[0].idea).toBeNull();
    const stored = await s.t.run((ctx) => ctx.db.query("exquisite_corpse_parts").collect());
    expect(stored.find((part) => part.part_index === 0)).toMatchObject({ idea_id: idea.id, idea_text: idea.text });
    const bodyPart = stored.find((part) => part.part_index === 1)!;
    expect([bodyPart.idea_id, bodyPart.idea_text]).toEqual([undefined, undefined]);

    await send(s, s.a, { figureId, index: 2 });
    const parts = (await view(s.b)).recent_figures[0].parts;
    expect(parts.map((part: { idea: unknown }) => part.idea)).toEqual([{ id: idea.id, text: idea.text }, null, null]);
    await settle(s);
  });

  test("an idea from the other language's list is accepted and keeps its own text", async () => {
    const s = await startGame({ language: "en" });
    const norwegian = EXQUISITE_CORPSE_IDEAS.nb.head[0];
    const english = EXQUISITE_CORPSE_IDEAS.en.head[0];
    expect(EXQUISITE_CORPSE_IDEAS.en.head.some((idea) => idea.id === norwegian.id)).toBe(false);
    const first = await send(s, s.a, { figureId: newUuid(), index: 0, ideaId: norwegian.id });
    expect((await currentOf(s.a)).parts[0].idea).toEqual({ id: norwegian.id, text: norwegian.text });

    // The same the other way round, once the language changed and the next figure starts with the partner.
    await send(s, s.b, { figureId: first.args.p_figure_id, index: 1 });
    await send(s, s.a, { figureId: first.args.p_figure_id, index: 2 });
    await s.a.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    await send(s, s.b, { figureId: newUuid(), index: 0, ideaId: english.id });
    expect((await currentOf(s.b)).parts[0].idea).toEqual({ id: english.id, text: english.text });
    await settle(s);
  });

  test("an unknown idea, or one that belongs to another part, is refused", async () => {
    const s = await startGame();
    const figureId = newUuid();
    const unknown = await prepare(s, s.a, { figureId, index: 0, ideaId: "head-not-on-any-list" });
    expect((await failure(submit(s.a, unknown.args))).code).toBe("22023");
    const wrongPart = await prepare(s, s.a, { figureId, index: 0, ideaId: EXQUISITE_CORPSE_IDEAS.en.body[0].id });
    expect((await failure(submit(s.a, wrongPart.args))).code).toBe("22023");
    expect((await gameOf(s.a)).version).toBe(1);
  });
});

describe("submit_exquisite_corpse_part", () => {
  test("three parts make a figure, the turn alternates, and the next figure starts with the body drawer", async () => {
    const s = await startGame();
    const turn = async () => (await gameOf(s.a)).turn_user_id;
    expect(await turn()).toBe(s.a.userId);

    const figureId = newUuid();
    const head = await send(s, s.a, { figureId, index: 0 });
    expect(head.result).toMatchObject({ figure_id: figureId, part_id: head.partId, part_index: 0, figure_finished: false });
    expect(await turn()).toBe(s.b.userId);
    expect(await gameOf(s.a)).toMatchObject({ figure_id: figureId, figure_number: 1, part_index: 1, figures_finished: 0, version: 2 });

    const body = await send(s, s.b, { figureId, index: 1 });
    expect(body.result.figure_finished).toBe(false);
    expect(await turn()).toBe(s.a.userId);
    expect(await gameOf(s.a)).toMatchObject({ part_index: 2, version: 3 });

    const legs = await send(s, s.a, { figureId, index: 2 });
    expect(legs.result).toMatchObject({ part_index: 2, figure_finished: true });
    expect(await turn()).toBe(s.b.userId);
    const finished = await view(s.a);
    expect(finished.game).toMatchObject({ figure_id: null, figure_number: 2, part_index: 0, figures_finished: 1, version: 4 });
    expect(finished.current_figure).toBeNull();
    expect(finished.recent_figures).toHaveLength(1);
    expect(finished.recent_figures[0]).toMatchObject({ id: figureId, number: 1, starter_user_id: s.a.userId });
    expect(finished.recent_figures[0].finished_at).not.toBeNull();
    expect(finished.recent_figures[0].parts.map((part: { id: string }) => part.id)).toEqual([head.partId, body.partId, legs.partId]);

    // b drew the body, so b starts the next figure and draws its head and legs.
    const next = newUuid();
    await send(s, s.b, { figureId: next, index: 0 });
    await send(s, s.a, { figureId: next, index: 1 });
    await send(s, s.b, { figureId: next, index: 2 });
    const after = await view(s.a);
    expect(after.game).toMatchObject({ turn_user_id: s.a.userId, figure_number: 3, figures_finished: 2 });
    expect(after.recent_figures.map((figure: { number: number }) => figure.number)).toEqual([2, 1]);
    expect(after.recent_figures[0].starter_user_id).toBe(s.b.userId);
    await settle(s);
  });

  test("a partner sees the strip at once but neither the drawing nor the idea before the figure is finished", async () => {
    const s = await startGame();
    const idea = EXQUISITE_CORPSE_IDEAS.en.head[1];
    const figureId = newUuid();
    const head = await send(s, s.a, { figureId, index: 0, ideaId: idea.id });

    const seenByB = await currentOf(s.b);
    expect(seenByB.parts).toEqual([
      {
        id: head.partId,
        part_index: 0,
        drawer_user_id: s.a.userId,
        created_at: head.result.created_at,
        strip_media_asset_id: head.strip!.assetId,
        drawing_media_asset_id: null,
        idea: null,
      },
    ]);
    expect((await currentOf(s.a)).parts[0]).toMatchObject({
      drawing_media_asset_id: head.drawing.assetId,
      strip_media_asset_id: head.strip!.assetId,
      idea: { id: idea.id, text: idea.text },
    });

    // The body drawer's own part is hidden from the head drawer in the same way.
    const body = await send(s, s.b, { figureId, index: 1 });
    expect((await currentOf(s.a)).parts[1]).toMatchObject({ drawing_media_asset_id: null, strip_media_asset_id: body.strip!.assetId });
    expect((await currentOf(s.b)).parts[1]).toMatchObject({ drawing_media_asset_id: body.drawing.assetId });

    const legs = await send(s, s.a, { figureId, index: 2 });
    expect(legs.strip).toBeUndefined();
    for (const user of [s.a, s.b]) {
      const parts = (await view(user)).recent_figures[0].parts;
      expect(parts.map((part: { drawing_media_asset_id: string | null }) => part.drawing_media_asset_id)).toEqual([
        head.drawing.assetId,
        body.drawing.assetId,
        legs.drawing.assetId,
      ]);
      expect(parts.map((part: { strip_media_asset_id: string | null }) => part.strip_media_asset_id)).toEqual([head.strip!.assetId, body.strip!.assetId, null]);
    }
    await settle(s);
  });

  test("the results have the documented fields", async () => {
    const s = await startGame();
    const head = await send(s, s.a, { figureId: newUuid(), index: 0, ideaId: EXQUISITE_CORPSE_IDEAS.en.head[0].id });
    expect(Object.keys(head.result).sort()).toEqual(["created_at", "figure_finished", "figure_id", "part_id", "part_index"]);
    const data = await view(s.b);
    expect(Object.keys(data).sort()).toEqual(["couple_id", "current_figure", "data_epoch", "game", "ideas", "partner_user_id", "recent_figures", "user_id"]);
    expect(Object.keys(data.game!).sort()).toEqual([
      "created_at",
      "figure_id",
      "figure_number",
      "figures_finished",
      "id",
      "part_index",
      "turn_started_at",
      "turn_user_id",
      "updated_at",
      "version",
    ]);
    expect(Object.keys(data.current_figure!).sort()).toEqual([
      "created_at",
      "finished_at",
      "id",
      "my_reveal_seen_at",
      "number",
      "parts",
      "starred_by_me",
      "starter_user_id",
    ]);
    expect(Object.keys(data.current_figure!.parts[0]).sort()).toEqual([
      "created_at",
      "drawer_user_id",
      "drawing_media_asset_id",
      "id",
      "idea",
      "part_index",
      "strip_media_asset_id",
    ]);
    await settle(s);
  });

  test("it refuses the wrong person, the wrong part, the wrong figure, and a reused id", async () => {
    const s = await startGame();
    const figureId = newUuid();
    const version = async () => (await gameOf(s.a)).version;

    // b is not up yet.
    const early = await prepare(s, s.b, { figureId, index: 0 });
    expect((await failure(submit(s.b, early.args))).message).toMatch(/not your turn/);
    // The head is next, not the body.
    const skipped = await prepare(s, s.a, { figureId, index: 1 });
    expect((await failure(submit(s.a, skipped.args))).code).toBe("23514");
    for (const index of [-1, 3, 1.5]) {
      const odd = await prepare(s, s.a, { figureId, index: index as 0 });
      expect((await failure(submit(s.a, odd.args))).code).toBe("22023");
    }
    expect(await version()).toBe(1);

    const head = await send(s, s.a, { figureId, index: 0 });
    // a cannot send twice in a row.
    const again = await prepare(s, s.a, { figureId, index: 1 });
    expect((await failure(submit(s.a, again.args))).message).toMatch(/not your turn/);
    // b names another figure, or the head's figure for a new head, or the head's part id.
    const strayFigure = await prepare(s, s.b, { figureId: newUuid(), index: 1 });
    expect((await failure(submit(s.b, strayFigure.args))).message).toMatch(/out of date/);
    const sameParts = await prepare(s, s.b, { figureId, index: 1, partId: head.partId });
    expect((await failure(submit(s.b, sameParts.args))).code).toBe("23505");
    expect(await version()).toBe(2);

    await send(s, s.b, { figureId, index: 1 });
    await send(s, s.a, { figureId, index: 2 });
    // The next head cannot reuse a figure id or a part id.
    const reusedFigure = await prepare(s, s.b, { figureId, index: 0 });
    expect((await failure(submit(s.b, reusedFigure.args))).code).toBe("23505");
    const reusedPart = await prepare(s, s.b, { figureId: newUuid(), index: 0, partId: head.partId });
    expect((await failure(submit(s.b, reusedPart.args))).code).toBe("23505");
    await settle(s);
  });

  test("the strip is required for the head and body and refused for the legs", async () => {
    const s = await startGame();
    const figureId = newUuid();
    const noStrip = await prepare(s, s.a, { figureId, index: 0 });
    const { p_strip_media_asset_id: _unused, ...withoutStrip } = noStrip.args;
    expect((await failure(submit(s.a, withoutStrip))).code).toBe("22023");
    await send(s, s.a, { figureId, index: 0 });

    const body = await prepare(s, s.b, { figureId, index: 1 });
    const { p_strip_media_asset_id: _alsoUnused, ...bodyWithoutStrip } = body.args;
    expect((await failure(submit(s.b, bodyWithoutStrip))).code).toBe("22023");
    await submit(s.b, body.args);

    const legs = await prepare(s, s.a, { figureId, index: 2 });
    const extra = await upload(s, s.a, legs.partId, "exquisite_corpse_strip");
    expect((await failure(submit(s.a, { ...legs.args, p_strip_media_asset_id: extra.assetId }))).code).toBe("22023");
    expect(await gameOf(s.a)).toMatchObject({ part_index: 2, version: 3 });
    await settle(s);
  });

  test("only the caller's own finished uploads of this part count", async () => {
    const s = await startGame();
    const figureId = newUuid();
    const good = await prepare(s, s.a, { figureId, index: 0 });
    const partId = good.partId;
    const bad = async (patch: Partial<SubmitArgs>, pattern = /not usable/) => {
      expect((await failure(submit(s.a, { ...good.args, ...op(), ...patch }))).message).toMatch(pattern);
    };

    // The partner's upload for the same part, an upload of another part, and an image from the memory bucket.
    const partners = await upload(s, s.b, partId, "exquisite_corpse_drawing");
    await bad({ p_drawing_media_asset_id: partners.assetId });
    const elsewhere = await upload(s, s.a, newUuid(), "exquisite_corpse_drawing");
    await bad({ p_drawing_media_asset_id: elsewhere.assetId });
    const image = await uploadAsset(s.t, s.a, photo(s.couple.coupleId));
    await bad({ p_drawing_media_asset_id: image.assetId });
    // A strip is not a drawing, and a drawing is not a strip.
    await bad({ p_drawing_media_asset_id: good.strip!.assetId });
    await bad({ p_strip_media_asset_id: good.drawing.assetId });
    // An upload that was reserved but never finished.
    const [reserved] = await s.a.as.mutation(api.media.create_pending_media_upload, {
      ...op(),
      p_reserved_parent_kind: "exquisite_corpse_part",
      p_reserved_parent_id: partId,
      p_upload_purpose: "exquisite_corpse_drawing",
      p_media_type: "drawing_payload",
      p_file_extension: "pkdrawing",
      p_couple_id: s.couple.coupleId,
      p_path_context: { game_id: s.gameId },
    });
    await bad({ p_drawing_media_asset_id: reserved.media_asset_id });
    await bad({ p_drawing_media_asset_id: newUuid() });

    expect(await submit(s.a, good.args)).toMatchObject({ part_id: partId });
    await settle(s);
  });

  test("a retry returns the first answer, and a changed retry is refused", async () => {
    const s = await startGame();
    const figureId = newUuid();
    const prepared = await prepare(s, s.a, { figureId, index: 0 });
    const first = await submit(s.a, prepared.args);
    expect(await submit(s.a, prepared.args)).toEqual(first);
    expect(await s.t.run((ctx) => ctx.db.query("exquisite_corpse_parts").collect())).toHaveLength(1);
    expect((await outbox(s.t)).filter((row) => row.kind === "game_turn_ready")).toHaveLength(1);
    expect((await gameOf(s.a)).version).toBe(2);

    const changed = await failure(submit(s.a, { ...prepared.args, p_idea_id: EXQUISITE_CORPSE_IDEAS.en.head[0].id }));
    expect(changed).toMatchObject({ code: "23505", message: expect.stringMatching(/replay hash mismatch/) });
    const otherStrip = await upload(s, s.a, prepared.partId, "exquisite_corpse_strip");
    expect((await failure(submit(s.a, { ...prepared.args, p_strip_media_asset_id: otherStrip.assetId }))).code).toBe("23505");
    await settle(s);
  });

  test("each sent part counts once for the streak, and both partners qualify the day", async () => {
    const s = await startGame();
    const figureId = newUuid();
    const head = await prepare(s, s.a, { figureId, index: 0 });
    await submit(s.a, head.args);
    await submit(s.a, head.args);
    const body = await send(s, s.b, { figureId, index: 1 });

    const events = await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events).toHaveLength(2);
    expect(events.find((event) => event.user_id === s.a.userId)).toMatchObject({
      activity_kind: "game_turn_completed",
      dedupe_key: `game_turn_completed:${head.partId}`,
      metadata: { game_id: s.gameId, figure_id: figureId, part_id: head.partId },
    });
    expect(events.find((event) => event.user_id === s.b.userId)).toMatchObject({ dedupe_key: `game_turn_completed:${body.partId}` });
    expect((await s.t.run((ctx) => ctx.db.query("streak_states").first()))?.current_count).toBe(1);
    await settle(s);
  });
});

describe("media", () => {
  test("a part's files are reserved under the game, and only for a game of the caller's couple", async () => {
    const s = await startGame();
    const partId = newUuid();
    const drawing = await upload(s, s.a, partId, "exquisite_corpse_drawing");
    const strip = await upload(s, s.a, partId, "exquisite_corpse_strip");
    for (const file of [drawing, strip]) {
      expect(file.bucket).toBe("game-drawings");
      expect(file.storagePath).toBe(`${s.couple.coupleId}/${s.gameId}/parts/${partId}/${file.assetId}.pkdrawing`);
    }

    const stranger = await createCouple(s.t);
    const reserve = (user: TestUser, coupleId: string, gameId?: string, patch: { p_reserved_parent_kind?: string; p_upload_purpose?: string } = {}) =>
      user.as.mutation(api.media.create_pending_media_upload, {
        ...op(),
        p_reserved_parent_kind: "exquisite_corpse_part",
        p_reserved_parent_id: newUuid(),
        p_upload_purpose: "exquisite_corpse_drawing",
        p_media_type: "drawing_payload",
        p_file_extension: "pkdrawing",
        p_couple_id: coupleId,
        ...(gameId ? { p_path_context: { game_id: gameId } } : {}),
        ...patch,
      });
    expect((await failure(reserve(s.a, s.couple.coupleId))).message).toMatch(/require a game id/);
    expect((await failure(reserve(stranger.first, stranger.coupleId, s.gameId))).code).toBe("42501");
    expect((await failure(reserve(s.a, stranger.coupleId, s.gameId))).code).toBe("42501");
    expect((await failure(reserve(s.a, s.couple.coupleId, newUuid()))).code).toBe("42501");
    // The kind and the purpose go together.
    expect((await failure(reserve(s.a, s.couple.coupleId, s.gameId, { p_reserved_parent_kind: "game_move" }))).code).toBe("23514");
    expect((await failure(reserve(s.a, s.couple.coupleId, s.gameId, { p_upload_purpose: "game_drawing_payload" }))).code).toBe("23514");
  });

  test("the partner reads a strip at once, a drawing only after the figure is finished, and the drawer always", async () => {
    const s = await startGame();
    const figureId = newUuid();
    const stranger = await createCouple(s.t);
    const head = await prepare(s, s.a, { figureId, index: 0 });
    // Nothing is attached yet, so nobody else can read either file.
    expect((await failure(signed(s.b, head.strip!.assetId))).code).toBe("42501");
    expect((await failure(signed(s.b, head.drawing.assetId))).code).toBe("42501");
    await submit(s.a, head.args);

    const [strip] = await signed(s.b, head.strip!.assetId);
    expect(strip).toMatchObject({ bucket: "game-drawings", storage_path: head.strip!.storagePath });
    expect(strip.signed_url).toContain(`asset=${head.strip!.assetId}`);
    expect((await failure(signed(s.b, head.drawing.assetId))).code).toBe("42501");
    for (const assetId of [head.strip!.assetId, head.drawing.assetId]) {
      expect(await signed(s.a, assetId)).toHaveLength(1);
      expect((await failure(signed(stranger.first, assetId))).code).toBe("42501");
    }

    const body = await send(s, s.b, { figureId, index: 1 });
    expect((await failure(signed(s.a, body.drawing.assetId))).code).toBe("42501");
    expect(await signed(s.a, body.strip!.assetId)).toHaveLength(1);
    await send(s, s.a, { figureId, index: 2 });

    for (const user of [s.a, s.b]) {
      expect(await signed(user, head.drawing.assetId)).toHaveLength(1);
      expect(await signed(user, body.drawing.assetId)).toHaveLength(1);
    }
    expect((await failure(signed(stranger.first, head.drawing.assetId))).code).toBe("42501");
    await settle(s);
  });

  test("the orphan sweep keeps a part's drawing and strip and queues an upload nobody attached", async () => {
    const s = await startGame();
    const head = await send(s, s.a, { figureId: newUuid(), index: 0 });
    const stray = await upload(s, s.a, newUuid(), "exquisite_corpse_drawing");
    tick(8 * 24 * HOUR);
    expect(await s.t.mutation(internal.media.sweep_orphan_storage, {})).toMatchObject({ queued: 1 });

    const status = (assetId: string) =>
      s.t.run(async (ctx) => (await ctx.db.query("media_assets").collect()).find((asset) => asset.id === assetId)?.storage_delete_status);
    expect(await status(head.drawing.assetId)).toBe("none");
    expect(await status(head.strip!.assetId)).toBe("none");
    expect(await status(stray.assetId)).toBe("pending");
    await settle(s);
  });
});

describe("reveal seen", () => {
  const seen = (user: TestUser, figureId: string) =>
    user.as.mutation(api.exquisiteCorpse.mark_exquisite_corpse_reveal_seen, { p_figure_id: figureId });

  test("each partner's time is set once, keeps the first write, and leaves the other empty", async () => {
    const s = await startGame();
    const { figureId } = await playFigure(s, s.a, s.b);
    const mine = (user: TestUser) => view(user).then((data) => data.recent_figures[0].my_reveal_seen_at);
    expect(await mine(s.a)).toBeNull();

    const first = await seen(s.b, figureId);
    expect(first).toEqual({ figure_id: figureId, reveal_seen_at: new Date(Date.now()).toISOString() });
    tick(60);
    expect(await seen(s.b, figureId)).toEqual(first);
    expect(await mine(s.b)).toBe(first.reveal_seen_at);
    expect(await mine(s.a)).toBeNull();

    const starter = await seen(s.a, figureId);
    expect(starter.reveal_seen_at).toBe(new Date(Date.now()).toISOString());
    const row = await s.t.run((ctx) => ctx.db.query("exquisite_corpse_figures").first());
    expect(row).toMatchObject({ starter_reveal_seen_at: starter.reveal_seen_at, partner_reveal_seen_at: first.reveal_seen_at });
    await settle(s);
  });

  test("a figure that is still in progress cannot be marked, and an unknown one is refused", async () => {
    const s = await startGame();
    const figureId = newUuid();
    await send(s, s.a, { figureId, index: 0 });
    expect((await failure(seen(s.a, figureId))).message).toMatch(/not finished/);
    expect((await failure(seen(s.a, newUuid()))).code).toBe("42501");
    await settle(s);
  });
});

describe("stars", () => {
  const star = (user: TestUser, figureId: string, starred: boolean) =>
    user.as.mutation(api.exquisiteCorpse.set_exquisite_corpse_star, { p_figure_id: figureId, p_starred: starred });
  const stars = (t: TestConvex) => t.run((ctx) => ctx.db.query("exquisite_corpse_stars").collect());

  test("a star is private, idempotent, and removed by unstarring, and nobody is told", async () => {
    const s = await startGame();
    const { figureId } = await playFigure(s, s.a, s.b);
    const queued = (await outbox(s.t)).length;

    expect(await star(s.a, figureId, true)).toEqual({ figure_id: figureId, starred: true });
    await star(s.a, figureId, true);
    expect(await stars(s.t)).toMatchObject([{ couple_id: s.couple.coupleId, user_id: s.a.userId, figure_id: figureId, figure_number: 1 }]);
    expect((await view(s.a)).recent_figures[0].starred_by_me).toBe(true);
    expect((await view(s.b)).recent_figures[0].starred_by_me).toBe(false);
    await star(s.b, figureId, true);
    expect(await stars(s.t)).toHaveLength(2);
    expect((await outbox(s.t)).length).toBe(queued);

    expect(await star(s.a, figureId, false)).toEqual({ figure_id: figureId, starred: false });
    await star(s.a, figureId, false);
    expect(await stars(s.t)).toMatchObject([{ user_id: s.b.userId }]);
    await settle(s);
  });

  test("only a finished figure can be starred", async () => {
    const s = await startGame();
    const figureId = newUuid();
    await send(s, s.a, { figureId, index: 0 });
    expect((await failure(star(s.a, figureId, true))).message).toMatch(/not finished/);
    expect(await stars(s.t)).toHaveLength(0);
    await settle(s);
  });
});

describe("history", () => {
  const history = (user: TestUser, args: { starredOnly?: boolean; before?: number | null; limit?: number } = {}) =>
    user.as.query(api.exquisiteCorpse.get_exquisite_corpse_history, {
      p_starred_only: args.starredOnly ?? false,
      p_before_figure_number: args.before ?? null,
      p_limit: args.limit ?? 30,
    });
  const numbers = (page: { figures: { number: number }[] }) => page.figures.map((figure) => figure.number);

  /** Finished figures 1 to `count` without parts, and one unfinished figure after them. */
  async function insertFigures(s: Setup, count: number): Promise<string[]> {
    return await s.t.run(async (ctx) => {
      const now = new Date().toISOString();
      const ids: string[] = [];
      for (let number = 1; number <= count + 1; number += 1) {
        const id = newUuid();
        ids.push(id);
        await ctx.db.insert("exquisite_corpse_figures", {
          id,
          couple_id: s.couple.coupleId,
          game_id: s.gameId,
          number,
          starter_user_id: s.a.userId,
          created_at: now,
          ...(number <= count ? { finished_at: now } : {}),
          updated_at: now,
        });
      }
      return ids;
    });
  }

  test("lists finished figures newest first with their parts, and the caller's own star", async () => {
    const s = await startGame();
    const one = await playFigure(s, s.a, s.b, { head: EXQUISITE_CORPSE_IDEAS.en.head[0].id });
    const two = await playFigure(s, s.b, s.a);
    await send(s, s.a, { figureId: newUuid(), index: 0 });
    await s.a.as.mutation(api.exquisiteCorpse.set_exquisite_corpse_star, { p_figure_id: one.figureId, p_starred: true });

    for (const user of [s.a, s.b]) {
      const page = await history(user);
      expect(numbers(page)).toEqual([2, 1]);
      expect(page.next_before_figure_number).toBeNull();
      expect(page.figures[0].id).toBe(two.figureId);
      for (const figure of page.figures) {
        expect(figure.parts).toHaveLength(3);
        expect(figure.parts.every((part: { drawing_media_asset_id: string | null }) => part.drawing_media_asset_id !== null)).toBe(true);
      }
    }
    expect((await history(s.a)).figures.map((figure: { starred_by_me: boolean }) => figure.starred_by_me)).toEqual([false, true]);
    expect((await history(s.b)).figures.map((figure: { starred_by_me: boolean }) => figure.starred_by_me)).toEqual([false, false]);
    expect(numbers(await history(s.a, { starredOnly: true }))).toEqual([1]);
    expect(numbers(await history(s.b, { starredOnly: true }))).toEqual([]);
    const idea = EXQUISITE_CORPSE_IDEAS.en.head[0];
    expect((await history(s.a)).figures[1].parts[0].idea).toEqual({ id: idea.id, text: idea.text });
    await settle(s);
  });

  test("pages by figure number, for all figures and for starred ones", async () => {
    const s = await startGame();
    const ids = await insertFigures(s, 5);
    for (const number of [1, 2, 4, 5]) {
      await s.a.as.mutation(api.exquisiteCorpse.set_exquisite_corpse_star, { p_figure_id: ids[number - 1], p_starred: true });
    }

    const first = await history(s.a, { limit: 2 });
    expect(numbers(first)).toEqual([5, 4]);
    expect(first.next_before_figure_number).toBe(4);
    const second = await history(s.a, { limit: 2, before: first.next_before_figure_number });
    expect(numbers(second)).toEqual([3, 2]);
    expect(second.next_before_figure_number).toBe(2);
    const last = await history(s.a, { limit: 2, before: second.next_before_figure_number });
    expect(numbers(last)).toEqual([1]);
    expect(last.next_before_figure_number).toBeNull();

    const starred = await history(s.a, { starredOnly: true, limit: 2 });
    expect(numbers(starred)).toEqual([5, 4]);
    expect(starred.next_before_figure_number).toBe(4);
    const rest = await history(s.a, { starredOnly: true, limit: 2, before: starred.next_before_figure_number });
    expect(numbers(rest)).toEqual([2, 1]);
    expect(rest.next_before_figure_number).toBeNull();
  });

  test("a page holds at most 50 figures, the limit must be positive, and get_exquisite_corpse returns 10", async () => {
    const s = await startGame();
    await insertFigures(s, 60);
    const page = await history(s.a, { limit: 1000 });
    expect(page.figures).toHaveLength(50);
    expect(page.figures[0].number).toBe(60);
    expect(page.next_before_figure_number).toBe(11);
    expect(numbers(await history(s.a, { limit: 1000, before: 11 }))).toHaveLength(10);
    expect((await failure(history(s.a, { limit: 0 }))).code).toBe("23514");
    expect((await view(s.a)).recent_figures.map((figure: { number: number }) => figure.number)).toEqual([60, 59, 58, 57, 56, 55, 54, 53, 52, 51]);
  });

  test("another couple sees none of it", async () => {
    const s = await startGame();
    await playFigure(s, s.a, s.b);
    const other = await startGame();
    expect(await history(other.a)).toEqual({ figures: [], next_before_figure_number: null });
    expect(await history(other.a, { starredOnly: true })).toEqual({ figures: [], next_before_figure_number: null });
    await settle(s);
    await settle(other);
  });
});

describe("pushes", () => {
  const kinds = (rows: { payload: unknown }[]) => rows.map((row) => (row.payload as { type: string }).type).sort();
  const claim = (s: Setup) => deliverDuePushes(s.t);
  const errorsOf = async (s: Setup, kind: string) => (await outbox(s.t)).filter((row) => row.kind === kind).map((row) => row.last_error ?? null);

  test("a head or body queues a lock-screen-safe turn push, and the legs queue a result push", async () => {
    const s = await startGame();
    const { figureId, head, body, legs } = await playFigure(s, s.a, s.b, { head: EXQUISITE_CORPSE_IDEAS.en.head[0].id });
    const rows = await outbox(s.t);

    const turns = rows.filter((row) => row.kind === "game_turn_ready");
    expect(turns).toHaveLength(2);
    expect(turns[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      apns_push_type: "alert",
      dedupe_key: expect.stringContaining(`exquisite_corpse:turn:${head.partId}`),
      payload: {
        type: "game_turn_ready",
        game_kind: "exquisite_corpse",
        couple_id: s.couple.coupleId,
        game_id: s.gameId,
        round_id: figureId,
        actor_user_id: s.a.userId,
        route: "games",
        deeplink: "paeonia://games/exquisite-corpse",
        step: "body",
      },
      body: "Your turn to draw the body.",
    });
    expect(turns[1]).toMatchObject({
      recipient_user_id: s.a.userId,
      dedupe_key: expect.stringContaining(`exquisite_corpse:turn:${body.partId}`),
      payload: { actor_user_id: s.b.userId, step: "legs" },
      body: "Your turn to draw the legs.",
    });

    const results = rows.filter((row) => row.kind === "game_result");
    expect(results).toHaveLength(1);
    expect(results[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      dedupe_key: expect.stringContaining(`exquisite_corpse:finished:${figureId}`),
      payload: { type: "game_result", game_kind: "exquisite_corpse", round_id: figureId, actor_user_id: s.a.userId },
      body: "Open it to see the whole thing.",
    });
    expect(results[0].payload).not.toHaveProperty("step");
    // The payload holds ids only. It never names a drawing, a strip, or an idea.
    for (const row of rows) {
      const text = JSON.stringify(row);
      for (const secret of [head.drawing.assetId, head.strip!.assetId, legs.drawing.assetId, EXQUISITE_CORPSE_IDEAS.en.head[0].text]) {
        expect(text).not.toContain(secret);
      }
    }
    await settle(s);
  });

  test("an open game screen on the recipient's phone suppresses the turn and result pushes", async () => {
    const s = await startGame();
    // The presence component times sessions out with scheduled functions, so fake every timer.
    vi.useFakeTimers();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "exquisite_corpse", p_present: true });
    const figureId = newUuid();
    await send(s, s.a, { figureId, index: 0 });
    expect(await outbox(s.t)).toHaveLength(0);

    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "exquisite_corpse", p_present: false });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "exquisite_corpse", p_present: true });
    await send(s, s.b, { figureId, index: 1 });
    expect(await outbox(s.t)).toHaveLength(0);

    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "exquisite_corpse", p_present: false });
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "exquisite_corpse", p_present: true });
    await send(s, s.a, { figureId, index: 2 });
    expect(await outbox(s.t)).toHaveLength(0);

    // A screen that stopped its heartbeats does not count.
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "exquisite_corpse", p_present: true });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    await send(s, s.b, { figureId: newUuid(), index: 0 });
    expect(kinds(await outbox(s.t))).toEqual(["game_turn_ready"]);
    await settle(s);
  });

  test("the drain drops a turn push once the recipient has sent their part", async () => {
    const s = await startGame();
    const figureId = newUuid();
    await send(s, s.a, { figureId, index: 0 });
    // b answers before the drain runs, so the push for b's turn is out of date and a's push is current.
    await send(s, s.b, { figureId, index: 1 });
    expect(kinds(await claim(s))).toEqual(["game_turn_ready"]);
    const rows = await outbox(s.t);
    const toB = rows.find((row) => row.recipient_user_id === s.b.userId)!;
    const toA = rows.find((row) => row.recipient_user_id === s.a.userId)!;
    expect(toB.last_error).toBe("notification is out of date");
    expect(toA.last_error ?? null).toBeNull();
    await settle(s);
  });

  test("the drain drops a turn push once the figure is finished, and a result push once the reveal was seen", async () => {
    const s = await startGame();
    await playFigure(s, s.a, s.b);
    // a's body push and b's head push are out of date. b's result push is current until b has seen the reveal.
    expect(kinds(await claim(s))).toEqual(["game_result"]);
    expect(await errorsOf(s, "game_turn_ready")).toEqual(["notification is out of date", "notification is out of date"]);

    const again = await startGame();
    const second = await playFigure(again, again.a, again.b);
    await again.b.as.mutation(api.exquisiteCorpse.mark_exquisite_corpse_reveal_seen, { p_figure_id: second.figureId });
    expect(await claim(again)).toEqual([]);
    expect(await errorsOf(again, "game_result")).toEqual(["notification is out of date"]);
    await settle(s);
    await settle(again);
  });

  test("the Games switch turns the pushes off", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    await send(s, s.a, { figureId: newUuid(), index: 0 });
    expect(await outbox(s.t)).toHaveLength(0);
    await settle(s);
  });
});

describe("turn reminder", () => {
  const run = (s: Setup) => s.t.mutation(internal.games.send_due_game_turn_reminders, {});
  const reminders = async (s: Setup) => (await outbox(s.t)).filter((row) => row.kind === "game_turn_reminder");

  test("goes out once after 72 hours to the partner whose turn it is, and again only for a new turn", async () => {
    const s = await startGame();
    tick(71 * HOUR);
    expect(await run(s)).toBe(0);
    tick(HOUR);
    expect(await run(s)).toBe(1);
    expect(await run(s)).toBe(0);
    tick(10 * HOUR);
    expect(await run(s)).toBe(0);

    let rows = await reminders(s);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.a.userId,
      dedupe_key: expect.stringContaining(`exquisite_corpse:reminder:${s.gameId}:${new Date(START).toISOString()}`),
      payload: { type: "game_turn_reminder", game_kind: "exquisite_corpse", game_id: s.gameId, actor_user_id: s.b.userId, deeplink: "paeonia://games/exquisite-corpse" },
    });
    const game = await s.t.run((ctx) => ctx.db.query("exquisite_corpse_games").first());
    expect(game?.turn_reminder_sent_at).toBeDefined();

    // a finally draws. The turn moves to b, and b's wait starts now.
    await send(s, s.a, { figureId: newUuid(), index: 0 });
    expect((await s.t.run((ctx) => ctx.db.query("exquisite_corpse_games").first()))?.turn_reminder_sent_at).toBeUndefined();
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);
    expect(await run(s)).toBe(0);
    rows = await reminders(s);
    expect(rows.map((row) => row.recipient_user_id)).toEqual([s.a.userId, s.b.userId]);
    await settle(s);
  });

  test("the drain drops a reminder once the turn moved on", async () => {
    const s = await startGame();
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);
    await send(s, s.a, { figureId: newUuid(), index: 0 });
    const claimed = await deliverDuePushes(s.t);
    expect(claimed.map((row) => row.payload.type)).toEqual(["game_turn_ready"]);
    expect((await reminders(s))[0].last_error).toBe("notification is out of date");
    await settle(s);
  });

  test("an old reminder still waiting in the outbox stays out of date on a later turn of the same person", async () => {
    const s = await startGame();
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);
    // The head reminder is never claimed. a draws the head, b the body, and a's legs turn waits too.
    const figureId = newUuid();
    await send(s, s.a, { figureId, index: 0 });
    await send(s, s.b, { figureId, index: 1 });
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);

    const claimed = await deliverDuePushes(s.t);
    const sent = claimed.filter((row) => row.payload.type === "game_turn_reminder");
    expect(sent.map((row) => row.payload.step)).toEqual(["turn_1_2"]);
    const stale = (await reminders(s)).find((row) => (row.payload as { step?: string }).step === "turn_1_0");
    expect(stale?.last_error).toBe("notification is out of date");
    await settle(s);
  });

  test("respects the Games switch and a couple that is no longer active", async () => {
    const s = await startGame();
    await s.a.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    tick(80 * HOUR);
    expect(await run(s)).toBe(0);
    expect(await outbox(s.t)).toHaveLength(0);

    const other = await startGame();
    await endCouple(other.t, other.couple.coupleId, other.a.userId);
    tick(80 * HOUR);
    expect(await run(other)).toBe(0);
    await settle(s);
  });
});

describe("relationship end", () => {
  test("cleanup deletes every row of the game and queues the drawings, and another couple keeps its game", async () => {
    const s = await startGame();
    const { figureId, head } = await playFigure(s, s.a, s.b);
    await s.a.as.mutation(api.exquisiteCorpse.set_exquisite_corpse_star, { p_figure_id: figureId, p_starred: true });
    await send(s, s.b, { figureId: newUuid(), index: 0 });
    const keep = await startGame({ t: s.t });
    await playFigure(keep, keep.a, keep.b);

    const tables = ["exquisite_corpse_games", "exquisite_corpse_figures", "exquisite_corpse_parts", "exquisite_corpse_stars"] as const;
    const count = (t: TestConvex, coupleId: string) =>
      t.run(async (ctx) => {
        const result: Record<string, number> = {};
        for (const table of tables) {
          result[table] = (await ctx.db.query(table).collect()).filter((row) => row.couple_id === coupleId).length;
        }
        return result;
      });
    expect(await count(s.t, s.couple.coupleId)).toEqual({
      exquisite_corpse_games: 1,
      exquisite_corpse_figures: 2,
      exquisite_corpse_parts: 4,
      exquisite_corpse_stars: 1,
    });

    await s.a.as.mutation(api.relationship.leave_relationship, op());
    await s.t.mutation(internal.relationship.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" });
    expect(Object.values(await count(s.t, s.couple.coupleId)).every((rows) => rows === 0)).toBe(true);
    expect(await count(keep.t, keep.couple.coupleId)).toMatchObject({
      exquisite_corpse_games: 1,
      exquisite_corpse_figures: 1,
      exquisite_corpse_parts: 3,
    });

    const drawings = await s.t.run(async (ctx) =>
      (await ctx.db.query("media_assets").collect()).filter(
        (asset) => asset.reserved_parent_kind === "exquisite_corpse_part" && asset.couple_id === s.couple.coupleId,
      ),
    );
    // Four parts with a drawing each, and a strip for each head and body.
    expect(drawings).toHaveLength(4 + 3);
    expect(drawings.every((asset) => asset.storage_delete_status === "pending")).toBe(true);
    await s.t.mutation(internal.media.cleanup_media_storage, {});
    const after = await s.t.run(async (ctx) => (await ctx.db.query("media_assets").collect()).find((asset) => asset.id === head.drawing.assetId));
    expect(after).toMatchObject({ storage_delete_status: "deleted" });
    await settle(s);
    await settle(keep);
  });
});
