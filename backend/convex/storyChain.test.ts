// Tests for the Story Chain functions in storyChain.ts and the hooks in lib/storyChain.ts. The pure
// rules (line limits, dare check, choice picking, content lists) are in lib/storyChain.test.ts.
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { STORY_OPENINGS, STORY_WORDS } from "./lib/storyChain";
import { deleteCoupleGameRows } from "./lib/gameRegistry";
import { endCouple, failure, op } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

const START = Date.parse("2026-10-10T12:00:00.000Z");

const opened: TestConvex[] = [];

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(async () => {
  try {
    for (const t of opened.splice(0)) await t.finishAllScheduledFunctions(vi.runAllTimers);
  } finally {
    vi.useRealTimers();
  }
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));
const HOUR = 3600;

type Setup = { t: TestConvex; a: TestUser; b: TestUser; coupleId: string; gameId: string };
type StartOptions = { language?: "en" | "nb"; locales?: { a?: string; b?: string } };

/** A couple with a push device each, game settings, and a Story Chain game. `a` starts. */
async function startGameIn(t: TestConvex, options: StartOptions = {}): Promise<Setup> {
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await addDevice(t, a.userId, { locale: options.locales?.a });
  await addDevice(t, b.userId, { locale: options.locales?.b });
  await a.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: options.language ?? "en" });
  const { game_id } = await a.as.mutation(api.storyChain.ensure_story_chain_game, {});
  return { t, a, b, coupleId: couple.coupleId, gameId: game_id };
}

/** A fresh deployment with a started game. Its scheduled push drains run when the test ends. */
async function startGame(options: StartOptions = {}): Promise<Setup> {
  return await startGameIn(newDeployment(), options);
}

function newDeployment(): TestConvex {
  const t = newTest();
  opened.push(t);
  return t;
}

const view = (user: TestUser) => user.as.query(api.storyChain.get_story_chain, {});
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
const pushesOf = async (t: TestConvex, kind: string) => (await outbox(t)).filter((row) => row.kind === kind);
const gameRow = (t: TestConvex, gameId: string) =>
  t.run(async (ctx) => (await ctx.db.query("story_chain_games").withIndex("by_uuid", (q) => q.eq("id", gameId)).unique())!);
const storyRow = (t: TestConvex, storyId: string) =>
  t.run(async (ctx) => (await ctx.db.query("story_chain_stories").withIndex("by_uuid", (q) => q.eq("id", storyId)).unique())!);
const streakEvents = (t: TestConvex) =>
  t.run(async (ctx) => (await ctx.db.query("couple_activity_events").collect()).filter((event) => event.activity_kind === "game_turn_completed"));
const usedRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("story_chain_used").collect());

function begin(user: TestUser, gameId: string, openingId: string | null = null, storyId: string = newUuid()) {
  return user.as.mutation(api.storyChain.start_story, { ...op(), p_game_id: gameId, p_story_id: storyId, p_opening_id: openingId });
}

type LineOptions = { last?: boolean; dare?: string | null; dareId?: string | null; lineId?: string };

function write(user: TestUser, storyId: string, text: string, options: LineOptions = {}) {
  return user.as.mutation(api.storyChain.add_story_line, {
    ...op(),
    p_story_id: storyId,
    p_line_id: options.lineId ?? newUuid(),
    p_text: text,
    p_is_last: options.last ?? false,
    p_dare_word: options.dare ?? null,
    p_dare_word_id: options.dareId ?? null,
  });
}

const name = (user: TestUser, storyId: string, title: string) =>
  user.as.mutation(api.storyChain.name_story, { ...op(), p_story_id: storyId, p_title: title });
const seen = (user: TestUser, storyId: string) => user.as.mutation(api.storyChain.mark_story_seen, { p_story_id: storyId });
const star = (user: TestUser, storyId: string, starred: boolean) =>
  user.as.mutation(api.storyChain.set_story_star, { p_story_id: storyId, p_starred: starred });
const history = (user: TestUser, options: { starred?: boolean; before?: number | null; limit?: number } = {}) =>
  user.as.query(api.storyChain.get_story_chain_history, {
    p_starred_only: options.starred ?? false,
    p_before_story_number: options.before ?? null,
    p_limit: options.limit ?? 30,
  });

type StoryOptions = { label?: string; lines?: number; openingId?: string | null };

/**
 * `starter` starts a story and the two partners write `lines` lines in turn, `starter` first. The
 * last line ends the story. Returns who wrote the last line and who has to name the story.
 */
async function reachTitling(s: Setup, starter: TestUser, options: StoryOptions = {}) {
  const other = starter.userId === s.a.userId ? s.b : s.a;
  const label = options.label ?? "the story";
  const lines = options.lines ?? 8;
  const writer = (number: number) => (number % 2 === 1 ? starter : other);
  const { story_id: storyId } = await begin(starter, s.gameId, options.openingId ?? null);
  for (let number = 1; number < lines; number += 1) await write(writer(number), storyId, `Line ${number} of ${label}.`);
  const lastWriter = writer(lines);
  const { line_id: lastLineId } = await write(lastWriter, storyId, `Line ${lines} of ${label}.`, { last: true });
  return { storyId, lastLineId, lastWriter, namer: lastWriter === starter ? other : starter };
}

/** `reachTitling`, then the other partner names the story. The namer is the next one to start. */
async function playStory(s: Setup, starter: TestUser, title: string, options: StoryOptions = {}) {
  const reached = await reachTitling(s, starter, { label: title, ...options });
  await name(reached.namer, reached.storyId, title);
  return reached;
}

/** Marks openings or words as already used by the couple's game. */
async function markUsed(s: Setup, kind: "opening" | "word", language: "en" | "nb", contentIds: string[]) {
  await s.t.run(async (ctx) => {
    for (const contentId of contentIds) {
      await ctx.db.insert("story_chain_used", {
        game_id: s.gameId,
        couple_id: s.coupleId,
        language,
        kind,
        content_id: contentId,
        created_at: new Date().toISOString(),
      });
    }
  });
}

describe("access", () => {
  test("a signed-out caller is refused", async () => {
    const s = await startGame();
    const calls: (() => Promise<unknown>)[] = [
      () => s.t.mutation(api.storyChain.ensure_story_chain_game, {}),
      () => s.t.query(api.storyChain.get_story_chain, {}),
      () => s.t.query(api.storyChain.get_story_chain_story, { p_story_id: newUuid() }),
      () => s.t.query(api.storyChain.get_story_chain_history, { p_starred_only: false, p_limit: 5 }),
      () => s.t.mutation(api.storyChain.start_story, { ...op(), p_game_id: s.gameId, p_story_id: newUuid(), p_opening_id: null }),
      () =>
        s.t.mutation(api.storyChain.add_story_line, {
          ...op(),
          p_story_id: newUuid(),
          p_line_id: newUuid(),
          p_text: "Hello there.",
          p_is_last: false,
        }),
      () => s.t.mutation(api.storyChain.name_story, { ...op(), p_story_id: newUuid(), p_title: "Title" }),
      () => s.t.mutation(api.storyChain.mark_story_seen, { p_story_id: newUuid() }),
      () => s.t.mutation(api.storyChain.set_story_star, { p_story_id: newUuid(), p_starred: true }),
    ];
    for (const call of calls) expect((await failure(call())).code).toBe("42501");
  });

  test("a user without a couple is refused and reads nothing", async () => {
    const t = newDeployment();
    const loner = await createSignedInUser(t, { name: "Loner" });
    const calls: (() => Promise<unknown>)[] = [
      () => loner.as.mutation(api.storyChain.ensure_story_chain_game, {}),
      () => loner.as.query(api.storyChain.get_story_chain, {}),
      () => loner.as.query(api.storyChain.get_story_chain_history, { p_starred_only: false, p_limit: 5 }),
      () => begin(loner, newUuid()),
      () => write(loner, newUuid(), "Hello there."),
      () => name(loner, newUuid(), "Title"),
      () => seen(loner, newUuid()),
      () => star(loner, newUuid(), true),
    ];
    for (const call of calls) expect((await failure(call())).code).toBe("42501");
    expect(await loner.as.query(api.storyChain.get_story_chain_story, { p_story_id: newUuid() })).toBeNull();
  });

  test("a couple without a subscription is refused", async () => {
    const t = newDeployment();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.mutation(api.storyChain.ensure_story_chain_game, {}))).code).toBe("42501");
    expect((await failure(couple.first.as.query(api.storyChain.get_story_chain, {}))).code).toBe("42501");
  });

  test("a subscription that ends blocks the existing game", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    await s.t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect((await failure(write(s.b, story_id, "Line two."))).code).toBe("42501");
    expect((await failure(view(s.b))).code).toBe("42501");
    expect(await s.b.as.query(api.storyChain.get_story_chain_story, { p_story_id: story_id })).toBeNull();
  });

  test("a user outside the couple cannot read or act on a story", async () => {
    const s = await startGame();
    const first = await playStory(s, s.a, "Ours");
    const { story_id } = await begin(first.namer, s.gameId);
    await write(first.namer, story_id, "A line.");

    const outsider = (await startGameIn(s.t)).a;
    expect(await outsider.as.query(api.storyChain.get_story_chain_story, { p_story_id: story_id })).toBeNull();
    expect(await outsider.as.query(api.storyChain.get_story_chain_story, { p_story_id: first.storyId })).toBeNull();
    const own = await view(outsider);
    expect(own.game?.id).not.toBe(s.gameId);
    expect(own.current_story).toBeNull();
    expect(own.previous_story).toBeNull();
    expect((await history(outsider)).stories).toEqual([]);

    const calls: (() => Promise<unknown>)[] = [
      () => begin(outsider, s.gameId),
      () => write(outsider, story_id, "My line."),
      () => name(outsider, first.storyId, "Mine"),
      () => seen(outsider, first.storyId),
      () => star(outsider, first.storyId, true),
    ];
    for (const call of calls) expect((await failure(call())).code).toBe("42501");
    expect((await storyRow(s.t, story_id)).lines).toHaveLength(1);
  });

  test("a partner who left cannot play after the relationship ends", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    await endCouple(s.t, s.coupleId, s.a.userId);
    expect((await failure(write(s.b, story_id, "Line two."))).code).toBe("42501");
    expect((await failure(view(s.b))).code).toBe("42501");
    expect(await s.b.as.query(api.storyChain.get_story_chain_story, { p_story_id: story_id })).toBeNull();
  });

  test("a pending account deletion blocks writes", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    await s.t.run(async (ctx) => {
      await ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: s.a.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        auth_delete_attempts: 0,
        next_attempt_at: new Date().toISOString(),
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
    });
    const calls: (() => Promise<unknown>)[] = [
      () => s.a.as.mutation(api.storyChain.ensure_story_chain_game, {}),
      () => begin(s.a, s.gameId),
      () => write(s.a, story_id, "Line one."),
      () => name(s.a, story_id, "Title"),
      () => seen(s.a, story_id),
      () => star(s.a, story_id, true),
    ];
    for (const call of calls) expect((await failure(call())).message).toMatch(/account deletion/);
    expect((await storyRow(s.t, story_id)).lines).toHaveLength(0);
  });
});

