// Model-based fuzz test for Draw & Guess. Each seed creates a couple and plays a long random
// sequence of actions by both partners against the real functions, keeps a small reference
// model of the rules in docs/games/draw-and-guess.md, and checks invariants after every step.
//
// Run one seed:      GAMES_FUZZ_SEED=123 npx vitest run convex/games.fuzz.test.ts
// Run more seeds:    GAMES_FUZZ_RUNS=3000 npx vitest run convex/games.fuzz.test.ts
// Start elsewhere:   GAMES_FUZZ_FIRST_SEED=5000 GAMES_FUZZ_RUNS=1000 ...
//
// The seed drives the action choices and `Math.random` on the server (the word picks), so a
// failure replays from its seed. Only uuids stay random, and no rule depends on them.
import type { FunctionReturnType } from "convex/server";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { WORD_CATALOGS, WORD_DIFFICULTIES, type GameLanguage, type WordDifficulty } from "./lib/gameWords";
import { newUuid } from "./lib/ids";
import { op, setMediaEnv, uploadAsset } from "./media.testing";
import { addDevice, createCouple, newTest, type TestConvex, type TestUser } from "./test.setup";

const RUNS = Number(process.env.GAMES_FUZZ_RUNS ?? 180);
const FIRST_SEED = Number(process.env.GAMES_FUZZ_FIRST_SEED ?? 1);
const ONLY_SEED = process.env.GAMES_FUZZ_SEED === undefined ? undefined : Number(process.env.GAMES_FUZZ_SEED);
const MIN_STEPS = 60;
const MAX_STEPS = 120;

// The rules, written from the docs rather than imported from the engine.
/** The speed bonus tiers: 2 within 15 seconds, 1 within 30, else 0. */
const bonusFor = (solveMs: number) => (solveMs <= 15_000 ? 2 : solveMs <= 30_000 ? 1 : 0);
const AVERAGE_MAX_MS = 10 * 60_000;
const HISTORY_MAX = 50;
const REACTIONS = ["love", "laugh", "wow"] as const;
const PRESENCE_FRESH_MS = 60_000;
const PRESENCE_DELETE_MS = 120_000;
const INVITE_GAP_MS = 15 * 60_000;
const REMINDER_AFTER_MS = 72 * 3_600_000;
const MAX_SOLVE_MS = 30 * 24 * 3_600_000;
const POINTS = { easy: 1, medium: 2, hard: 3, custom: 2 } as const;
const PUSH_KINDS = ["game_turn_ready", "game_guessed", "game_invite", "game_turn_reminder"] as const;
const PAYLOAD_KEYS = new Set(["type", "game_kind", "couple_id", "game_id", "round_id", "actor_user_id", "route", "deeplink"]);
const VALID_CUSTOM = ["flying cat", "  Dog At   Mom ", "Brunost", "ab", "Æ Ø Å", "hot dog", "x".repeat(20)];
const INVALID_CUSTOM = ["", "a", "   ", "cat5", "one two three four", "x".repeat(21), "no!", "tæ.st"];
const TIME_JUMPS = [1_000, 4_000, 14_000, 15_000, 15_001, 29_000, 30_000, 30_001, 31_000, 61_000, 125_000, INVITE_GAP_MS, REMINDER_AFTER_MS - 1_000, REMINDER_AFTER_MS, REMINDER_AFTER_MS + 3_600_000];

type Uid = string;
type Choice = { difficulty: WordDifficulty; word_id: string; word: string };
type RoundState = "drawing" | "guessing" | "solved" | "missed";
type Round = {
  id: string;
  number: number;
  drawer: Uid;
  guesser: Uid;
  state: RoundState;
  difficulty: keyof typeof POINTS;
  word: string;
  points: number;
  drawing?: string;
  submittedAt?: number;
  seenAt?: number;
  endedAt?: number;
  solveMs?: number;
  speedBonus: number;
  firstTryBonus: number;
  hintsUsed: number;
  personalBest: boolean;
  reaction?: (typeof REACTIONS)[number];
  drawerSeenAt?: number;
  guesserSeenAt?: number;
  stars: Set<Uid>;
  attempts: { text: string; correct: boolean }[];
  frozen?: string;
};
type Asset = { id: string; owner: Uid; roundId: string; used: boolean };
type OpName = "pick" | "submit" | "guess" | "giveUp";
type Args = Record<string, unknown> & { p_client_operation_id: string };
type RecordedOp = { name: OpName; user: Uid; args: Args; key: string; result: unknown };
type View = FunctionReturnType<typeof api.games.get_draw_and_guess>;
type Outcome<T> = { ok: true; value: T } | { ok: false; code: string; message: string };
type Expect = "ok" | { code: string; message?: RegExp };

type Model = {
  style: "together" | "against";
  language: GameLanguage;
  state: "choosing_word" | "drawing" | "guessing";
  turnUser: Uid;
  turnNumber: number;
  currentRoundId?: string;
  shared: number;
  points: Record<Uid, number>;
  /** The choices on offer. `null` means a fresh draw is due and the next check validates it. */
  choices: Choice[] | null | undefined;
  used: Record<GameLanguage, Record<WordDifficulty, Set<string>>>;
  turnStartedAt: number;
  reminded: boolean;
  presence: Record<Uid, number | undefined>;
  lastInvite: Record<Uid, number | undefined>;
  rounds: Round[];
  pushes: Record<(typeof PUSH_KINDS)[number], number>;
  drawingsSent: number;
  assets: Asset[];
  ops: RecordedOp[];
  opsByKey: Map<string, RecordedOp>;
  lastVersion: number;
};

class FuzzFailure extends Error {}

function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let x = state;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

/** JSON with sorted object keys, so key order never matters in a comparison. */
const canonical = (value: unknown) =>
  JSON.stringify(value, (_key, item) =>
    item && typeof item === "object" && !Array.isArray(item) ? Object.fromEntries(Object.entries(item).sort(([x], [y]) => (x < y ? -1 : 1))) : item,
  );
const iso = (ms: number) => new Date(ms).toISOString();
const orNull = <T,>(value: T | undefined) => (value === undefined ? null : value);
const normalize = (text: string) => text.trim().replace(/\s+/g, " ").toLowerCase();
const finished = (round: Round) => round.state === "solved" || round.state === "missed";

/** The doc's custom word rule: 2 to 20 letters, at most three words, letters a-z plus æøå. */
function customWordOf(input: string): string | null {
  const word = normalize(input);
  const parts = word.split(" ");
  const letters = [...word.replace(/ /g, "")];
  const ok = parts.length <= 3 && parts.every((part) => /^[a-zæøå]+$/.test(part)) && letters.length >= 2 && letters.length <= 20;
  return ok ? word : null;
}

const POOLS: Record<GameLanguage, Record<WordDifficulty, Map<string, string>>> = {
  en: { easy: new Map(), medium: new Map(), hard: new Map() },
  nb: { easy: new Map(), medium: new Map(), hard: new Map() },
};
for (const language of ["en", "nb"] as const) {
  for (const entry of WORD_CATALOGS[language].words) POOLS[language][entry.difficulty].set(entry.id, entry.text);
}

async function attempt<T>(promise: Promise<T>): Promise<Outcome<T>> {
  try {
    return { ok: true, value: await promise };
  } catch (error) {
    const data = (error as { data?: unknown }).data;
    if (data && typeof data === "object" && "code" in data) {
      const { code, message } = data as { code: string; message: string };
      return { ok: false, code, message };
    }
    throw new FuzzFailure(`server error that is not a ConvexError: ${(error as Error).stack ?? error}`);
  }
}