describe("ensure_story_chain_game", () => {
  test("creates one game with the caller on turn, and returns it again", async () => {
    const s = await startGame();
    expect(await s.b.as.mutation(api.storyChain.ensure_story_chain_game, {})).toEqual({ game_id: s.gameId, created: false });
    expect(await s.a.as.mutation(api.storyChain.ensure_story_chain_game, {})).toEqual({ game_id: s.gameId, created: false });
    const data = await view(s.a);
    expect(data).toMatchObject({ user_id: s.a.userId, partner_user_id: s.b.userId, couple_id: s.coupleId });
    expect(data.game).toMatchObject({
      id: s.gameId,
      state: "choosing_opening",
      turn_user_id: s.a.userId,
      turn_number: 1,
      current_story_id: null,
      story_count: 0,
      finished_count: 0,
      version: 1,
    });
    expect(data.current_story).toBeNull();
    expect(data.previous_story).toBeNull();
    expect(await s.t.run((ctx) => ctx.db.query("story_chain_games").collect())).toHaveLength(1);
  });

  test("the game needs the couple's settings first", async () => {
    const t = newDeployment();
    const couple = await createCouple(t);
    const refusal = await failure(couple.first.as.mutation(api.storyChain.ensure_story_chain_game, {}));
    expect(refusal).toMatchObject({ code: "23514" });
    expect(refusal.message).toMatch(/settings are required/);
  });

  test("the game needs two active partners", async () => {
    const t = newDeployment();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    await t.run(async (ctx) => {
      const member = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.coupleId).eq("user_id", couple.second.userId))
        .unique();
      await ctx.db.patch(member!._id, { status: "left" });
    });
    const refusal = await failure(couple.first.as.mutation(api.storyChain.ensure_story_chain_game, {}));
    expect(refusal).toMatchObject({ code: "23514" });
    expect(refusal.message).toMatch(/two active partners/);
    expect(await t.run((ctx) => ctx.db.query("story_chain_games").collect())).toHaveLength(0);
  });

  test("two partners opening at the same time still get one game", async () => {
    const t = newDeployment();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    const [x, y] = await Promise.all([
      couple.first.as.mutation(api.storyChain.ensure_story_chain_game, {}),
      couple.second.as.mutation(api.storyChain.ensure_story_chain_game, {}),
    ]);
    expect(x.game_id).toBe(y.game_id);
    expect([x.created, y.created].sort()).toEqual([false, true]);
    expect(await t.run((ctx) => ctx.db.query("story_chain_games").collect())).toHaveLength(1);
  });
});

describe("get_story_chain", () => {
  test("shows no game before one exists", async () => {
    const t = newDeployment();
    const couple = await createCouple(t);
    expect(await view(couple.first)).toEqual({
      user_id: couple.first.userId,
      partner_user_id: couple.second.userId,
      couple_id: couple.coupleId,
      game: null,
      current_story: null,
      previous_story: null,
      opening_choices: null,
      word_choices: null,
    });
  });

  test("shows the current story and the one before it", async () => {
    const s = await startGame();
    const first = await playStory(s, s.a, "One");
    const second = await begin(first.namer, s.gameId);
    await write(first.namer, second.story_id, "Second story, line one.");

    const forB = await view(s.b);
    expect(forB.game).toMatchObject({ state: "writing", current_story_id: second.story_id, story_count: 2, finished_count: 1 });
    expect(forB.current_story).toMatchObject({ id: second.story_id, story_number: 2, state: "writing", seen_by_me: false });
    expect(forB.previous_story).toMatchObject({ id: first.storyId, story_number: 1, state: "finished", title: "One", seen_by_me: false });
    // The namer saw their story when they named it.
    expect((await view(s.a)).previous_story).toMatchObject({ id: first.storyId, seen_by_me: true });
  });

  describe("opening choices", () => {
    test("the starter sees three different openings, the partner none, and the same three on every read", async () => {
      const s = await startGame();
      const mine = (await view(s.a)).opening_choices!;
      expect(mine).toHaveLength(3);
      expect(new Set(mine.map((choice) => choice.opening_id)).size).toBe(3);
      for (const choice of mine) {
        expect(STORY_OPENINGS.en.find((opening) => opening.id === choice.opening_id)?.text).toBe(choice.text);
      }
      expect((await view(s.a)).opening_choices).toEqual(mine);
      expect((await view(s.b)).opening_choices).toBeNull();
      expect((await view(s.a)).word_choices).toBeNull();
    });

    test("a language change shows openings in the new language at once", async () => {
      const s = await startGame({ language: "en" });
      const en = (await view(s.a)).opening_choices!;
      await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
      const nb = (await view(s.a)).opening_choices!;
      expect(nb).toHaveLength(3);
      for (const choice of nb) {
        expect(STORY_OPENINGS.nb.find((opening) => opening.id === choice.opening_id)?.text).toBe(choice.text);
      }
      expect(nb.map((choice) => choice.opening_id)).not.toEqual(en.map((choice) => choice.opening_id));
    });

    test("an opening the couple already used is not offered until the list runs out", async () => {
      const s = await startGame();
      const ids = (choices: { opening_id: string }[] | null) => choices!.map((choice) => choice.opening_id).sort();
      const keep = STORY_OPENINGS.en.slice(10, 13).map((opening) => opening.id);
      await markUsed(s, "opening", "en", STORY_OPENINGS.en.filter((opening) => !keep.includes(opening.id)).map((opening) => opening.id));
      // Openings used in the other language do not count.
      await markUsed(s, "opening", "nb", STORY_OPENINGS.nb.slice(0, 5).map((opening) => opening.id));
      expect(ids((await view(s.a)).opening_choices)).toEqual([...keep].sort());

      // Two unused openings are fewer than three, so the list starts over.
      await markUsed(s, "opening", "en", [keep[0]]);
      const again = ids((await view(s.a)).opening_choices);
      expect(again).toHaveLength(3);
      expect(new Set(again).size).toBe(3);
      expect(again.some((id) => id !== keep[1] && id !== keep[2])).toBe(true);
    });

    test("an opening that starts a story is marked used, and the marks start over once the list is nearly empty", async () => {
      const s = await startGame();
      const keep = STORY_OPENINGS.en.slice(0, 4).map((opening) => opening.id);
      await markUsed(s, "opening", "en", STORY_OPENINGS.en.slice(4).map((opening) => opening.id));
      const offered = (await view(s.a)).opening_choices!.map((choice) => choice.opening_id);
      expect(offered.every((id) => keep.includes(id))).toBe(true);
      const left = keep.filter((id) => !offered.includes(id));

      // Four unused: picking one leaves three, which is enough to keep going without a restart.
      const first = await playStory(s, s.a, "One", { openingId: offered[0] });
      expect((await usedRows(s.t)).filter((row) => row.content_id === offered[0])).toHaveLength(1);
      const next = (await view(first.namer)).opening_choices!.map((choice) => choice.opening_id);
      expect(next.sort()).toEqual([...offered.slice(1), ...left].sort());

      // Three unused: picking one leaves two, so the next choices start over.
      await playStory(s, first.namer, "Two", { openingId: next[0] });
      const restarted = (await view(first.namer)).opening_choices!;
      expect(restarted).toHaveLength(3);
      expect(restarted.some((choice) => !next.slice(1).includes(choice.opening_id))).toBe(true);

      // Picking now deletes the old marks and keeps only this one.
      await playStory(s, first.namer, "Three", { openingId: restarted[0].opening_id });
      const rows = (await usedRows(s.t)).filter((row) => row.kind === "opening" && row.language === "en");
      expect(rows.map((row) => row.content_id)).toEqual([restarted[0].opening_id]);
    });
  });

  describe("word choices", () => {
    test("only the writer gets three different words, fixed for the turn", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      const mine = (await view(s.a)).word_choices!;
      expect(mine).toHaveLength(3);
      expect(new Set(mine.map((choice) => choice.word_id)).size).toBe(3);
      for (const choice of mine) {
        expect(STORY_WORDS.en.find((word) => word.id === choice.word_id)?.text).toBe(choice.word);
      }
      expect((await view(s.a)).word_choices).toEqual(mine);
      expect((await view(s.a)).opening_choices).toBeNull();
      expect((await view(s.b)).word_choices).toBeNull();

      await write(s.a, story_id, "Line one.");
      expect((await view(s.a)).word_choices).toBeNull();
      expect((await view(s.b)).word_choices).toHaveLength(3);
    });

    test("a word follows the language setting and a word the couple already dared is not suggested", async () => {
      const s = await startGame();
      await begin(s.a, s.gameId);
      await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
      const nb = (await view(s.a)).word_choices!;
      for (const choice of nb) {
        expect(STORY_WORDS.nb.find((word) => word.id === choice.word_id)?.text).toBe(choice.word);
      }

      const keep = STORY_WORDS.nb.slice(20, 23).map((word) => word.id);
      await markUsed(s, "word", "nb", STORY_WORDS.nb.filter((word) => !keep.includes(word.id)).map((word) => word.id));
      expect((await view(s.a)).word_choices!.map((choice) => choice.word_id).sort()).toEqual([...keep].sort());
    });

    test("nobody gets words in the other states", async () => {
      const s = await startGame();
      expect((await view(s.a)).word_choices).toBeNull();
      expect((await view(s.b)).word_choices).toBeNull();
      const reached = await reachTitling(s, s.a);
      for (const user of [s.a, s.b]) {
        const data = await view(user);
        expect(data.word_choices).toBeNull();
        expect(data.opening_choices).toBeNull();
      }
      await name(reached.namer, reached.storyId, "Done");
      expect((await view(s.a)).word_choices).toBeNull();
      expect((await view(s.b)).word_choices).toBeNull();
    });
  });
});

describe("start_story", () => {
  test("starts a story with an opening and marks the opening used", async () => {
    const s = await startGame();
    const opening = (await view(s.a)).opening_choices![1];
    const storyId = newUuid();
    expect(await begin(s.a, s.gameId, opening.opening_id, storyId)).toEqual({ story_id: storyId, story_number: 1 });

    const data = await view(s.b);
    expect(data.game).toMatchObject({ state: "writing", turn_user_id: s.a.userId, current_story_id: storyId, story_count: 1, version: 2 });
    expect(data.current_story).toMatchObject({
      id: storyId,
      story_number: 1,
      starter_user_id: s.a.userId,
      opening_id: opening.opening_id,
      opening_text: opening.text,
      state: "writing",
      lines: [],
      last_line_user_id: null,
      title: null,
    });
    expect(await usedRows(s.t)).toMatchObject([{ kind: "opening", language: "en", content_id: opening.opening_id }]);
  });

  test("starts a story with the starter's own line and no opening", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId, null);
    expect((await view(s.a)).current_story).toMatchObject({ opening_id: null, opening_text: null, lines: [] });
    expect(await usedRows(s.t)).toEqual([]);
    // The starter keeps the turn and writes line 1.
    expect(await write(s.a, story_id, "It all began here.")).toMatchObject({ number: 1 });
  });

  test("takes an opening from the other language", async () => {
    const s = await startGame({ language: "en" });
    const norwegian = STORY_OPENINGS.nb[0];
    const { story_id } = await begin(s.a, s.gameId, norwegian.id);
    expect((await view(s.a)).current_story).toMatchObject({ id: story_id, opening_id: norwegian.id, opening_text: norwegian.text });
    expect(await usedRows(s.t)).toMatchObject([{ kind: "opening", language: "nb", content_id: norwegian.id }]);
  });

  test("refuses an opening that is not in any list and starts nothing", async () => {
    const s = await startGame();
    const refusal = await failure(begin(s.a, s.gameId, "no_such_opening"));
    expect(refusal).toMatchObject({ code: "23514" });
    expect(refusal.message).toMatch(/opening is not available/);
    expect((await view(s.a)).game).toMatchObject({ state: "choosing_opening", story_count: 0 });
    expect(await s.t.run((ctx) => ctx.db.query("story_chain_stories").collect())).toHaveLength(0);
  });

  test("is only for the partner whose turn it is", async () => {
    const s = await startGame();
    expect(await failure(begin(s.b, s.gameId))).toMatchObject({ code: "42501", message: "not your turn" });
    expect((await view(s.a)).game).toMatchObject({ state: "choosing_opening", story_count: 0 });
  });

  test("is refused once the story has started", async () => {
    const s = await startGame();
    await begin(s.a, s.gameId);
    const refusal = await failure(begin(s.a, s.gameId));
    expect(refusal).toMatchObject({ code: "23514" });
    expect(refusal.message).toMatch(/already started/);
    // Also while the story waits for its title.
    const t = await startGame();
    const reached = await reachTitling(t, t.a);
    expect((await failure(begin(reached.namer, t.gameId))).code).toBe("23514");
    expect((await failure(begin(reached.lastWriter, t.gameId))).code).toBe("42501");
  });

  test("refuses a story id that is taken", async () => {
    const s = await startGame();
    const first = await playStory(s, s.a, "One");
    const refusal = await failure(begin(first.namer, s.gameId, null, first.storyId));
    expect(refusal.code).toBe("23505");
    expect(refusal.message).toMatch(/story_chain_stories_pkey/);
    expect((await view(s.a)).game).toMatchObject({ state: "choosing_opening", story_count: 1 });
  });

  test("refuses a game that does not exist", async () => {
    const s = await startGame();
    expect((await failure(begin(s.a, newUuid()))).code).toBe("42501");
  });

  test("takes uppercase ids from the phone and stores them in lowercase", async () => {
    const s = await startGame();
    const storyId = newUuid();
    const result = await begin(s.a, s.gameId.toUpperCase(), null, storyId.toUpperCase());
    expect(result.story_id).toBe(storyId);
    expect((await storyRow(s.t, storyId)).id).toBe(storyId);
    expect((await failure(begin(s.a, "not-a-uuid"))).code).toBe("22P02");
  });

  test("a retry with the same operation returns the same story, and a changed retry fails", async () => {
    const s = await startGame();
    const args = { ...op(), p_game_id: s.gameId, p_story_id: newUuid(), p_opening_id: null };
    const first = await s.a.as.mutation(api.storyChain.start_story, args);
    expect(await s.a.as.mutation(api.storyChain.start_story, args)).toEqual(first);
    expect(await s.t.run((ctx) => ctx.db.query("story_chain_stories").collect())).toHaveLength(1);
    const changed = await failure(s.a.as.mutation(api.storyChain.start_story, { ...args, p_story_id: newUuid() }));
    expect(changed).toMatchObject({ code: "23505" });
    expect(changed.message).toMatch(/replay hash mismatch/);
  });
});