class Fuzz {
  readonly log: string[] = [];
  private readonly rng: () => number;
  private t!: TestConvex;
  private a!: TestUser;
  private b!: TestUser;
  private users!: Record<Uid, TestUser>;
  private gameId!: string;
  private coupleId!: string;
  private m!: Model;

  constructor(readonly seed: number) {
    this.rng = mulberry32(seed);
  }

  // --- Randomness ------------------------------------------------------------

  private chance(p: number) {
    return this.rng() < p;
  }
  private int(min: number, max: number) {
    return min + Math.floor(this.rng() * (max - min + 1));
  }
  private pick<T>(items: readonly T[]): T {
    return items[Math.floor(this.rng() * items.length)];
  }
  private other(user: Uid): Uid {
    return user === this.a.userId ? this.b.userId : this.a.userId;
  }
  private actor(preferred: Uid): Uid {
    return this.chance(0.8) ? preferred : this.pick([this.a.userId, this.b.userId]);
  }
  private name(user: Uid) {
    return user === this.a.userId ? "A" : "B";
  }
  private round(id: string) {
    return this.m.rounds.find((round) => round.id === id);
  }
  private latest() {
    return this.m.rounds.at(-1);
  }
  private targetRound(): string {
    const latest = this.latest();
    if (latest && this.chance(0.75)) return latest.id;
    if (this.m.rounds.length > 0 && this.chance(0.6)) return this.pick(this.m.rounds).id;
    return newUuid();
  }
  private present(user: Uid) {
    const seen = this.m.presence[user];
    return seen !== undefined && seen >= Date.now() - PRESENCE_FRESH_MS;
  }

  private note(line: string) {
    this.log.push(`${this.log.length}. ${line}`);
  }

  private check<T>(label: string, outcome: Outcome<T>, expected: Expect): T | undefined {
    const got = outcome.ok ? `ok ${JSON.stringify(outcome.value)}` : `${outcome.code} ${outcome.message}`;
    this.note(`${label} -> ${got.slice(0, 300)}`);
    if (expected === "ok") {
      if (!outcome.ok) throw new FuzzFailure(`${label}: expected success, got ${got}`);
      return outcome.value;
    }
    if (outcome.ok) throw new FuzzFailure(`${label}: expected ${expected.code}, got ${got}`);
    if (outcome.code !== expected.code || (expected.message && !expected.message.test(outcome.message))) {
      throw new FuzzFailure(`${label}: expected ${expected.code} ${expected.message ?? ""}, got ${got}`);
    }
    return undefined;
  }

  private same(label: string, actual: unknown, expected: unknown) {
    const a = canonical(actual);
    const e = canonical(expected);
    if (a !== e) throw new FuzzFailure(`${label}: expected ${e}, got ${a}`);
  }

  private assert(label: string, condition: boolean, detail: unknown = "") {
    if (!condition) throw new FuzzFailure(`${label} ${typeof detail === "string" ? detail : JSON.stringify(detail)}`);
  }

  // --- Setup -----------------------------------------------------------------

  async setup() {
    this.t = newTest();
    const couple = await createCouple(this.t);
    this.a = couple.first;
    this.b = couple.second;
    this.coupleId = couple.coupleId;
    this.users = { [this.a.userId]: this.a, [this.b.userId]: this.b };
    await addDevice(this.t, this.a.userId);
    await addDevice(this.t, this.b.userId);
    const style = this.pick(["together", "against"] as const);
    const language = this.pick(["en", "nb"] as const);
    const first = this.pick([this.a, this.b]);
    await first.as.mutation(api.games.set_game_settings, { p_play_style: style, p_language: language });
    const { game_id } = await first.as.mutation(api.games.ensure_draw_and_guess_game, {});
    this.gameId = game_id;
    const empty = () => ({ easy: new Set<string>(), medium: new Set<string>(), hard: new Set<string>() });
    this.m = {
      style,
      language,
      state: "choosing_word",
      turnUser: first.userId,
      turnNumber: 1,
      shared: 0,
      points: { [this.a.userId]: 0, [this.b.userId]: 0 },
      choices: null,
      used: { en: empty(), nb: empty() },
      turnStartedAt: Date.now(),
      reminded: false,
      presence: {},
      lastInvite: {},
      rounds: [],
      pushes: { game_turn_ready: 0, game_guessed: 0, game_invite: 0, game_turn_reminder: 0 },
      drawingsSent: 0,
      assets: [],
      ops: [],
      opsByKey: new Map(),
      lastVersion: 0,
    };
    this.note(`setup: ${this.name(first.userId)} draws first, ${style}, ${language}`);

    // Half the runs nearly exhaust one difficulty in both languages, so the start-over rule runs.
    if (this.chance(0.5)) {
      const difficulty = this.pick(WORD_DIFFICULTIES);
      const offered = await this.t.run(async (ctx) => (await ctx.db.query("games").first())!.word_choices ?? []);
      for (const lang of ["en", "nb"] as const) {
        const keep = this.int(0, 2);
        const ids = [...POOLS[lang][difficulty].keys()].filter((id) => !offered.some((choice) => choice.word_id === id));
        const marked = ids.slice(0, ids.length - keep);
        await this.t.run(async (ctx) => {
          for (const word_id of marked) {
            await ctx.db.insert("game_used_words", {
              game_id: this.gameId,
              couple_id: this.coupleId,
              language: lang,
              difficulty,
              word_id,
              created_at: new Date().toISOString(),
            });
          }
        });
        for (const id of marked) this.m.used[lang][difficulty].add(id);
      }
      this.note(`setup: ${difficulty} nearly used up`);
    }
    await this.checkInvariants();
  }

  // --- Actions ---------------------------------------------------------------

  async step() {
    const m = this.m;
    const open = this.latest() && !finished(this.latest()!);
    const anyFinished = m.rounds.some(finished);
    const actions: [number, () => Promise<void>][] = [
      [3, () => this.settings()],
      [m.state === "choosing_word" ? 16 : 2, () => this.pickWord()],
      [m.state === "choosing_word" ? 1 : 6, async () => void (await this.upload())],
      [m.state === "drawing" ? 12 : 3, () => this.submit()],
      [open ? 5 : 1, () => this.markSeen()],
      [open ? 14 : 2, () => this.guess()],
      [open ? 3 : 1, () => this.giveUp()],
      [m.ops.length > 0 ? 6 : 0, () => this.replay()],
      [anyFinished ? 3 : 1, () => this.react()],
      [anyFinished ? 3 : 1, () => this.star()],
      [anyFinished ? 3 : 1, () => this.resultSeen()],
      [2, () => this.invite()],
      [4, () => this.presence()],
      [7, () => this.timeJump()],
      [3, () => this.crons()],
    ];
    const total = actions.reduce((sum, [weight]) => sum + weight, 0);
    let roll = this.rng() * total;
    for (const [weight, action] of actions) {
      roll -= weight;
      if (roll < 0) {
        await action();
        break;
      }
    }
    await this.checkInvariants();
  }

  private async settings() {
    const user = this.pick([this.a.userId, this.b.userId]);
    const style = this.pick(["together", "against"] as const);
    const language = this.chance(0.5) ? this.m.language : this.pick(["en", "nb"] as const);
    const result = this.check(
      `${this.name(user)} set_game_settings ${style} ${language}`,
      await attempt(this.users[user].as.mutation(api.games.set_game_settings, { p_play_style: style, p_language: language })),
      "ok",
    )!;
    this.same("settings result", [result.play_style, result.language, result.updated_by_user_id], [style, language, user]);
    if (language !== this.m.language && this.m.state === "choosing_word") this.m.choices = null;
    this.m.style = style;
    this.m.language = language;
  }