describe("add_story_line", () => {
  test("a word in both lists is recorded under the couple's language", async () => {
    const s = await startGame({ language: "nb" });
    const shared = STORY_WORDS.nb.find((entry) => STORY_WORDS.en.some((other) => other.id === entry.id))!;
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Linje en.", { dareId: shared.id });
    expect(await usedRows(s.t)).toMatchObject([{ kind: "word", language: "nb", content_id: shared.id }]);
  });

  test("numbers the lines and passes the turn", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    const first = await write(s.a, story_id, "The first line.");
    expect(first).toEqual({ line_id: expect.any(String), number: 1, story_state: "writing" });
    expect((await view(s.b)).game).toMatchObject({
      state: "writing",
      turn_user_id: s.b.userId,
      turn_number: 2,
      current_story_id: story_id,
      version: 3,
    });

    expect(await write(s.b, story_id, "The second line.")).toMatchObject({ number: 2, story_state: "writing" });
    expect((await view(s.a)).game).toMatchObject({ turn_user_id: s.a.userId, turn_number: 3, version: 4 });
    const lines = (await view(s.a)).current_story!.lines;
    expect(lines.map((line) => [line.number, line.author_user_id, line.text])).toEqual([
      [1, s.a.userId, "The first line."],
      [2, s.b.userId, "The second line."],
    ]);
    expect(lines[0].id).toBe(first.line_id);
  });

  test("is only for the partner whose turn it is", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    expect(await failure(write(s.a, story_id, "Line two, too soon."))).toMatchObject({ code: "42501", message: "not your turn" });
    expect((await storyRow(s.t, story_id)).lines).toHaveLength(1);
  });

  test("is refused when the story is not waiting for a line", async () => {
    const s = await startGame();
    const first = await playStory(s, s.a, "One");
    // Finished story, and the namer is on turn to start the next one.
    const finished = await failure(write(first.namer, first.storyId, "Too late."));
    expect(finished).toMatchObject({ code: "23514" });
    expect(finished.message).toMatch(/not waiting for a line/);
    // A story that waits for its title.
    const second = await reachTitling(s, first.namer, { label: "two" });
    expect(await failure(write(second.lastWriter, second.storyId, "One more."))).toMatchObject({ code: "42501" });
    const titling = await failure(write(second.namer, second.storyId, "One more."));
    expect(titling).toMatchObject({ code: "23514" });
    expect(titling.message).toMatch(/not waiting for a line/);
    expect((await storyRow(s.t, second.storyId)).lines).toHaveLength(8);
  });

  test("refuses a line id the story already has", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    const lineId = newUuid();
    await write(s.a, story_id, "Line one.", { lineId });
    const refusal = await failure(write(s.b, story_id, "Line two.", { lineId }));
    expect(refusal).toMatchObject({ code: "23505" });
    expect(refusal.message).toMatch(/story_chain_lines_pkey/);
    expect((await storyRow(s.t, story_id)).lines).toHaveLength(1);
  });

  test("a retry with the same operation returns the first answer, and a changed retry fails", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    const args = {
      ...op(),
      p_story_id: story_id,
      p_line_id: newUuid(),
      p_text: "Line one.",
      p_is_last: false,
      p_dare_word: null,
      p_dare_word_id: null,
    };
    const first = await s.a.as.mutation(api.storyChain.add_story_line, args);
    // The turn has moved on by now, and the retry still gets the stored answer.
    expect(await s.a.as.mutation(api.storyChain.add_story_line, args)).toEqual(first);
    expect((await storyRow(s.t, story_id)).lines).toHaveLength(1);
    expect(await streakEvents(s.t)).toHaveLength(1);
    expect(await pushesOf(s.t, "game_turn_ready")).toHaveLength(1);

    const changed = await failure(s.a.as.mutation(api.storyChain.add_story_line, { ...args, p_text: "A different line." }));
    expect(changed).toMatchObject({ code: "23505" });
    expect(changed.message).toMatch(/replay hash mismatch/);
  });

  describe("the text", () => {
    test("turns runs of spaces and line breaks into one space", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      await write(s.a, story_id, "  The   cat\n\nsat \t down.  \n");
      expect((await storyRow(s.t, story_id)).lines[0].text).toBe("The cat sat down.");
    });

    test("is 2 to 240 characters after that, counted as code points", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      const tooShort = ["", "   ", "a", " é ", "\n\n x \n"];
      for (const text of tooShort) {
        const refusal = await failure(write(s.a, story_id, text));
        expect(refusal).toMatchObject({ code: "23514" });
        expect(refusal.message).toMatch(/2 to 240 characters/);
      }
      for (const text of ["x".repeat(241), "😀".repeat(241), `${"word ".repeat(60)}end`]) {
        expect((await failure(write(s.a, story_id, text))).code).toBe("23514");
      }
      expect((await storyRow(s.t, story_id)).lines).toHaveLength(0);

      // 240 emoji are 480 UTF-16 units but 240 characters.
      await write(s.a, story_id, "😀".repeat(240));
      await write(s.b, story_id, "ok");
      await write(s.a, story_id, "x".repeat(240));
      expect((await storyRow(s.t, story_id)).lines.map((line) => [...line.text].length)).toEqual([240, 2, 240]);
    });
  });

  describe("the dare word", () => {
    test("the next line must use the word, in any case and inside a longer word", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      await write(s.a, story_id, "Lisa åpnet døra.", { dare: "hund" });
      const refusal = await failure(write(s.b, story_id, "Ingen dyr i sikte."));
      expect(refusal).toMatchObject({ code: "23514" });
      expect(refusal.message).toMatch(/must use the dare word/);
      await write(s.b, story_id, "Gårdshunden bjeffet.");

      await write(s.a, story_id, "Så kom en annen.", { dare: "Katt" });
      expect((await failure(write(s.b, story_id, "A cat, not the right word."))).code).toBe("23514");
      await write(s.b, story_id, "Det var EN KATT i vinduet.");
      expect((await storyRow(s.t, story_id)).lines).toHaveLength(4);
    });

    test("matches an accented word typed in a different Unicode form", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      await write(s.a, story_id, "Meet me tomorrow.", { dare: "caf\u00e9" });
      await write(s.b, story_id, "Fine, at the cafe\u0301 then.");
      expect((await storyRow(s.t, story_id)).lines[0].dare_word).toBe("caf\u00e9");
    });

    test("only binds the line right after it", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      await write(s.a, story_id, "Line one.", { dare: "hund" });
      await write(s.b, story_id, "A hund appeared.");
      await write(s.a, story_id, "Line three needs no word.");
      expect((await storyRow(s.t, story_id)).lines).toHaveLength(3);
    });

    test("an own word is stored trimmed and in lowercase, with no list id", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      await write(s.a, story_id, "Line one.", { dare: "  Smørbrød " });
      const line = (await storyRow(s.t, story_id)).lines[0];
      expect(line.dare_word).toBe("smørbrød");
      expect(line.dare_word_id).toBeUndefined();
      expect((await view(s.b)).current_story!.lines[0].dare_word).toBe("smørbrød");
      expect(await usedRows(s.t)).toEqual([]);
    });

    test("an own word must be one word of 2 to 20 letters", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      for (const dare of ["", "  ", "a", "two words", "hund1", "a-b", "hund!", "x".repeat(21)]) {
        const refusal = await failure(write(s.a, story_id, "Line one.", { dare }));
        expect(refusal).toMatchObject({ code: "23514" });
        expect(refusal.message).toMatch(/one word of 2 to 20 letters/);
      }
      expect((await storyRow(s.t, story_id)).lines).toHaveLength(0);
      await write(s.a, story_id, "Line one.", { dare: "x".repeat(20) });
      expect((await storyRow(s.t, story_id)).lines[0].dare_word).toBe("x".repeat(20));
    });

    test("a list word takes its text from the list and is marked used", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      const word = (await view(s.a)).word_choices![0];
      await write(s.a, story_id, "Line one.", { dareId: word.word_id, dare: "ignored" });
      const line = (await storyRow(s.t, story_id)).lines[0];
      expect(line).toMatchObject({ dare_word: word.word, dare_word_id: word.word_id });
      expect((await view(s.b)).current_story!.lines[0].dare_word).toBe(word.word);
      expect(await usedRows(s.t)).toMatchObject([{ kind: "word", language: "en", content_id: word.word_id }]);

      expect((await failure(write(s.b, story_id, "Zzz qqq."))).code).toBe("23514");
      await write(s.b, story_id, `Look, a ${word.word}.`);
    });

    test("a list word of the other language is taken, and an unknown id is refused", async () => {
      const s = await startGame({ language: "en" });
      const { story_id } = await begin(s.a, s.gameId);
      const refusal = await failure(write(s.a, story_id, "Line one.", { dareId: "no_such_word" }));
      expect(refusal).toMatchObject({ code: "23514" });
      expect(refusal.message).toMatch(/dare word is not available/);
      expect((await storyRow(s.t, story_id)).lines).toHaveLength(0);

      const norwegian = STORY_WORDS.nb[0];
      await write(s.a, story_id, "Line one.", { dareId: norwegian.id });
      expect((await storyRow(s.t, story_id)).lines[0]).toMatchObject({ dare_word: norwegian.text, dare_word_id: norwegian.id });
      expect(await usedRows(s.t)).toMatchObject([{ kind: "word", language: "nb", content_id: norwegian.id }]);
    });

    test("a refused line leaves the story, the turn, the streak, and the pushes alone", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      await write(s.a, story_id, "Line one.", { dare: "hund" });
      const before = await gameRow(s.t, s.gameId);
      const pushesBefore = (await outbox(s.t)).length;
      expect((await failure(write(s.b, story_id, "No dog at all."))).code).toBe("23514");
      expect(await gameRow(s.t, s.gameId)).toEqual(before);
      expect((await storyRow(s.t, story_id)).lines).toHaveLength(1);
      expect(await streakEvents(s.t)).toHaveLength(1);
      expect(await outbox(s.t)).toHaveLength(pushesBefore);
    });
  });

  describe("ending the story", () => {
    test("a story can end from line 8 and not before", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      for (let number = 1; number <= 6; number += 1) await write(number % 2 === 1 ? s.a : s.b, story_id, `Line ${number}.`);
      const early = await failure(write(s.a, story_id, "Line 7, the end.", { last: true }));
      expect(early).toMatchObject({ code: "23514" });
      expect(early.message).toMatch(/can end from line 8/);
      expect((await storyRow(s.t, story_id)).state).toBe("writing");

      await write(s.a, story_id, "Line 7.");
      expect(await write(s.b, story_id, "Line 8, the end.", { last: true })).toMatchObject({ number: 8, story_state: "titling" });
    });

    test("the last line puts the story in titling and passes the turn to the namer", async () => {
      const s = await startGame();
      const reached = await reachTitling(s, s.a);
      expect(reached).toMatchObject({ lastWriter: s.b, namer: s.a });
      const story = await storyRow(s.t, reached.storyId);
      expect(story).toMatchObject({ state: "titling", last_line_user_id: s.b.userId });
      expect(story.lines).toHaveLength(8);
      expect(story.title).toBeUndefined();
      expect(story.seen_by).toEqual([]);

      const data = await view(s.a);
      expect(data.game).toMatchObject({ state: "titling", turn_user_id: s.a.userId, current_story_id: reached.storyId, finished_count: 0 });
      expect(data.current_story).toMatchObject({ state: "titling", last_line_user_id: s.b.userId, title: null, finished_at: null });
    });

    test("an odd last line makes the starter the last writer, so the partner names the story", async () => {
      const s = await startGame();
      const reached = await reachTitling(s, s.a, { lines: 9 });
      expect(reached).toMatchObject({ lastWriter: s.a, namer: s.b });
      expect((await view(s.b)).game).toMatchObject({ state: "titling", turn_user_id: s.b.userId });
    });

    test("the last line still has to use the word it was dared with, and cannot dare", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      for (let number = 1; number <= 6; number += 1) await write(number % 2 === 1 ? s.a : s.b, story_id, `Line ${number}.`);
      await write(s.a, story_id, "Line 7.", { dare: "kake" });
      expect((await failure(write(s.b, story_id, "Line 8, the end.", { last: true }))).message).toMatch(/dare word/);

      const wordId = STORY_WORDS.en[0].id;
      for (const dare of [{ dare: "slutt" }, { dareId: wordId }]) {
        const refusal = await failure(write(s.b, story_id, "Line 8, kake, the end.", { last: true, ...dare }));
        expect(refusal).toMatchObject({ code: "23514" });
        expect(refusal.message).toMatch(/last line can't give a word/);
      }
      expect((await storyRow(s.t, story_id)).lines).toHaveLength(7);

      await write(s.b, story_id, "Line 8, kake, the end.", { last: true });
      expect((await storyRow(s.t, story_id)).state).toBe("titling");
      expect(await usedRows(s.t)).toEqual([]);
    });

    test("line 20 ends the story without being asked, and offers no words before it", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      for (let number = 1; number <= 18; number += 1) await write(number % 2 === 1 ? s.a : s.b, story_id, `Line ${number}.`);
      // Next is line 19, written by a: words are still offered.
      expect((await view(s.a)).word_choices).toHaveLength(3);
      await write(s.a, story_id, "Line 19.");
      // Next is line 20: the last one, so there is no word to give.
      expect((await view(s.b)).word_choices).toBeNull();
      expect((await view(s.a)).word_choices).toBeNull();
      expect((await failure(write(s.b, story_id, "Line 20.", { dare: "never" }))).message).toMatch(/last line can't give a word/);

      expect(await write(s.b, story_id, "Line 20.")).toMatchObject({ number: 20, story_state: "titling" });
      expect(await storyRow(s.t, story_id)).toMatchObject({ state: "titling", last_line_user_id: s.b.userId });
      expect((await view(s.a)).game).toMatchObject({ state: "titling", turn_user_id: s.a.userId });
      // Nothing can be added after line 20.
      expect((await failure(write(s.a, story_id, "Line 21."))).code).toBe("23514");
    });
  });

  describe("the streak", () => {
    test("counts each line once as a game turn, and naming adds nothing", async () => {
      const s = await startGame();
      const { story_id } = await begin(s.a, s.gameId);
      expect(await streakEvents(s.t)).toHaveLength(0);
      const first = await write(s.a, story_id, "Line one.");
      const second = await write(s.b, story_id, "Line two.");
      const third = await write(s.a, story_id, "Line three.");

      const events = await streakEvents(s.t);
      expect(events.map((event) => event.dedupe_key).sort()).toEqual(
        [first, second, third].map((line) => `game_turn_completed:${line.line_id}`).sort(),
      );
      const byLine = new Map(events.map((event) => [event.dedupe_key, event]));
      expect(byLine.get(`game_turn_completed:${first.line_id}`)).toMatchObject({
        user_id: s.a.userId,
        couple_id: s.coupleId,
        metadata: { game_id: s.gameId, story_id, line_id: first.line_id },
      });
      expect(byLine.get(`game_turn_completed:${second.line_id}`)?.user_id).toBe(s.b.userId);

      // Finish the story and name it: eight lines, eight events.
      for (let number = 4; number <= 7; number += 1) await write(number % 2 === 1 ? s.a : s.b, story_id, `Line ${number}.`);
      await write(s.b, story_id, "Line 8.", { last: true });
      expect(await streakEvents(s.t)).toHaveLength(8);
      await name(s.a, story_id, "Named");
      expect(await streakEvents(s.t)).toHaveLength(8);
    });
  });
});

describe("name_story", () => {
  test("only the partner who did not write the last line can name the story", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    expect(await failure(name(reached.lastWriter, reached.storyId, "Mine"))).toMatchObject({ code: "42501", message: "not your turn" });
    expect((await storyRow(s.t, reached.storyId)).state).toBe("titling");
    await name(reached.namer, reached.storyId, "Theirs");
    expect((await storyRow(s.t, reached.storyId)).state).toBe("finished");
  });

  test("is refused while the story is still being written", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    const refusal = await failure(name(s.b, story_id, "Too soon"));
    expect(refusal).toMatchObject({ code: "23514" });
    expect(refusal.message).toMatch(/waiting for a title/);
  });

  test("finishes the story and gives the namer the next story", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    const before = await gameRow(s.t, s.gameId);
    tick(60);
    expect(await name(reached.namer, reached.storyId, "The Moonlit Heist")).toEqual({ story_id: reached.storyId, title: "The Moonlit Heist" });

    const story = await storyRow(s.t, reached.storyId);
    expect(story).toMatchObject({
      state: "finished",
      title: "The Moonlit Heist",
      titled_by_user_id: reached.namer.userId,
      last_line_user_id: reached.lastWriter.userId,
      finished_at: new Date().toISOString(),
      seen_by: [reached.namer.userId],
    });
    const game = await gameRow(s.t, s.gameId);
    expect(game).toMatchObject({
      state: "choosing_opening",
      turn_user_id: reached.namer.userId,
      turn_number: before.turn_number + 1,
      finished_count: 1,
      story_count: 1,
      version: before.version + 1,
      turn_started_at: new Date().toISOString(),
    });

    const forNamer = await view(reached.namer);
    expect(forNamer.opening_choices).toHaveLength(3);
    expect(forNamer.current_story).toMatchObject({ state: "finished", title: "The Moonlit Heist", seen_by_me: true, starred_by_me: false });
    const forWriter = await view(reached.lastWriter);
    expect(forWriter.opening_choices).toBeNull();
    expect(forWriter.current_story).toMatchObject({ seen_by_me: false });
  });

  test("a full second story can start and finish after the first", async () => {
    const s = await startGame();
    const first = await playStory(s, s.a, "One");
    const second = await playStory(s, first.namer, "Two", { lines: 9 });
    const data = await view(s.a);
    expect(data.game).toMatchObject({ state: "choosing_opening", story_count: 2, finished_count: 2, turn_user_id: second.namer.userId });
    expect(data.current_story).toMatchObject({ id: second.storyId, story_number: 2, state: "finished", title: "Two" });
    expect(data.current_story!.lines).toHaveLength(9);
    expect(data.previous_story).toMatchObject({ id: first.storyId, story_number: 1, state: "finished", title: "One" });
    expect((await storyRow(s.t, first.storyId)).lines).toHaveLength(8);
  });

  test("the title is 1 to 40 characters counted as code points, and runs of spaces become one", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    for (const title of ["", "   ", "\n", "x".repeat(41), "😀".repeat(41)]) {
      const refusal = await failure(name(reached.namer, reached.storyId, title));
      expect(refusal).toMatchObject({ code: "23514" });
      expect(refusal.message).toMatch(/1 to 40 characters/);
    }
    expect((await storyRow(s.t, reached.storyId)).state).toBe("titling");
    await name(reached.namer, reached.storyId, "😀".repeat(40));
    expect((await storyRow(s.t, reached.storyId)).title).toBe("😀".repeat(40));

    const second = await reachTitling(s, reached.namer);
    expect(await name(second.namer, second.storyId, "  The   Big\n Heist ")).toMatchObject({ title: "The Big Heist" });
    expect((await storyRow(s.t, second.storyId)).title).toBe("The Big Heist");
  });

  test("a retry with the same operation returns the first answer, and a second name with a new operation fails", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    const args = { ...op(), p_story_id: reached.storyId, p_title: "Once" };
    const first = await reached.namer.as.mutation(api.storyChain.name_story, args);
    expect(await reached.namer.as.mutation(api.storyChain.name_story, args)).toEqual(first);
    expect((await gameRow(s.t, s.gameId)).finished_count).toBe(1);
    expect((await failure(reached.namer.as.mutation(api.storyChain.name_story, { ...args, p_title: "Twice" }))).code).toBe("23505");
    const again = await failure(name(reached.namer, reached.storyId, "Twice"));
    expect(again).toMatchObject({ code: "23514" });
    expect((await storyRow(s.t, reached.storyId)).title).toBe("Once");
  });
});