  private async pickWord() {
    const m = this.m;
    const user = this.actor(m.turnUser);
    let choice: keyof typeof POINTS;
    let custom: string | null = null;
    let wordId: string | null = null;
    const roll = this.rng();
    if (roll < 0.6) {
      choice = this.pick(WORD_DIFFICULTIES);
      wordId = m.choices?.find((item) => item.difficulty === choice)?.word_id ?? this.pick([...POOLS[m.language][choice].keys()]);
    } else if (roll < 0.72) {
      // A stale or missing word id.
      choice = this.pick(WORD_DIFFICULTIES);
      wordId = this.chance(0.3) ? null : this.pick([...POOLS[this.pick(["en", "nb"] as const)][choice].keys()]);
    } else {
      choice = "custom";
      custom = this.chance(0.7) ? this.pick(VALID_CUSTOM) : this.pick(INVALID_CUSTOM);
      wordId = this.chance(0.2) ? "ignored" : null;
    }
    const roundId = m.rounds.length > 0 && this.chance(0.06) ? this.pick(m.rounds).id : newUuid();
    const gameId = this.chance(0.2) ? this.gameId.toUpperCase() : this.gameId;
    await this.runOp("pick", user, {
      ...op(),
      p_game_id: gameId,
      p_round_id: this.chance(0.2) ? roundId.toUpperCase() : roundId,
      p_choice: choice,
      p_custom_word: custom,
      p_word_id: wordId,
    });
  }