describe("mark_story_seen", () => {
  test("a new seen mark moves the game version, and a repeated one does not", async () => {
    const s = await startGame();
    const played = await playStory(s, s.a, "Seen once");
    const before = (await gameRow(s.t, s.gameId)).version;
    await seen(played.lastWriter, played.storyId);
    expect((await gameRow(s.t, s.gameId)).version).toBe(before + 1);
    await seen(played.lastWriter, played.storyId);
    expect((await gameRow(s.t, s.gameId)).version).toBe(before + 1);
  });

  test("keeps each partner's mark on the story, and marking twice changes nothing", async () => {
    const s = await startGame();
    const reached = await playStory(s, s.a, "One");
    const reader = reached.lastWriter;
    expect((await view(reader)).current_story!.seen_by_me).toBe(false);
    expect(await seen(reader, reached.storyId)).toEqual({ story_id: reached.storyId });
    expect((await view(reader)).current_story!.seen_by_me).toBe(true);
    expect((await storyRow(s.t, reached.storyId)).seen_by.sort()).toEqual([s.a.userId, s.b.userId].sort());

    const before = await storyRow(s.t, reached.storyId);
    tick(5);
    await seen(reader, reached.storyId);
    await seen(reached.namer, reached.storyId);
    expect(await storyRow(s.t, reached.storyId)).toEqual(before);
  });

  test("is refused for a story that is not finished", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    const refusal = await failure(seen(s.b, story_id));
    expect(refusal).toMatchObject({ code: "23514" });
    expect(refusal.message).toMatch(/not finished/);
    await write(s.a, story_id, "Line one.");
    expect((await failure(seen(s.a, story_id))).code).toBe("23514");
    expect((await storyRow(s.t, story_id)).seen_by).toEqual([]);
  });
});

describe("set_story_star", () => {
  test("a changed star moves the game version, and setting the same value does not", async () => {
    const s = await startGame();
    const played = await playStory(s, s.a, "Starred once");
    const starIt = (starred: boolean) =>
      s.a.as.mutation(api.storyChain.set_story_star, { p_story_id: played.storyId, p_starred: starred });
    const before = (await gameRow(s.t, s.gameId)).version;
    await starIt(true);
    await starIt(true);
    expect((await gameRow(s.t, s.gameId)).version).toBe(before + 1);
    await starIt(false);
    expect((await gameRow(s.t, s.gameId)).version).toBe(before + 2);
  });

  test("stars and unstars a finished story, and repeating a call changes nothing", async () => {
    const s = await startGame();
    const reached = await playStory(s, s.a, "One");
    const rows = () => s.t.run((ctx) => ctx.db.query("story_chain_stars").collect());
    expect(await star(s.a, reached.storyId, true)).toEqual({ story_id: reached.storyId, starred: true });
    expect(await star(s.a, reached.storyId, true)).toEqual({ story_id: reached.storyId, starred: true });
    expect(await rows()).toMatchObject([{ story_id: reached.storyId, user_id: s.a.userId, couple_id: s.coupleId, story_number: 1 }]);
    expect((await view(s.a)).current_story!.starred_by_me).toBe(true);

    expect(await star(s.a, reached.storyId, false)).toEqual({ story_id: reached.storyId, starred: false });
    expect(await star(s.a, reached.storyId, false)).toEqual({ story_id: reached.storyId, starred: false });
    expect(await rows()).toEqual([]);
    expect((await view(s.a)).current_story!.starred_by_me).toBe(false);
  });

  test("is refused for a story that is not finished", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    const refusal = await failure(star(s.a, story_id, true));
    expect(refusal).toMatchObject({ code: "23514" });
    expect(refusal.message).toMatch(/only a finished story/);
    // A story that waits for its title is not finished either.
    const titling = await startGame();
    const reached = await reachTitling(titling, titling.a);
    expect((await failure(star(reached.namer, reached.storyId, true))).code).toBe("23514");
    expect(await titling.t.run((ctx) => ctx.db.query("story_chain_stars").collect())).toEqual([]);
  });

  test("a star is private: the partner never sees it", async () => {
    const s = await startGame();
    const reached = await playStory(s, s.a, "One");
    await star(s.a, reached.storyId, true);

    expect((await view(s.a)).current_story!.starred_by_me).toBe(true);
    expect((await view(s.b)).current_story!.starred_by_me).toBe(false);
    expect((await s.a.as.query(api.storyChain.get_story_chain_story, { p_story_id: reached.storyId }))!.starred_by_me).toBe(true);
    expect((await s.b.as.query(api.storyChain.get_story_chain_story, { p_story_id: reached.storyId }))!.starred_by_me).toBe(false);
    expect((await history(s.a)).stories[0].starred_by_me).toBe(true);
    expect((await history(s.b)).stories[0].starred_by_me).toBe(false);
    expect((await history(s.b, { starred: true })).stories).toEqual([]);

    // The partner's own star is separate, and unstarring it leaves the first alone.
    await star(s.b, reached.storyId, true);
    await star(s.b, reached.storyId, false);
    expect((await history(s.a, { starred: true })).stories).toHaveLength(1);
  });
});

describe("get_story_chain_story", () => {
  test("returns the story as the app reads it, and null for an id nobody has", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId, STORY_OPENINGS.en[0].id);
    const line = await write(s.a, story_id, "The first line.", { dare: "hund" });
    const story = await s.b.as.query(api.storyChain.get_story_chain_story, { p_story_id: story_id.toUpperCase() });
    expect(story).toEqual({
      id: story_id,
      story_number: 1,
      starter_user_id: s.a.userId,
      opening_id: STORY_OPENINGS.en[0].id,
      opening_text: STORY_OPENINGS.en[0].text,
      state: "writing",
      lines: [
        { id: line.line_id, number: 1, author_user_id: s.a.userId, text: "The first line.", dare_word: "hund", created_at: new Date().toISOString() },
      ],
      last_line_user_id: null,
      title: null,
      titled_by_user_id: null,
      finished_at: null,
      seen_by_me: false,
      starred_by_me: false,
      created_at: expect.any(String),
      updated_at: expect.any(String),
    });
    expect(await s.b.as.query(api.storyChain.get_story_chain_story, { p_story_id: newUuid() })).toBeNull();
  });
});

describe("get_story_chain_history", () => {
  test("lists finished stories newest first, pages by story number, and leaves out the story being written", async () => {
    const s = await startGame();
    const specs: { title: string; lines: number; openingId?: string }[] = [
      { title: "First", lines: 8, openingId: STORY_OPENINGS.en[0].id },
      { title: "Second", lines: 9 },
      { title: "Third", lines: 8 },
      { title: "Fourth", lines: 10 },
    ];
    let starter = s.a;
    const stories: { storyId: string; title: string }[] = [];
    for (const spec of specs) {
      tick(60);
      const done = await playStory(s, starter, spec.title, spec);
      stories.push({ storyId: done.storyId, title: spec.title });
      starter = done.namer;
    }
    const inProgress = await begin(starter, s.gameId);
    await write(starter, inProgress.story_id, "Still going.");

    const all = await history(s.b);
    expect(all.next_before_story_number).toBeNull();
    expect(all.stories.map((item) => [item.story_number, item.title, item.line_count])).toEqual([
      [4, "Fourth", 10],
      [3, "Third", 8],
      [2, "Second", 9],
      [1, "First", 8],
    ]);
    expect(all.stories[3]).toEqual({
      id: stories[0].storyId,
      story_number: 1,
      title: "First",
      first_line: STORY_OPENINGS.en[0].text,
      line_count: 8,
      finished_at: expect.any(String),
      starred_by_me: false,
    });
    expect(all.stories[2].first_line).toBe("Line 1 of Second.");
    expect(all.stories.map((item) => item.finished_at)).toEqual([...all.stories.map((item) => item.finished_at)].sort().reverse());

    const page1 = await history(s.b, { limit: 3 });
    expect(page1.stories.map((item) => item.story_number)).toEqual([4, 3, 2]);
    expect(page1.next_before_story_number).toBe(2);
    const page2 = await history(s.b, { limit: 3, before: page1.next_before_story_number });
    expect(page2.stories.map((item) => item.story_number)).toEqual([1]);
    expect(page2.next_before_story_number).toBeNull();

    // A page that ends exactly at the oldest story has no next page.
    const two = await history(s.b, { limit: 2 });
    expect(two.stories.map((item) => item.story_number)).toEqual([4, 3]);
    expect(two.next_before_story_number).toBe(3);
    const rest = await history(s.b, { limit: 2, before: 3 });
    expect(rest.stories.map((item) => item.story_number)).toEqual([2, 1]);
    expect(rest.next_before_story_number).toBeNull();

    // The limit is at least 1 and a whole number.
    expect((await history(s.b, { limit: 0 })).stories).toHaveLength(1);
    expect((await history(s.b, { limit: -4 })).stories).toHaveLength(1);
    expect((await history(s.b, { limit: 2.9 })).stories).toHaveLength(2);
    expect((await history(s.b, { limit: 100000 })).stories).toHaveLength(4);
    // NaN and infinity are refused: a NaN limit would never fill the page.
    for (const limit of [Number.NaN, Number.POSITIVE_INFINITY]) {
      expect((await failure(history(s.b, { limit }))).code).toBe("23514");
    }

    // Stars are per partner, and the starred list pages the same way.
    await star(s.a, stories[3].storyId, true);
    await star(s.a, stories[1].storyId, true);
    await star(s.b, stories[2].storyId, true);
    await star(s.b, stories[1].storyId, true);
    expect((await history(s.a)).stories.map((item) => item.starred_by_me)).toEqual([true, false, true, false]);
    expect((await history(s.b)).stories.map((item) => item.starred_by_me)).toEqual([false, true, true, false]);
    expect((await history(s.a, { starred: true })).stories.map((item) => item.story_number)).toEqual([4, 2]);
    expect((await history(s.b, { starred: true })).stories.map((item) => item.story_number)).toEqual([3, 2]);

    const starred1 = await history(s.a, { starred: true, limit: 1 });
    expect(starred1.stories.map((item) => item.story_number)).toEqual([4]);
    expect(starred1.next_before_story_number).toBe(4);
    const starred2 = await history(s.a, { starred: true, limit: 1, before: 4 });
    expect(starred2.stories.map((item) => item.story_number)).toEqual([2]);
    expect(starred2.next_before_story_number).toBeNull();
  });

  test("has nothing before a story is finished", async () => {
    const s = await startGame();
    expect(await history(s.a)).toEqual({ stories: [], next_before_story_number: null });
    expect(await history(s.a, { starred: true })).toEqual({ stories: [], next_before_story_number: null });
    await reachTitling(s, s.a);
    expect((await history(s.a)).stories).toEqual([]);
  });
});

describe("pushes", () => {
  test("a line queues a lock-screen-safe turn push for the partner with the deep link", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    expect(await outbox(s.t)).toHaveLength(0);
    const { line_id } = await write(s.a, story_id, "Zeppelins drifted over the pineapple harbour.", { dare: "marzipan" });

    const rows = await pushesOf(s.t, "game_turn_ready");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      apns_push_type: "alert",
      title: "Your turn in Story Chain",
      body: "Open Paeonia to read the newest line.",
      payload: {
        type: "game_turn_ready",
        game_kind: "story_chain",
        couple_id: s.coupleId,
        game_id: s.gameId,
        round_id: line_id,
        actor_user_id: s.a.userId,
        route: "games",
        deeplink: "paeonia://games/story-chain",
      },
    });
    expect(rows[0].payload).not.toHaveProperty("step");
    const text = JSON.stringify(rows[0]);
    for (const secret of ["Zeppelin", "pineapple", "marzipan"]) expect(text).not.toContain(secret);
  });

  test("the last line queues the last-line copy, and naming queues the story-named copy", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    const last = (await pushesOf(s.t, "game_turn_ready")).filter((row) => (row.payload as { step?: string }).step === "last_line");
    expect(last).toHaveLength(1);
    expect(last[0]).toMatchObject({
      recipient_user_id: s.a.userId,
      title: "Second Partner wrote the last line",
      body: "Open Paeonia to give your story a title.",
      payload: { type: "game_turn_ready", step: "last_line", round_id: reached.lastLineId, actor_user_id: s.b.userId, deeplink: "paeonia://games/story-chain" },
    });
    // The seven earlier lines are plain turn pushes.
    expect((await pushesOf(s.t, "game_turn_ready")).filter((row) => row.title === "Your turn in Story Chain")).toHaveLength(7);

    await name(reached.namer, reached.storyId, "The Moonlit Heist");
    const named = await pushesOf(s.t, "game_result");
    expect(named).toHaveLength(1);
    expect(named[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      apns_push_type: "alert",
      title: "First Partner named your story",
      body: "Open Paeonia to read it.",
      payload: {
        type: "game_result",
        game_kind: "story_chain",
        couple_id: s.coupleId,
        game_id: s.gameId,
        round_id: reached.storyId,
        actor_user_id: s.a.userId,
        route: "games",
        deeplink: "paeonia://games/story-chain",
      },
    });
    const text = JSON.stringify(await outbox(s.t));
    expect(text).not.toContain("Moonlit");
  });

  test("the copy follows the recipient's language", async () => {
    const s = await startGame({ language: "nb", locales: { a: "nb-NO", b: "nb-NO" } });
    const reached = await reachTitling(s, s.a);
    const turn = (await pushesOf(s.t, "game_turn_ready")).filter((row) => (row.payload as { step?: string }).step === undefined);
    expect(turn[0]).toMatchObject({ title: "Din tur i Skrivestafett", body: "Åpne Paeonia for å lese den nyeste linjen." });
    const last = (await pushesOf(s.t, "game_turn_ready")).find((row) => (row.payload as { step?: string }).step === "last_line");
    expect(last).toMatchObject({ title: "Second Partner skrev den siste linjen", body: "Åpne Paeonia for å gi historien en tittel." });

    await name(reached.namer, reached.storyId, "Tyveriet");
    expect((await pushesOf(s.t, "game_result"))[0]).toMatchObject({
      title: "First Partner ga historien deres en tittel",
      body: "Åpne Paeonia for å lese den.",
    });
  });

  test("an English phone gets English copy next to a Norwegian partner", async () => {
    const s = await startGame({ locales: { a: "nb-NO", b: "en-US" } });
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    await write(s.b, story_id, "Line two.");
    const byRecipient = new Map((await pushesOf(s.t, "game_turn_ready")).map((row) => [row.recipient_user_id, row]));
    expect(byRecipient.get(s.b.userId)).toMatchObject({ title: "Your turn in Story Chain" });
    expect(byRecipient.get(s.a.userId)).toMatchObject({ title: "Din tur i Skrivestafett" });
  });

  test("a partner who has the game open gets no push for a line, the last line, or the name", async () => {
    const s = await startGame();
    for (const user of [s.a, s.b]) await user.as.mutation(api.games.set_game_presence, { p_kind: "story_chain", p_present: true });
    const reached = await playStory(s, s.a, "Quiet");
    expect(await outbox(s.t)).toHaveLength(0);
    // The line was still written.
    expect((await storyRow(s.t, reached.storyId)).state).toBe("finished");
  });

  test("an old presence, or presence in another game, does not silence the push", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    expect(await pushesOf(s.t, "game_turn_ready")).toHaveLength(1);

    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "story_chain", p_present: true });
    tick(61);
    await write(s.b, story_id, "Line two.");
    expect(await pushesOf(s.t, "game_turn_ready")).toHaveLength(2);

    // Closing the screen removes the presence at once.
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "story_chain", p_present: true });
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "story_chain", p_present: false });
    await write(s.a, story_id, "Line three.");
    expect(await pushesOf(s.t, "game_turn_ready")).toHaveLength(3);
  });

  test("the Games switch turns the pushes off", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    expect(await outbox(s.t)).toHaveLength(0);
  });
});