  private async freshPick(user: Uid, args: Args): Promise<Outcome<unknown>> {
    const m = this.m;
    const choice = args.p_choice as keyof typeof POINTS;
    const roundId = (args.p_round_id as string).toLowerCase();
    const customWord = choice === "custom" ? customWordOf((args.p_custom_word as string | null) ?? "") : null;
    let expected: Expect = "ok";
    let word = customWord ?? "";
    let wordId: string | undefined;
    if (choice === "custom" && customWord === null) expected = { code: "23514", message: /custom word/ };
    else if (user !== m.turnUser) expected = { code: "42501", message: /not your turn/ };
    else if (m.state !== "choosing_word") expected = { code: "23514", message: /already chosen/ };
    else if (this.round(roundId)) expected = { code: "23505", message: /game_moves_pkey/ };
    else if (choice !== "custom") {
      const offered = m.choices?.find((item) => item.difficulty === choice);
      if (!offered || offered.word_id !== (args.p_word_id ?? "")) expected = { code: "23514", message: /out of date|not available/ };
      else {
        word = offered.word;
        wordId = offered.word_id;
      }
    }
    const outcome = await attempt(this.users[user].as.mutation(api.games.pick_draw_word, args as never));
    const result = this.check(`${this.name(user)} pick ${choice} ${JSON.stringify(args.p_custom_word)} ${args.p_word_id} round=${roundId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok") return outcome;
    this.same("pick result", result, { round_id: roundId, round_number: m.turnNumber, difficulty: choice, word, points: POINTS[choice] });
    void wordId;
    m.rounds.push({
      id: roundId,
      number: m.turnNumber,
      drawer: user,
      guesser: this.other(user),
      state: "drawing",
      difficulty: choice,
      word,
      points: POINTS[choice],
      speedBonus: 0,
      firstTryBonus: 0,
      hintsUsed: 0,
      personalBest: false,
      stars: new Set(),
      attempts: [],
    });
    m.state = "drawing";
    m.currentRoundId = roundId;
    m.choices = undefined;
    return outcome;
  }

  private async upload(roundId = this.targetRound(), user?: Uid): Promise<Asset | undefined> {
    const round = this.round(roundId);
    const uploader = user ?? (round ? this.actor(round.drawer) : this.pick([this.a.userId, this.b.userId]));
    const expected: Expect = round && round.drawer === uploader ? "ok" : { code: "42501" };
    const outcome = await attempt(
      uploadAsset(this.t, this.users[uploader], {
        kind: "game_move",
        purpose: "game_drawing_payload",
        mediaType: "drawing_payload",
        extension: "pkdrawing",
        mime: "application/octet-stream",
        parentId: roundId,
        coupleId: this.coupleId,
        gameId: this.gameId,
      }),
    );
    const uploaded = this.check(`${this.name(uploader)} upload drawing round=${roundId.slice(0, 8)}`, outcome, expected);
    if (!uploaded) return undefined;
    const asset = { id: uploaded.assetId, owner: uploader, roundId, used: false };
    this.m.assets.push(asset);
    if (this.chance(0.15)) {
      // The reservation retried with the same client operation returns the same asset.
      const [again] = await this.users[uploader].as.mutation(api.media.create_pending_media_upload, {
        ...op(uploaded.reserveOperationId),
        p_reserved_parent_kind: "game_move",
        p_reserved_parent_id: roundId,
        p_upload_purpose: "game_drawing_payload",
        p_media_type: "drawing_payload",
        p_file_extension: "pkdrawing",
        p_couple_id: this.coupleId,
        p_path_context: { game_id: this.gameId },
      });
      this.same("reserve retry", again.media_asset_id, asset.id);
      this.note(`${this.name(uploader)} reserve retry -> same asset`);
    }
    return asset;
  }

  private async submit() {
    const m = this.m;
    const latest = this.latest();
    const roll = this.rng();
    let user: Uid;
    let roundId: string;
    let assetId: string;
    if (latest && roll < 0.65) {
      // The drawer sends an asset of the round, uploading one first when needed.
      roundId = latest.id;
      user = latest.drawer;
      const unused = m.assets.find((asset) => asset.roundId === roundId && asset.owner === user && !asset.used);
      const asset = unused && this.chance(0.8) ? unused : await this.upload(roundId, user);
      assetId = asset!.id;
    } else if (latest && roll < 0.75) {
      // The wrong user sends the drawer's asset.
      roundId = latest.id;
      user = latest.guesser;
      assetId = (m.assets.find((asset) => asset.roundId === roundId) ?? { id: newUuid() }).id;
    } else if (m.assets.length > 0 && roll < 0.9) {
      // Some asset, maybe of another round or already used.
      const asset = this.pick(m.assets);
      roundId = this.chance(0.5) ? asset.roundId : this.targetRound();
      user = this.actor(asset.owner);
      assetId = asset.id;
    } else {
      roundId = this.targetRound();
      user = this.pick([this.a.userId, this.b.userId]);
      assetId = newUuid();
    }
    await this.runOp("submit", user, { ...op(), p_round_id: roundId, p_media_asset_id: this.chance(0.2) ? assetId.toUpperCase() : assetId });
  }

  private async freshSubmit(user: Uid, args: Args): Promise<Outcome<unknown>> {
    const m = this.m;
    const roundId = (args.p_round_id as string).toLowerCase();
    const assetId = (args.p_media_asset_id as string).toLowerCase();
    const round = this.round(roundId);
    const asset = m.assets.find((item) => item.id === assetId);
    let expected: Expect = "ok";
    if (!round) expected = { code: "42501" };
    else if (round.drawer !== user) expected = { code: "42501", message: /only the drawer/ };
    else if (round.drawing !== undefined) expected = { code: "23505", message: /already sent/ };
    else if (!asset || asset.owner !== user || asset.roundId !== roundId || asset.used) expected = { code: "23514", message: /not usable/ };
    const outcome = await attempt(this.users[user].as.mutation(api.games.submit_drawing, args as never));
    const result = this.check(`${this.name(user)} submit_drawing round=${roundId.slice(0, 8)} asset=${assetId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok" || !round || !asset) return outcome;
    const now = Date.now();
    round.drawing = assetId;
    round.submittedAt = now;
    asset.used = true;
    m.drawingsSent += 1;
    if (round.state === "drawing") {
      round.state = "guessing";
      m.state = "guessing";
      m.turnUser = round.guesser;
      m.turnStartedAt = now;
      m.reminded = false;
      if (!this.present(round.guesser)) m.pushes.game_turn_ready += 1;
    }
    this.same("submit result", result, { round_id: roundId, round_state: round.state, drawing_submitted_at: iso(now) });
    return outcome;
  }

  private async markSeen() {
    const roundId = this.targetRound();
    const round = this.round(roundId);
    const user = round ? this.actor(round.guesser) : this.pick([this.a.userId, this.b.userId]);
    let expected: Expect = "ok";
    if (!round) expected = { code: "42501" };
    else if (round.guesser !== user) expected = { code: "42501", message: /only the guesser/ };
    const outcome = await attempt(this.users[user].as.mutation(api.games.mark_round_seen, { p_round_id: roundId }));
    const result = this.check(`${this.name(user)} mark_round_seen round=${roundId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok" || !round) return;
    if (!finished(round) && round.seenAt === undefined) round.seenAt = Date.now();
    this.same("mark_round_seen result", result, { guesser_first_seen_at: round.seenAt === undefined ? null : iso(round.seenAt) });
  }

  private async guess() {
    const roundId = this.targetRound();
    const round = this.round(roundId);
    const user = round ? this.actor(round.guesser) : this.pick([this.a.userId, this.b.userId]);
    if (round && !finished(round) && round.seenAt !== undefined && this.chance(0.25)) {
      // Land right on the edge of a speed bonus tier.
      const edge = round.seenAt + this.pick([14_999, 15_000, 15_001, 29_999, 30_000, 30_001]);
      if (edge > Date.now()) {
        vi.setSystemTime(new Date(edge));
        this.note(`time -> ${iso(edge)} (bonus window edge)`);
      }
    }
    const roll = this.rng();
    let text: string;
    if (round && roll < 0.35) text = round.word;
    else if (round && roll < 0.45) text = `  ${round.word.toUpperCase().replace(/ /g, "   ")} `;
    else if (roll < 0.8) text = this.pick([...POOLS[this.m.language][this.pick(WORD_DIFFICULTIES)].values()]);
    else if (roll < 0.87) text = "   ";
    else if (roll < 0.93) text = "x".repeat(41);
    else text = "y".repeat(40);
    const claimRoll = this.rng();
    let claim: Record<string, unknown> = {};
    if (claimRoll < 0.4) claim = {};
    else if (claimRoll < 0.6) claim = { p_speed_bonus: this.int(0, 2), p_solve_ms: this.int(0, 120_000) };
    else if (claimRoll < 0.7) claim = { p_speed_bonus: this.int(0, 2) };
    else if (claimRoll < 0.78) claim = { p_solve_ms: this.chance(0.5) ? this.int(0, 90_000) : this.int(0, 90_000) + 0.5 };
    else if (claimRoll < 0.83) claim = { p_speed_bonus: null, p_solve_ms: null };
    else if (claimRoll < 0.88) claim = { p_speed_bonus: 2, p_solve_ms: this.pick([MAX_SOLVE_MS, MAX_SOLVE_MS + 1, 40 * 24 * 3_600_000]) };
    else if (claimRoll < 0.92) claim = { p_solve_ms: this.pick([-1, Number.POSITIVE_INFINITY]) };
    else if (claimRoll < 0.96) claim = { p_speed_bonus: this.pick([3, -1, 1.5]) };
    const hintRoll = this.rng();
    if (hintRoll < 0.25) claim = { ...claim, p_hints_used: this.int(0, 3) };
    else if (hintRoll < 0.3) claim = { ...claim, p_hints_used: this.pick([null, 0, 7, 99, -1, 1.5]) };
    await this.runOp("guess", user, { ...op(), p_round_id: roundId, p_guess: text, ...claim });
  }

  /** The doc's fallback: the tiered bonus for the time since the guesser first saw the drawing. */
  private scoreSolve(round: Round, now: number): { bonus: number; solveMs: number | undefined } {
    if (round.seenAt === undefined) return { bonus: 0, solveMs: undefined };
    const solveMs = Math.max(0, now - round.seenAt);
    return { bonus: bonusFor(solveMs), solveMs };
  }

  private beginTurn(drawer: Uid) {
    const m = this.m;
    m.state = "choosing_word";
    m.turnUser = drawer;
    m.turnNumber += 1;
    m.choices = null;
    m.turnStartedAt = Date.now();
    m.reminded = false;
  }

  /** The solve time a guess may claim: any finite time from 0 up. */
  private solveMsAllowed(value: number) {
    return Number.isFinite(value) && value >= 0;
  }

  private async freshGuess(user: Uid, args: Args): Promise<Outcome<unknown>> {
    const m = this.m;
    const roundId = (args.p_round_id as string).toLowerCase();
    const round = this.round(roundId);
    const text = normalize(args.p_guess as string);
    const claimBonus = (args.p_speed_bonus as number | null | undefined) ?? null;
    const claimMs = (args.p_solve_ms as number | null | undefined) ?? null;
    const claimHints = (args.p_hints_used as number | null | undefined) ?? null;
    const correct = round !== undefined && text === round.word;
    let expected: Expect = "ok";
    if (text === "" || [...text].length > 40) expected = { code: "23514", message: /guess must be/ };
    else if (claimBonus !== null && ![0, 1, 2].includes(claimBonus)) expected = { code: "23514", message: /speed bonus/ };
    else if (claimMs !== null && !this.solveMsAllowed(claimMs)) expected = { code: "23514", message: /solve time/ };
    else if (claimHints !== null && !(Number.isInteger(claimHints) && claimHints >= 0)) expected = { code: "23514", message: /hints used must be/ };
    else if (!round) expected = { code: "42501" };
    else if (round.guesser !== user) expected = { code: "42501", message: /only the guesser/ };
    else if (finished(round)) expected = { code: "23514", message: /already finished/ };
    else if (correct && claimHints !== null && claimHints > [...round.word.replace(/ /g, "")].length - 1) expected = { code: "23514", message: /more than the word allows/ };
    const outcome = await attempt(this.users[user].as.mutation(api.games.submit_guess, args as never));
    const claimText = `bonus=${args.p_speed_bonus} ms=${args.p_solve_ms} hints=${args.p_hints_used}`;
    const result = this.check(`${this.name(user)} guess ${JSON.stringify(args.p_guess)} ${claimText} round=${roundId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok" || !round) return outcome;
    const now = Date.now();
    const firstAttempt = round.attempts.length === 0;
    round.attempts.push({ text, correct });
    const value = result as Record<string, unknown>;
    if (!correct) {
      this.same(
        "wrong guess result",
        [value.correct, value.round_state, value.points, value.speed_bonus, value.first_try_bonus, value.hints_used, value.personal_best, value.solve_ms, value.created_at],
        [false, round.state, 0, 0, 0, 0, false, null, iso(now)],
      );
      return outcome;
    }
    const hints = claimHints ?? 0;
    const scored = this.scoreSolve(round, now);
    const bonus = hints > 0 ? 0 : (claimBonus ?? scored.bonus);
    const firstTry = hints === 0 && firstAttempt ? 1 : 0;
    const solveMs = claimMs === null ? scored.solveMs : this.storedSolveMs(claimMs);
    const earlier = m.rounds.filter((item) => item.state === "solved" && item.guesser === round.guesser && item.hintsUsed === 0 && item.solveMs !== undefined);
    const personalBest = hints === 0 && solveMs !== undefined && earlier.length > 0 && earlier.every((item) => solveMs < item.solveMs!);
    round.state = "solved";
    round.endedAt = now;
    round.solveMs = solveMs;
    round.speedBonus = bonus;
    round.firstTryBonus = firstTry;
    round.hintsUsed = hints;
    round.personalBest = personalBest;
    m.shared += round.points;
    m.points[round.drawer] += round.points;
    m.points[round.guesser] += round.points + bonus + firstTry;
    this.beginTurn(round.guesser);
    if (!this.present(round.drawer)) m.pushes.game_guessed += 1;
    this.same(
      "correct guess result",
      [value.correct, value.round_state, value.points, value.speed_bonus, value.first_try_bonus, value.hints_used, value.personal_best, value.solve_ms, value.created_at],
      [true, "solved", round.points, bonus, firstTry, hints, personalBest, orNull(solveMs), iso(now)],
    );
    return outcome;
  }

  /** A claimed solve time is stored rounded and capped at 30 days. */
  private storedSolveMs(value: number) {
    return Math.min(Math.round(value), MAX_SOLVE_MS);
  }

  private async giveUp() {
    const roundId = this.targetRound();
    const round = this.round(roundId);
    const user = round ? this.actor(round.guesser) : this.pick([this.a.userId, this.b.userId]);
    await this.runOp("giveUp", user, { ...op(), p_round_id: roundId });
  }

  private async freshGiveUp(user: Uid, args: Args): Promise<Outcome<unknown>> {
    const roundId = (args.p_round_id as string).toLowerCase();
    const round = this.round(roundId);
    let expected: Expect = "ok";
    if (!round) expected = { code: "42501" };
    else if (round.guesser !== user) expected = { code: "42501", message: /only the guesser/ };
    else if (finished(round)) expected = { code: "23514", message: /already finished/ };
    const outcome = await attempt(this.users[user].as.mutation(api.games.give_up_round, args as never));
    const result = this.check(`${this.name(user)} give_up round=${roundId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok" || !round) return outcome;
    this.same("give up result", result, { round_id: roundId, round_state: "missed" });
    round.state = "missed";
    round.endedAt = Date.now();
    this.beginTurn(round.guesser);
    return outcome;
  }

  // --- Client operations and replays ------------------------------------------

  /** The request fields the server hashes, in the model's own words. */
  private requestKey(name: OpName, args: Args): string {
    const lower = (value: unknown) => String(value).toLowerCase();
    switch (name) {
      case "pick": {
        const custom = args.p_choice === "custom";
        return JSON.stringify([name, lower(args.p_game_id), lower(args.p_round_id), args.p_choice, custom ? customWordOf(String(args.p_custom_word ?? "")) : "", custom ? "" : (args.p_word_id ?? "")]);
      }
      case "submit":
        return JSON.stringify([name, lower(args.p_round_id), lower(args.p_media_asset_id)]);
      case "guess":
        return JSON.stringify([name, lower(args.p_round_id), normalize(String(args.p_guess)), args.p_speed_bonus ?? null, args.p_solve_ms ?? null, args.p_hints_used ?? null]);
      case "giveUp":
        return JSON.stringify([name, lower(args.p_round_id)]);
    }
  }

  private async callOp(name: OpName, user: Uid, args: Args): Promise<Outcome<unknown>> {
    const as = this.users[user].as;
    switch (name) {
      case "pick":
        return await attempt(as.mutation(api.games.pick_draw_word, args as never));
      case "submit":
        return await attempt(as.mutation(api.games.submit_drawing, args as never));
      case "guess":
        return await attempt(as.mutation(api.games.submit_guess, args as never));
      case "giveUp":
        return await attempt(as.mutation(api.games.give_up_round, args as never));
    }
  }

  private async runOp(name: OpName, user: Uid, args: Args) {
    const opKey = `${user}:${args.p_client_operation_id.toLowerCase()}`;
    const prior = this.m.opsByKey.get(opKey);
    if (prior) {
      // A replay: the first result when the request matches, a hash mismatch otherwise, and no change either way.
      const before = await this.snapshot();
      const outcome = await this.callOp(name, user, args);
      if (prior.key === this.requestKey(name, args)) {
        const value = this.check(`${this.name(user)} replay ${name} (same request)`, outcome, "ok");
        this.same("replayed result", value, prior.result);
      } else {
        this.check(`${this.name(user)} replay ${name} (changed request)`, outcome, { code: "23505", message: /replay hash mismatch/ });
      }
      this.same("state after a replay", await this.snapshot(), before);
      return;
    }
    const fresh = { pick: this.freshPick, submit: this.freshSubmit, guess: this.freshGuess, giveUp: this.freshGiveUp }[name];
    const outcome = await fresh.call(this, user, args);
    if (outcome.ok) {
      const recorded = { name, user, args, key: this.requestKey(name, args), result: outcome.value };
      this.m.ops.push(recorded);
      this.m.opsByKey.set(opKey, recorded);
    }
  }

  private async replay() {
    const recorded = this.pick(this.m.ops);
    const roll = this.rng();
    const fresh = op(recorded.args.p_client_operation_id);
    if (roll < 0.45) {
      const args: Args = { ...recorded.args, ...fresh };
      if (this.chance(0.4)) {
        for (const key of ["p_round_id", "p_game_id", "p_media_asset_id", "p_client_operation_id"]) {
          if (typeof args[key] === "string") args[key] = (args[key] as string).toUpperCase();
        }
      }
      await this.runOp(recorded.name, recorded.user, args);
    } else if (roll < 0.8) {
      const changed: Args = { ...recorded.args, ...fresh };
      if (recorded.name === "guess") {
        if (this.chance(0.5) || recorded.args.p_speed_bonus === undefined) changed.p_guess = "fuzz changed";
        else changed.p_speed_bonus = (Number(recorded.args.p_speed_bonus ?? 0) + 1) % 3;
      } else if (recorded.name === "submit") changed.p_media_asset_id = newUuid();
      else changed.p_round_id = newUuid();
      await this.runOp(recorded.name, recorded.user, changed);
    } else {
      // The other partner sends the same operation id: a new operation for them.
      await this.runOp(recorded.name, this.other(recorded.user), { ...recorded.args, ...fresh });
    }
  }

  private async snapshot(): Promise<string> {
    const views = [await this.view(this.a), await this.view(this.b)];
    const tables = await this.t.run(async (ctx) => ({
      moves: await ctx.db.query("game_moves").collect(),
      games: await ctx.db.query("games").collect(),
      guesses: (await ctx.db.query("game_guesses").collect()).length,
      used: (await ctx.db.query("game_used_words").collect()).length,
      outbox: (await ctx.db.query("notification_outbox").collect()).length,
      activity: (await ctx.db.query("couple_activity_events").collect()).length,
      operations: (await ctx.db.query("client_operations").collect()).length,
    }));
    return canonical({ views, tables });
  }

  // --- Reactions, stars, result seen, invites, presence, time ---------------------

  /** A finished round most of the time, otherwise any round id, so the "not finished" and unknown cases run too. */
  private afterRound(): { roundId: string; round: Round | undefined } {
    const done = this.m.rounds.filter(finished);
    const roundId = done.length > 0 && this.chance(0.7) ? this.pick(done).id : this.targetRound();
    return { roundId, round: this.round(roundId) };
  }

  private async react() {
    const { roundId, round } = this.afterRound();
    const user = round ? this.actor(round.guesser) : this.pick([this.a.userId, this.b.userId]);
    const reaction = this.pick([...REACTIONS, null]);
    let expected: Expect = "ok";
    if (!round) expected = { code: "42501" };
    else if (round.guesser !== user) expected = { code: "42501", message: /only the guesser/ };
    else if (!finished(round)) expected = { code: "23514", message: /not finished/ };
    const outcome = await attempt(this.users[user].as.mutation(api.games.set_round_reaction, { p_round_id: roundId, p_reaction: reaction }));
    const result = this.check(`${this.name(user)} react ${reaction} round=${roundId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok") return;
    round!.reaction = reaction ?? undefined;
    this.same("reaction result", result, { round_id: roundId, guesser_reaction: reaction });
  }

  private async star() {
    const { roundId, round } = this.afterRound();
    const user = this.pick([this.a.userId, this.b.userId]);
    const starred = this.chance(0.6);
    let expected: Expect = "ok";
    if (!round) expected = { code: "42501" };
    else if (!finished(round)) expected = { code: "23514", message: /not finished/ };
    const outcome = await attempt(this.users[user].as.mutation(api.games.set_round_star, { p_round_id: roundId, p_starred: starred }));
    const result = this.check(`${this.name(user)} star ${starred} round=${roundId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok") return;
    if (starred) round!.stars.add(user);
    else round!.stars.delete(user);
    this.same("star result", result, { round_id: roundId, starred });
  }

  private async resultSeen() {
    const { roundId, round } = this.afterRound();
    const user = this.pick([this.a.userId, this.b.userId]);
    let expected: Expect = "ok";
    if (!round) expected = { code: "42501" };
    else if (!finished(round)) expected = { code: "23514", message: /not finished/ };
    const outcome = await attempt(this.users[user].as.mutation(api.games.mark_round_result_seen, { p_round_id: roundId }));
    const result = this.check(`${this.name(user)} result seen round=${roundId.slice(0, 8)}`, outcome, expected);
    if (expected !== "ok") return;
    const drawer = round!.drawer === user;
    const seenAt = (drawer ? round!.drawerSeenAt : round!.guesserSeenAt) ?? Date.now();
    if (drawer) round!.drawerSeenAt = seenAt;
    else round!.guesserSeenAt = seenAt;
    this.same("result seen result", result, { round_id: roundId, result_seen_at: iso(seenAt) });
  }

  private async invite() {
    const user = this.pick([this.a.userId, this.b.userId]);
    const last = this.m.lastInvite[user];
    const now = Date.now();
    const expected: Expect = last !== undefined && last > now - INVITE_GAP_MS ? { code: "53300" } : "ok";
    const outcome = await attempt(this.users[user].as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" }));
    const result = this.check(`${this.name(user)} invite`, outcome, expected);
    if (expected !== "ok") return;
    this.same("invite result", result, { sent_at: iso(now) });
    this.m.lastInvite[user] = now;
    this.m.pushes.game_invite += 1;
  }

  private async presence() {
    const user = this.pick([this.a.userId, this.b.userId]);
    const present = this.chance(0.7);
    const outcome = await attempt(this.users[user].as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: present }));
    this.check(`${this.name(user)} presence ${present}`, outcome, "ok");
    this.m.presence[user] = present ? Date.now() : undefined;
  }

  private async timeJump() {
    const delta = this.pick(TIME_JUMPS);
    vi.setSystemTime(new Date(Date.now() + delta));
    this.note(`time +${delta} ms -> ${iso(Date.now())}`);
    if (this.chance(0.4)) await this.crons();
  }

  private async crons() {
    const m = this.m;
    const now = Date.now();
    const due = !m.reminded && m.turnStartedAt <= now - REMINDER_AFTER_MS;
    const outcome = await attempt(this.t.mutation(internal.games.send_due_game_turn_reminders, {}));
    const sent = this.check("cron send_due_game_turn_reminders", outcome, "ok");
    this.same("reminders sent", sent, due ? 1 : 0);
    if (due) {
      m.reminded = true;
      m.pushes.game_turn_reminder += 1;
    }
    const stale = Object.entries(m.presence).filter(([, seen]) => seen !== undefined && seen < now - PRESENCE_DELETE_MS);
    const removed = this.check("cron cleanup_stale_game_presence", await attempt(this.t.mutation(internal.games.cleanup_stale_game_presence, {})), "ok");
    this.same("presence rows removed", removed, stale.length);
    for (const [user] of stale) m.presence[user] = undefined;
  }

  // --- Invariants -------------------------------------------------------------

  private async view(user: TestUser): Promise<View> {
    return await user.as.query(api.games.get_draw_and_guess, {});
  }

  private roundJson(round: Round, viewer: Uid) {
    return {
      id: round.id,
      round_number: round.number,
      drawer_user_id: round.drawer,
      guesser_user_id: round.guesser,
      state: round.state,
      difficulty: round.difficulty,
      word: round.word,
      points: round.points,
      drawing_media_asset_id: orNull(round.drawing),
      drawing_submitted_at: round.submittedAt === undefined ? null : iso(round.submittedAt),
      guesser_first_seen_at: round.seenAt === undefined ? null : iso(round.seenAt),
      ended_at: round.endedAt === undefined ? null : iso(round.endedAt),
      solve_ms: orNull(round.solveMs),
      speed_bonus: round.speedBonus,
      first_try_bonus: round.firstTryBonus,
      hints_used: round.hintsUsed,
      personal_best: round.personalBest,
      guesser_reaction: orNull(round.reaction),
      starred_by_me: round.stars.has(viewer),
      drawer_result_seen_at: round.drawerSeenAt === undefined ? null : iso(round.drawerSeenAt),
      guesser_result_seen_at: round.guesserSeenAt === undefined ? null : iso(round.guesserSeenAt),
      attempt_count: round.attempts.length,
      attempts: round.attempts.map((item) => [item.text, item.correct]),
    };
  }

  private viewRound(json: NonNullable<View["current_round"]>) {
    const { started_at: _started, attempts, ...rest } = json;
    for (const item of attempts) this.assert("attempt by the guesser", item.user_id === json.guesser_user_id, item);
    return { ...rest, attempts: attempts.map((item) => [item.text, item.correct]) };
  }

  /** Validates a fresh draw of choices against the used words, then records it. */
  private acceptNewChoices(choices: Choice[]) {
    const m = this.m;
    for (const choice of choices) {
      const pool = POOLS[m.language][choice.difficulty];
      this.assert("choice is from the game language", pool.get(choice.word_id) === choice.word, choice);
      const used = m.used[m.language][choice.difficulty];
      if (used.has(choice.word_id)) {
        this.assert(`word ${choice.word_id} offered again before ${choice.difficulty} ran out`, used.size >= pool.size, { used: used.size, pool: pool.size });
        used.clear();
      } else if (used.size >= pool.size) {
        this.assert(`${choice.difficulty} ran out but did not start over`, false);
      }
      used.add(choice.word_id);
    }
    m.choices = choices;
  }

  async checkInvariants() {
    const m = this.m;
    for (const [me, user] of [
      [this.a.userId, this.a],
      [this.b.userId, this.b],
    ] as const) {
      const v = await this.view(user);
      const partner = this.other(me);
      const who = this.name(me);
      this.same(`${who} identity`, [v.user_id, v.partner_user_id, v.couple_id], [me, partner, this.coupleId]);
      this.same(`${who} settings`, [v.settings?.play_style, v.settings?.language], [m.style, m.language]);
      const game = v.game!;
      this.same(
        `${who} game`,
        [game.id, game.state, game.turn_user_id, game.turn_number, game.current_round_id, game.shared_points, game.my_points, game.partner_points, game.turn_started_at],
        [this.gameId, m.state, m.turnUser, m.turnNumber, orNull(m.currentRoundId), m.shared, m.points[me], m.points[partner], iso(m.turnStartedAt)],
      );
      this.assert(`${who} version never goes back`, game.version >= m.lastVersion, { version: game.version, last: m.lastVersion });
      m.lastVersion = game.version;

      // Choices: only the drawer, only while a word is being chosen, three distinct difficulties.
      if (m.state === "choosing_word" && me === m.turnUser) {
        const choices = (v.choices ?? []).map(({ difficulty, word_id, word }) => ({ difficulty, word_id, word }));
        this.same(`${who} choice difficulties`, choices.map((choice) => choice.difficulty), ["easy", "medium", "hard"]);
        this.same(`${who} choice points`, (v.choices ?? []).map((choice) => choice.points), [1, 2, 3]);
        this.assert("three distinct words", new Set(choices.map((choice) => choice.word_id)).size === 3, choices);
        if (m.choices === null) this.acceptNewChoices(choices);
        else this.same(`${who} choices stay fixed`, choices, m.choices);
      } else {
        this.same(`${who} sees no choices`, v.choices, null);
      }

      // Rounds: the latest first, then up to 20 earlier ones.
      const ordered = [...m.rounds].reverse();
      this.same(`${who} current round`, v.current_round ? this.viewRound(v.current_round) : null, ordered[0] ? this.roundJson(ordered[0], me) : null);
      this.same(`${who} recent rounds`, v.recent_rounds.map((round) => this.viewRound(round)), ordered.slice(1, 21).map((round) => this.roundJson(round, me)));
      this.same(`${who} presence`, [v.my_last_seen_at, v.partner_last_seen_at], [
        m.presence[me] === undefined ? null : iso(m.presence[me]!),
        m.presence[partner] === undefined ? null : iso(m.presence[partner]!),
      ]);
      this.same(`${who} last invite`, v.last_invite_at, m.lastInvite[me] === undefined ? null : iso(m.lastInvite[me]!));
    }

    const db = await this.t.run(async (ctx) => ({
      game: (await ctx.db.query("games").first())!,
      moves: await ctx.db.query("game_moves").collect(),
      guesses: await ctx.db.query("game_guesses").collect(),
      stars: await ctx.db.query("game_round_stars").collect(),
      assets: await ctx.db.query("media_assets").collect(),
      outbox: await ctx.db.query("notification_outbox").collect(),
      activity: await ctx.db.query("couple_activity_events").collect(),
    }));

    // At most one unfinished round, and current_round_id points at it.
    const unfinished = db.moves.filter((move) => move.state === "drawing" || move.state === "guessing");
    this.assert("at most one unfinished round", unfinished.length <= 1, unfinished.map((move) => move.id));
    if (db.game.state === "choosing_word") {
      this.assert("no unfinished round while choosing", unfinished.length === 0);
      const top = Math.max(0, ...db.moves.map((move) => move.round_number));
      this.assert("turn_number is one past the last round", db.game.turn_number === top + 1, { turn: db.game.turn_number, top });
    } else {
      this.assert("an open turn has its round", unfinished.length === 1 && unfinished[0].id === db.game.current_round_id, { current: db.game.current_round_id });
      this.assert("round_number matches turn_number", unfinished[0].round_number === db.game.turn_number);
      const expectedTurnUser = db.game.state === "drawing" ? unfinished[0].drawer_user_id : unfinished[0].guesser_user_id;
      this.assert(`the ${db.game.state} turn belongs to the right partner`, db.game.turn_user_id === expectedTurnUser);
      if (db.game.state === "guessing") this.assert("a guessing round has its drawing", unfinished[0].drawing_media_asset_id !== undefined);
    }
    this.same("round numbers", db.moves.map((move) => move.round_number).sort((x, y) => x - y), db.moves.map((_, index) => index + 1));
    this.assert("rounds alternate drawers", db.moves.every((move) => move.drawer_user_id !== move.guesser_user_id));

    // Scores.
    const solved = db.moves.filter((move) => move.state === "solved");
    this.same("shared total is the sum of solved word points", db.game.shared_points, solved.reduce((sum, move) => sum + move.points, 0));
    for (const uid of [this.a.userId, this.b.userId]) {
      const own = solved.reduce(
        (sum, move) =>
          sum + (move.drawer_user_id === uid ? move.points : 0) + (move.guesser_user_id === uid ? move.points + move.speed_bonus + (move.first_try_bonus ?? 0) : 0),
        0,
      );
      this.same(`personal total of ${this.name(uid)}`, db.game.points_by_user[uid] ?? 0, own);
    }
    for (const move of db.moves) {
      this.assert("speed bonus is 0, 1 or 2, and only on a solve", move.speed_bonus === 0 || ([1, 2].includes(move.speed_bonus) && move.state === "solved"), move);
      this.assert("first-try bonus is 0 or 1, and only on a solve", (move.first_try_bonus ?? 0) === 0 || (move.first_try_bonus === 1 && move.state === "solved"), move);
      this.assert("a hint zeroes both bonuses", (move.hints_used ?? 0) === 0 || (move.speed_bonus === 0 && (move.first_try_bonus ?? 0) === 0), move);
      this.assert("only a solve is a personal best", move.state === "solved" || !move.personal_best, move);
      this.assert("only a finished round has a reaction", move.guesser_reaction === undefined || move.state === "solved" || move.state === "missed", move);
      this.same("points follow the difficulty", move.points, POINTS[move.difficulty]);
    }

    // A finished round never changes its result again.
    for (const round of m.rounds) {
      if (!finished(round)) continue;
      const move = db.moves.find((item) => item.id === round.id)!;
      const result = JSON.stringify([
        move.state, move.ended_at, move.solve_ms, move.speed_bonus, move.first_try_bonus, move.hints_used, move.personal_best,
        move.points, move.word, db.guesses.filter((g) => g.move_id === move.id).length,
      ]);
      if (round.frozen === undefined) round.frozen = result;
      else this.same(`finished round ${round.id.slice(0, 8)}`, result, round.frozen);
    }

    // Stars match the model, and a round has at most one star per partner.
    const starKeys = db.stars.map((star) => `${star.move_id}:${star.user_id}`).sort();
    this.same("stars", starKeys, m.rounds.flatMap((round) => [...round.stars].map((uid) => `${round.id}:${uid}`)).sort());
    for (const star of db.stars) this.same("star round number", star.round_number, m.rounds.find((round) => round.id === star.move_id)?.number);
    await this.checkHistoryAndRecords();

    // Pushes: the expected count per kind, at most one reminder per move, never the word.
    const words = m.rounds.map((round) => round.word);
    for (const kind of PUSH_KINDS) {
      this.same(`${kind} pushes`, db.outbox.filter((row) => row.kind === kind).length, m.pushes[kind]);
    }
    const reminderKeys = db.outbox.filter((row) => row.kind === "game_turn_reminder").map((row) => row.dedupe_key);
    this.assert("one reminder per move", new Set(reminderKeys).size === reminderKeys.length, reminderKeys);
    for (const row of db.outbox.filter((item) => (PUSH_KINDS as readonly string[]).includes(item.kind))) {
      const payload = row.payload as Record<string, unknown>;
      for (const key of Object.keys(payload)) this.assert("push payload key", PAYLOAD_KEYS.has(key), key);
      const texts = [row.title ?? "", row.body ?? "", row.dedupe_key ?? "", ...Object.values(payload).map(String)].map((text) => text.toLowerCase().replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g, "<id>").replace(/draw-and-guess|draw_and_guess/g, "<game>"));
      for (const word of words) {
        const pattern = new RegExp(`(^|[^a-zæøå])${word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}($|[^a-zæøå])`);
        this.assert(`push ${row.kind} names the word ${word}`, !texts.some((text) => pattern.test(text)), texts);
      }
    }

    // Every sent drawing counts once for the streak.
    const activity = db.activity.filter((row) => row.activity_kind === "game_turn_completed");
    this.same("streak activity per sent drawing", activity.length, m.drawingsSent);

    // Progress: someone can always act.
    if (m.state === "choosing_word") this.assert("the drawer has words to pick", m.choices !== undefined && m.choices !== null && m.choices.length === 3);
  }

  /** The history pages and the records, compared with the model for both partners. */
  private async checkHistoryAndRecords() {
    const m = this.m;
    const eligible = [...m.rounds].reverse().filter((round) => finished(round) && round.drawing !== undefined);
    const item = (round: Round, me: Uid) => ({
      id: round.id,
      round_number: round.number,
      drawer_user_id: round.drawer,
      guesser_user_id: round.guesser,
      word: round.word,
      difficulty: round.difficulty,
      points: round.points,
      state: round.state,
      drawing_media_asset_id: round.drawing,
      solve_ms: orNull(round.solveMs),
      speed_bonus: round.speedBonus,
      first_try_bonus: round.firstTryBonus,
      hints_used: round.hintsUsed,
      attempt_count: round.attempts.length,
      guesser_reaction: orNull(round.reaction),
      personal_best: round.personalBest,
      starred_by_me: round.stars.has(me),
      ended_at: round.endedAt === undefined ? null : iso(round.endedAt),
    });
    for (const me of [this.a.userId, this.b.userId]) {
      const who = this.name(me);
      for (const starredOnly of [false, true]) {
        const pool = eligible.filter((round) => !starredOnly || round.stars.has(me));
        const limit = this.chance(0.5) ? 1000 : this.int(1, 4);
        const before = this.chance(0.5) || pool.length === 0 ? null : this.pick(pool).number + this.int(0, 1);
        const candidates = pool.filter((round) => before === null || round.number < before);
        const size = Math.min(limit, HISTORY_MAX);
        const page = candidates.slice(0, size);
        const expected = {
          rounds: page.map((round) => item(round, me)),
          next_before_round_number: candidates.length > size ? page[page.length - 1].number : null,
        };
        const got = await this.users[me].as.query(api.games.get_draw_and_guess_history, {
          p_starred_only: starredOnly,
          p_before_round_number: before,
          p_limit: limit,
        });
        this.same(
          `${who} history starred=${starredOnly} limit=${limit} before=${before}`,
          { ...got, rounds: got.rounds.map(({ started_at: _started, ...rest }) => rest) },
          expected,
        );
      }
      const records = await this.users[me].as.query(api.games.get_draw_and_guess_records, {});
      this.same(`${who} records`, records, { partners: [me, this.other(me)].map((uid) => this.records(uid)) });
    }
  }

  /** One player's records, written from the docs. */
  private records(uid: Uid) {
    const solves = this.m.rounds.filter((round) => round.guesser === uid && round.state === "solved");
    const free = solves.filter((round) => round.hintsUsed === 0 && round.solveMs !== undefined);
    const short = free.filter((round) => round.solveMs! <= AVERAGE_MAX_MS);
    let fastest: Round | undefined;
    for (const round of free) if (fastest === undefined || round.solveMs! < fastest.solveMs!) fastest = round;
    return {
      user_id: uid,
      solves: solves.length,
      first_try_solves: solves.filter((round) => round.firstTryBonus > 0).length,
      average_solve_ms: short.length === 0 ? null : Math.round(short.reduce((sum, round) => sum + round.solveMs!, 0) / short.length),
      fastest_solve_ms: fastest?.solveMs ?? null,
      fastest_solve_word: fastest?.word ?? null,
      drawings_solved: this.m.rounds.filter((round) => round.drawer === uid && round.state === "solved").length,
    };
  }

  /** Plays two whole rounds from wherever the game is, to prove it can always move on. */
  async finish() {
    for (let roundsLeft = 2; roundsLeft > 0; ) {
      const m = this.m;
      if (m.state === "choosing_word") {
        const choice = m.choices![0];
        await this.runOp("pick", m.turnUser, { ...op(), p_game_id: this.gameId, p_round_id: newUuid(), p_choice: choice.difficulty, p_custom_word: null, p_word_id: choice.word_id });
      } else if (m.state === "drawing") {
        const round = this.latest()!;
        const asset = await this.upload(round.id, round.drawer);
        await this.runOp("submit", round.drawer, { ...op(), p_round_id: round.id, p_media_asset_id: asset!.id });
      } else {
        const round = this.latest()!;
        await this.runOp("guess", round.guesser, { ...op(), p_round_id: round.id, p_guess: round.word });
        roundsLeft -= 1;
      }
      await this.checkInvariants();
    }
    await this.t.finishAllScheduledFunctions(vi.runAllTimers);
  }
}

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
});
afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

async function runSeed(seed: number): Promise<string | null> {
  const fuzz = new Fuzz(seed);
  const serverRandom = mulberry32(seed ^ 0x5bd1e995);
  vi.spyOn(Math, "random").mockImplementation(serverRandom);
  vi.setSystemTime(new Date(Date.parse("2026-10-10T12:00:00.000Z") + seed * 1000));
  try {
    await fuzz.setup();
    const steps = MIN_STEPS + (seed % (MAX_STEPS - MIN_STEPS + 1));
    for (let index = 0; index < steps; index += 1) await fuzz.step();
    await fuzz.finish();
    return null;
  } catch (error) {
    const reason = error instanceof FuzzFailure ? error.message : String((error as Error).stack ?? error);
    return [
      `seed ${seed}: ${reason}`,
      `reproduce: GAMES_FUZZ_SEED=${seed} npx vitest run convex/games.fuzz.test.ts`,
      "action log:",
      ...fuzz.log.slice(-80),
    ].join("\n");
  } finally {
    vi.restoreAllMocks();
  }
}

test(
  "Draw & Guess keeps its rules through random play by both partners",
  async () => {
    const seeds = ONLY_SEED !== undefined ? [ONLY_SEED] : Array.from({ length: RUNS }, (_, index) => FIRST_SEED + index);
    const failures: string[] = [];
    for (const seed of seeds) {
      const failure = await runSeed(seed);
      if (failure) failures.push(failure);
    }
    if (failures.length > 0) {
      const summary = failures.map((failure) => failure.split("\n")[0]).join("\n");
      throw new Error(`${failures.length} of ${seeds.length} seeds failed:\n${summary}\n\nFirst failure:\n${failures[0]}`);
    }
    expect(failures).toEqual([]);
  },
  30 * 60_000,
);