describe("push drain", () => {
  const claim = (s: Setup) => s.t.mutation(internal.pushQueue.claim_notification_batch, {});
  const errorsOf = async (s: Setup, recipient: TestUser, kind: string) =>
    (await outbox(s.t)).filter((row) => row.kind === kind && row.recipient_user_id === recipient.userId).map((row) => row.last_error ?? null);

  test("keeps a turn push that still waits and drops one once the turn moved on", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    await write(s.b, story_id, "Line two.");
    const claimed = await claim(s);
    expect(claimed).toHaveLength(1);
    expect(claimed[0].payload).toMatchObject({ type: "game_turn_ready", actor_user_id: s.b.userId });
    expect(claimed[0].title).toBe("Your turn in Story Chain");
    expect(await errorsOf(s, s.b, "game_turn_ready")).toEqual(["notification is out of date"]);
    expect(await errorsOf(s, s.a, "game_turn_ready")).toEqual([null]);
  });

  test("a turn push that waited while the turn went around is out of date", async () => {
    const s = await startGame();
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    await write(s.b, story_id, "Line two.");
    await write(s.a, story_id, "Line three.");
    // The turn is the second partner's again, but only the push for line three still names it.
    await claim(s);
    expect(await errorsOf(s, s.b, "game_turn_ready")).toEqual(["notification is out of date", null]);
  });

  test("keeps the last-line push while the title waits, and drops every earlier line push", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    const claimed = await claim(s);
    expect(claimed).toHaveLength(1);
    expect(claimed[0].payload).toMatchObject({ type: "game_turn_ready", step: "last_line", round_id: reached.lastLineId });
  });

  test("drops the last-line push once the story is named, and sends the named push", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    await name(reached.namer, reached.storyId, "Named");
    const claimed = await claim(s);
    expect(claimed.map((row) => (row.payload as { type: string }).type)).toEqual(["game_result"]);
    expect(claimed[0].title).toBe("First Partner named your story");
    expect(await errorsOf(s, s.a, "game_turn_ready")).toEqual(Array(4).fill("notification is out of date"));
    expect(await errorsOf(s, s.b, "game_result")).toEqual([null]);
  });

  test("drops the named push once the story was seen", async () => {
    const s = await startGame();
    const reached = await playStory(s, s.a, "Seen");
    await seen(reached.lastWriter, reached.storyId);
    expect(await claim(s)).toEqual([]);
    expect(await errorsOf(s, reached.lastWriter, "game_result")).toEqual(["notification is out of date"]);
  });

  test("drops the line pushes of an old story once a new one started, and keeps the unread named push", async () => {
    const s = await startGame();
    const first = await playStory(s, s.a, "Old");
    await begin(first.namer, s.gameId);
    const claimed = await claim(s);
    expect(claimed.map((row) => (row.payload as { type: string }).type)).toEqual(["game_result"]);
  });

  test("drops every couple push queued before the relationship ended", async () => {
    const s = await startGame();
    const reached = await playStory(s, s.a, "Gone");
    expect((await outbox(s.t)).length).toBeGreaterThan(0);
    await endCouple(s.t, s.coupleId, reached.namer.userId);
    expect(await claim(s)).toEqual([]);
    for (const row of await outbox(s.t)) {
      expect(row).toMatchObject({ last_error: "notification target is no longer eligible" });
      expect(row.failed_at).toBeDefined();
    }
  });
});

describe("turn reminder", () => {
  const run = (s: Setup) => s.t.mutation(internal.games.send_due_game_turn_reminders, {});
  const reminders = (s: Setup) => pushesOf(s.t, "game_turn_reminder");

  test("goes out once after 72 hours to the partner on turn, and again only for a new turn", async () => {
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
      title: "Your turn in Story Chain",
      body: "Open Paeonia to take your turn.",
      payload: {
        type: "game_turn_reminder",
        game_kind: "story_chain",
        game_id: s.gameId,
        actor_user_id: s.b.userId,
        deeplink: "paeonia://games/story-chain",
      },
    });
    expect((await gameRow(s.t, s.gameId)).turn_reminder_sent_at).toBeDefined();

    // a finally writes. The turn moves to b and b's wait starts now.
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    expect((await gameRow(s.t, s.gameId)).turn_reminder_sent_at).toBeUndefined();
    tick(71 * HOUR);
    expect(await run(s)).toBe(0);
    tick(2 * HOUR);
    expect(await run(s)).toBe(1);
    expect(await run(s)).toBe(0);
    rows = await reminders(s);
    expect(rows.map((row) => row.recipient_user_id)).toEqual([s.a.userId, s.b.userId]);
  });

  test("also reminds the partner who has to name the story, and a new turn after that gets its own", async () => {
    const s = await startGame();
    const reached = await reachTitling(s, s.a);
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);
    expect((await reminders(s)).map((row) => row.recipient_user_id)).toEqual([reached.namer.userId]);
    await name(reached.namer, reached.storyId, "Named");
    expect((await gameRow(s.t, s.gameId)).turn_reminder_sent_at).toBeUndefined();
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);
    expect(await run(s)).toBe(0);
    expect(await reminders(s)).toHaveLength(2);
  });

  test("starting a story keeps the turn and the reminder that was already sent", async () => {
    const s = await startGame();
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);
    await begin(s.a, s.gameId);
    tick(100 * HOUR);
    expect(await run(s)).toBe(0);
    expect(await reminders(s)).toHaveLength(1);
  });

  test("respects the Games switch and a couple that is no longer active", async () => {
    const s = await startGame();
    await s.a.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    tick(80 * HOUR);
    expect(await run(s)).toBe(0);
    expect(await outbox(s.t)).toHaveLength(0);

    const other = await startGame();
    await endCouple(other.t, other.coupleId, other.a.userId);
    tick(80 * HOUR);
    expect(await other.t.mutation(internal.games.send_due_game_turn_reminders, {})).toBe(0);
  });

  test("the drain still sends a reminder while the turn waits and drops it once the turn moved on", async () => {
    const waiting = await startGame();
    tick(73 * HOUR);
    expect(await run(waiting)).toBe(1);
    const claimed = await waiting.t.mutation(internal.pushQueue.claim_notification_batch, {});
    expect(claimed.map((row) => (row.payload as { type: string }).type)).toEqual(["game_turn_reminder"]);

    const moved = await startGame();
    tick(73 * HOUR);
    expect(await run(moved)).toBe(1);
    const { story_id } = await begin(moved.a, moved.gameId);
    await write(moved.a, story_id, "Line one.");
    const kinds = (await moved.t.mutation(internal.pushQueue.claim_notification_batch, {})).map((row) => (row.payload as { type: string }).type);
    expect(kinds).toEqual(["game_turn_ready"]);
    expect((await reminders(moved)).map((row) => row.last_error ?? null)).toEqual(["notification is out of date"]);
  });

  test("the drain drops a reminder for an earlier turn even when the turn came back to the same partner", async () => {
    const s = await startGame();
    tick(73 * HOUR);
    expect(await run(s)).toBe(1);
    const { story_id } = await begin(s.a, s.gameId);
    await write(s.a, story_id, "Line one.");
    await write(s.b, story_id, "Line two.");
    // It is a's turn again, but a new turn began, so the old reminder has no reason to go out.
    const claimed = await s.t.mutation(internal.pushQueue.claim_notification_batch, {});
    expect(claimed.map((row) => (row.payload as { type: string }).type)).toEqual(["game_turn_ready"]);
    expect(claimed[0].payload).toMatchObject({ actor_user_id: s.b.userId });
    expect((await reminders(s)).map((row) => row.last_error ?? null)).toEqual(["notification is out of date"]);
  });
});

describe("relationship end", () => {
  const tables = ["story_chain_games", "story_chain_stories", "story_chain_stars", "story_chain_used"] as const;
  const count = (t: TestConvex, coupleId: string) =>
    t.run(async (ctx) => {
      const result: Record<string, number> = {};
      for (const table of tables) {
        result[table] = (await ctx.db.query(table).collect()).filter((row) => row.couple_id === coupleId).length;
      }
      return result;
    });

  /** Two finished-or-running stories with a star each and used openings and words. */
  async function fill(s: Setup) {
    const first = await playStory(s, s.a, "One", { openingId: STORY_OPENINGS.en[2].id });
    await star(s.a, first.storyId, true);
    await star(s.b, first.storyId, true);
    const second = await begin(first.namer, s.gameId, STORY_OPENINGS.en[3].id);
    await write(first.namer, second.story_id, "Line one.", { dareId: STORY_WORDS.en[4].id });
  }

  test("cleanup deletes every Story Chain row of the couple and no other couple's", async () => {
    const s = await startGame();
    await fill(s);
    const other = await startGameIn(s.t);
    await fill(other);
    const otherBefore = await count(s.t, other.coupleId);
    const mine = await count(s.t, s.coupleId);
    expect(mine).toEqual({ story_chain_games: 1, story_chain_stories: 2, story_chain_stars: 2, story_chain_used: 3 });
    expect(otherBefore).toEqual(mine);

    await s.a.as.mutation(api.relationship.leave_relationship, op());
    // The rows stay through the retention window.
    expect(await count(s.t, s.coupleId)).toEqual(mine);
    await s.t.mutation(internal.relationship.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" });
    expect(await count(s.t, s.coupleId)).toEqual({ story_chain_games: 0, story_chain_stories: 0, story_chain_stars: 0, story_chain_used: 0 });
    expect(await count(s.t, other.coupleId)).toEqual(otherBefore);
  });

  test("the delete counts every row it removes", async () => {
    const s = await startGame();
    await fill(s);
    // 1 settings row, 1 game, 2 stories, 2 stars, and 2 openings and 1 word marked used.
    expect(await s.t.run((ctx) => deleteCoupleGameRows(ctx, s.coupleId))).toBe(1 + 1 + 2 + 2 + 3);
    expect(await count(s.t, s.coupleId)).toEqual({ story_chain_games: 0, story_chain_stories: 0, story_chain_stars: 0, story_chain_used: 0 });
  });

  test("a purge without an earlier cleanup still removes the rows", async () => {
    const s = await startGame();
    await fill(s);
    await s.t.run(async (ctx) => {
      const { purgeCoupleContent } = await import("./lib/relationshipCleanup");
      const couple = (await ctx.db.query("couples").first())!;
      await purgeCoupleContent(ctx, couple);
    });
    expect(await count(s.t, s.coupleId)).toEqual({ story_chain_games: 0, story_chain_stories: 0, story_chain_stars: 0, story_chain_used: 0 });
  });
});
