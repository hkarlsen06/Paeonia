// Tests for what every game shares: settings, the overview, invites, presence, the relay ticket,
// and the registry that the shared code uses to reach a game. Draw & Guess has its own tests in
// drawAndGuess.test.ts.
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { hmacSha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import { deleteCoupleGameRows, GAME_BACKENDS, gamePushStillWanted, type GameBackend } from "./lib/gameRegistry";
import { gameDeepLink } from "./lib/games";
import { GAME_PUSH_COPY } from "./lib/notificationCopy";
import { GAME_KINDS } from "./lib/validators";
import { endCouple, failure } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex } from "./test.setup";

const START = Date.parse("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));
const iso = () => new Date().toISOString();

/** A couple with a push device each. */
async function startCouple() {
  const t = newTest();
  const couple = await createCouple(t);
  await addDevice(t, couple.first.userId);
  await addDevice(t, couple.second.userId);
  return { t, couple, a: couple.first, b: couple.second };
}

const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

/** A backend that wants nothing and deletes nothing. Tests add the hook they watch. */
const nullBackend: GameBackend = {
  pushStillWanted: async () => false,
  deleteCoupleRows: async () => 0,
};

// Some tests swap registry entries. Put the registered games back after each one.
const registeredBackends = { ...GAME_BACKENDS };
afterEach(() => {
  Object.assign(GAME_BACKENDS, registeredBackends);
});

describe("access", () => {
  test("a user without a couple cannot use the shared game functions", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(loner.as.query(api.games.get_games_overview, {}))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" }))).code).toBe("42501");
    for (const kind of GAME_KINDS) {
      expect((await failure(loner.as.mutation(api.games.send_game_invite, { p_kind: kind }))).code).toBe("42501");
      expect((await failure(loner.as.mutation(api.games.set_game_presence, { p_kind: kind, p_present: true }))).code).toBe("42501");
      expect((await failure(loner.as.mutation(api.games.create_game_live_ticket, { p_kind: kind }))).code).toBe("42501");
    }
  });

  test("a couple without a subscription cannot use them either", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.query(api.games.get_games_overview, {}))).code).toBe("42501");
    expect((await failure(couple.first.as.mutation(api.games.send_game_invite, { p_kind: "mind_meld" }))).code).toBe("42501");
  });

  test("a kind outside the catalog is refused", async () => {
    const s = await startCouple();
    await expect(s.a.as.mutation(api.games.send_game_invite, { p_kind: "chess" as never })).rejects.toThrow();
    await expect(s.a.as.mutation(api.games.set_game_presence, { p_kind: "chess" as never, p_present: true })).rejects.toThrow();
    await expect(s.a.as.mutation(api.games.create_game_live_ticket, { p_kind: "chess" as never })).rejects.toThrow();
  });
});

describe("settings", () => {
  test("either partner writes them and the last write wins", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await couple.first.as.query(api.games.get_games_overview, {})).settings).toBeNull();
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    const changed = await couple.second.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "nb" });
    expect(changed).toMatchObject({ play_style: "against", language: "nb", updated_by_user_id: couple.second.userId, couple_id: couple.coupleId });
    expect((await couple.first.as.query(api.games.get_games_overview, {})).settings).toMatchObject({ play_style: "against", language: "nb" });
    expect(await t.run((ctx) => ctx.db.query("game_settings").collect())).toHaveLength(1);
  });

  test("a language change reaches every game that registered a hook, and the same language does not", async () => {
    const s = await startCouple();
    const onLanguageChanged = vi.fn<NonNullable<GameBackend["onLanguageChanged"]>>(async () => {});
    GAME_BACKENDS.mind_meld = { ...nullBackend, onLanguageChanged };
    try {
      await s.a.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
      await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "en" });
      expect(onLanguageChanged).not.toHaveBeenCalled();
      await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "nb" });
      expect(onLanguageChanged).toHaveBeenCalledTimes(1);
      expect(onLanguageChanged).toHaveBeenCalledWith(expect.anything(), s.couple.coupleId, "nb");
    } finally {
      GAME_BACKENDS.mind_meld = null;
    }
  });
});

describe("get_games_overview", () => {
  test("names the caller, the partner, and the couple, and has no settings or presence at first", async () => {
    const s = await startCouple();
    expect(await s.a.as.query(api.games.get_games_overview, {})).toEqual({
      user_id: s.a.userId,
      partner_user_id: s.b.userId,
      couple_id: s.couple.coupleId,
      settings: null,
      presence: [],
    });
    expect((await s.b.as.query(api.games.get_games_overview, {})).partner_user_id).toBe(s.a.userId);
  });

  test("returns the couple's settings once set", async () => {
    const s = await startCouple();
    const set = await s.a.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "nb" });
    expect((await s.b.as.query(api.games.get_games_overview, {})).settings).toEqual(set);
  });

  test("lists a kind only with a presence row of either partner or an invite from the caller", async () => {
    const s = await startCouple();
    const first = iso();
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    tick(10);
    const second = iso();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "connect_four", p_present: true });
    tick(10);
    const invited = await s.a.as.mutation(api.games.send_game_invite, { p_kind: "story_chain" });
    // Another kind with a presence row that was closed again leaves no entry.
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "dots_and_boxes", p_present: true });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "dots_and_boxes", p_present: false });

    // Entries follow the order of GAME_KINDS: mind_meld, story_chain, connect_four.
    expect((await s.a.as.query(api.games.get_games_overview, {})).presence).toEqual([
      { kind: "mind_meld", my_last_seen_at: first, partner_last_seen_at: null, last_invite_at: null },
      { kind: "story_chain", my_last_seen_at: null, partner_last_seen_at: null, last_invite_at: invited.sent_at },
      { kind: "connect_four", my_last_seen_at: null, partner_last_seen_at: second, last_invite_at: null },
    ]);
    // The partner's view swaps the two sides, and the invite belongs to the sender only.
    expect((await s.b.as.query(api.games.get_games_overview, {})).presence).toEqual([
      { kind: "mind_meld", my_last_seen_at: null, partner_last_seen_at: first, last_invite_at: null },
      { kind: "connect_four", my_last_seen_at: second, partner_last_seen_at: null, last_invite_at: null },
    ]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a stranger's rows stay out", async () => {
    const s = await startCouple();
    const other = await createCouple(s.t);
    await other.first.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await other.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    expect(await s.a.as.query(api.games.get_games_overview, {})).toMatchObject({ settings: null, presence: [] });
  });
});

describe("presence and invites for every kind", () => {
  test("a kind other than Draw & Guess keeps its own presence row and cron cleanup removes it", async () => {
    const s = await startCouple();
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    const rows = await s.t.run((ctx) => ctx.db.query("game_presence").collect());
    expect(rows.map((row) => row.kind).sort()).toEqual(["draw_and_guess", "mind_meld"]);

    tick(30);
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: false });
    expect((await s.t.run((ctx) => ctx.db.query("game_presence").collect())).map((row) => row.kind)).toEqual(["mind_meld"]);

    tick(121);
    expect(await s.t.mutation(internal.games.cleanup_stale_game_presence, {})).toBe(1);
    expect(await s.t.run((ctx) => ctx.db.query("game_presence").collect())).toHaveLength(0);
  });

  test("an open game screen does not silence an invite", async () => {
    const s = await startCouple();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "mind_meld" });
    expect(await outbox(s.t)).toHaveLength(1);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an invite for another kind is stored per kind, limited to one every 15 minutes, and has no copy yet", async () => {
    const s = await startCouple();
    // A kind that has no push copy yet.
    const kind = GAME_KINDS.find((item) => item !== "story_chain" && !GAME_PUSH_COPY[item])!;
    const sent = await s.a.as.mutation(api.games.send_game_invite, { p_kind: kind });
    expect(sent.sent_at).toBe(new Date(START).toISOString());
    const [row] = await outbox(s.t);
    expect(row).toMatchObject({
      recipient_user_id: s.b.userId,
      title: "Paeonia",
      body: "Open Paeonia to join in.",
      payload: { type: "game_invite", game_kind: kind, couple_id: s.couple.coupleId, route: "games", deeplink: gameDeepLink(kind) },
    });
    expect(row.payload).not.toHaveProperty("game_id");

    tick(14 * 60 + 59);
    expect((await failure(s.a.as.mutation(api.games.send_game_invite, { p_kind: kind }))).code).toBe("53300");
    // The limit is per sender and per kind.
    await s.b.as.mutation(api.games.send_game_invite, { p_kind: kind });
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "story_chain" });
    tick(1);
    expect((await s.a.as.mutation(api.games.send_game_invite, { p_kind: kind })).sent_at > sent.sent_at).toBe(true);
    expect((await s.t.run((ctx) => ctx.db.query("game_invites").collect())).map((invite) => invite.kind).sort()).toEqual([
      kind,
      kind,
      "story_chain",
    ].sort());
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the push payload carries the deep link of its kind", async () => {
    const s = await startCouple();
    for (const kind of GAME_KINDS) {
      await s.a.as.mutation(api.games.send_game_invite, { p_kind: kind });
      tick(1);
    }
    const links = Object.fromEntries(
      (await outbox(s.t)).map((row) => [(row.payload as { game_kind: string }).game_kind, (row.payload as { deeplink: string }).deeplink]),
    );
    expect(links).toEqual({
      draw_and_guess: "paeonia://games/draw-and-guess",
      mind_meld: "paeonia://games/mind-meld",
      exquisite_corpse: "paeonia://games/exquisite-corpse",
      story_chain: "paeonia://games/story-chain",
      connect_four: "paeonia://games/connect-four",
      dots_and_boxes: "paeonia://games/dots-and-boxes",
      ultimate_tic_tac_toe: "paeonia://games/ultimate-tic-tac-toe",
    });
    for (const kind of GAME_KINDS) expect(links[kind]).toBe(gameDeepLink(kind));
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("live ticket", () => {
  const decode = (ticket: string) => JSON.parse(atob(ticket.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")));

  test("carries the game channel and is signed for the relay", async () => {
    process.env.PAEONIA_LIVE_RELAY_URL = "wss://relay.example.test/canvas";
    process.env.PAEONIA_LIVE_RELAY_SECRET = "relay-secret";
    try {
      const s = await startCouple();
      const ticket = await s.a.as.mutation(api.games.create_game_live_ticket, { p_kind: "draw_and_guess" });
      expect(ticket!.url).toBe("wss://relay.example.test/canvas");
      expect(decode(ticket!.ticket)).toMatchObject({ c: s.couple.coupleId, u: s.a.userId, ch: "draw_and_guess" });
      const [payload, signature] = ticket!.ticket.split(".");
      expect(signature).toBe(await hmacSha256Hex("relay-secret", payload));
      expect(Date.parse(ticket!.expires_at)).toBe(Date.now() + 60_000);

      // The widget canvas ticket keeps working without a channel.
      const widget = await s.a.as.mutation(api.widget.create_widget_live_ticket, {});
      expect(decode(widget!.ticket)).not.toHaveProperty("ch");
    } finally {
      delete process.env.PAEONIA_LIVE_RELAY_URL;
      delete process.env.PAEONIA_LIVE_RELAY_SECRET;
    }
  });

  test("the channel is the game kind, for every kind", async () => {
    process.env.PAEONIA_LIVE_RELAY_URL = "wss://relay.example.test/canvas";
    process.env.PAEONIA_LIVE_RELAY_SECRET = "relay-secret";
    try {
      const s = await startCouple();
      for (const kind of GAME_KINDS) {
        const ticket = await s.a.as.mutation(api.games.create_game_live_ticket, { p_kind: kind });
        expect(decode(ticket!.ticket)).toMatchObject({ c: s.couple.coupleId, u: s.a.userId, ch: kind });
      }
    } finally {
      delete process.env.PAEONIA_LIVE_RELAY_URL;
      delete process.env.PAEONIA_LIVE_RELAY_SECRET;
    }
  });

  test("is null while the relay is not configured", async () => {
    const s = await startCouple();
    expect(await s.a.as.mutation(api.games.create_game_live_ticket, { p_kind: "draw_and_guess" })).toBeNull();
    expect(await s.a.as.mutation(api.games.create_game_live_ticket, { p_kind: "mind_meld" })).toBeNull();
  });
});

describe("registry", () => {
  const payload = (coupleId: string, kind: string) => ({ couple_id: coupleId, game_kind: kind, round_id: newUuid(), game_id: newUuid() });

  test("every kind has a registry entry, and each built game has a backend", () => {
    // Each built game adds its line here.
    expect(GAME_BACKENDS.draw_and_guess).not.toBeNull();
    expect(GAME_BACKENDS.mind_meld).not.toBeNull();
    expect(GAME_BACKENDS.story_chain).not.toBeNull();
    expect(Object.keys(GAME_BACKENDS)).toEqual([...GAME_KINDS]);
  });

  test("a game without a backend has out-of-date turn, result, and reminder pushes, and its invites stay wanted", async () => {
    const s = await startCouple();
    const wanted = (kind: Parameters<typeof gamePushStillWanted>[1], data: Record<string, unknown>) =>
      s.t.run((ctx) => gamePushStillWanted(ctx, kind, data, s.b.userId));
    const mindMeld = payload(s.couple.coupleId, "mind_meld");
    for (const kind of ["game_turn_ready", "game_result", "game_turn_reminder"] as const) {
      expect(await wanted(kind, mindMeld)).toEqual({ wanted: false, reason: "out_of_date" });
    }
    expect(await wanted("game_invite", mindMeld)).toEqual({ wanted: true });
    // A push that names no known game has nothing to wait for either.
    expect(await wanted("game_turn_ready", { ...mindMeld, game_kind: "chess" })).toEqual({ wanted: false, reason: "out_of_date" });
    expect(await wanted("game_turn_ready", { couple_id: s.couple.coupleId })).toEqual({ wanted: false, reason: "out_of_date" });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a push without a couple, or for a couple the recipient lost, is ineligible before any game is asked", async () => {
    const s = await startCouple();
    const entry = vi.fn<GameBackend["pushStillWanted"]>(async () => true);
    GAME_BACKENDS.mind_meld = { ...nullBackend, pushStillWanted: entry };
    try {
      const wanted = (data: Record<string, unknown>) => s.t.run((ctx) => gamePushStillWanted(ctx, "game_turn_ready", data, s.b.userId));
      expect(await wanted({ game_kind: "mind_meld" })).toEqual({ wanted: false, reason: "ineligible" });
      expect(await wanted(payload(s.couple.coupleId, "mind_meld"))).toEqual({ wanted: true });
      expect(entry).toHaveBeenCalledTimes(1);
      await endCouple(s.t, s.couple.coupleId, s.a.userId);
      expect(await s.t.run((ctx) => gamePushStillWanted(ctx, "game_invite", payload(s.couple.coupleId, "mind_meld"), s.a.userId))).toEqual({
        wanted: false,
        reason: "ineligible",
      });
      expect(entry).toHaveBeenCalledTimes(1);
    } finally {
      GAME_BACKENDS.mind_meld = null;
    }
  });

  test("the entry of the pushed game decides, with the push kind, the payload, and the recipient", async () => {
    const s = await startCouple();
    const entry = vi.fn<GameBackend["pushStillWanted"]>(async () => false);
    GAME_BACKENDS.mind_meld = { ...nullBackend, pushStillWanted: entry };
    try {
      const data = payload(s.couple.coupleId, "mind_meld");
      expect(await s.t.run((ctx) => gamePushStillWanted(ctx, "game_result", data, s.b.userId))).toEqual({ wanted: false, reason: "out_of_date" });
      expect(entry).toHaveBeenCalledWith(expect.anything(), "game_result", data, s.b.userId);
      // Another game's pushes never reach this entry.
      await s.t.run((ctx) => gamePushStillWanted(ctx, "game_result", payload(s.couple.coupleId, "connect_four"), s.b.userId));
      expect(entry).toHaveBeenCalledTimes(1);
    } finally {
      GAME_BACKENDS.mind_meld = null;
    }
  });

  test("the reminder cron sums the reminders of every game with turns", async () => {
    const s = await startCouple();
    const sendDueTurnReminders = vi.fn<NonNullable<GameBackend["sendDueTurnReminders"]>>(async () => 2);
    GAME_BACKENDS.mind_meld = { ...nullBackend, sendDueTurnReminders };
    GAME_BACKENDS.connect_four = { ...nullBackend, sendDueTurnReminders };
    try {
      expect(await s.t.mutation(internal.games.send_due_game_turn_reminders, {})).toBe(4);
      expect(sendDueTurnReminders).toHaveBeenCalledWith(expect.anything(), new Date().toISOString());
    } finally {
      GAME_BACKENDS.mind_meld = null;
      GAME_BACKENDS.connect_four = null;
    }
  });

  test("cleanup deletes the shared rows of every kind, then asks each game for its own", async () => {
    const s = await startCouple();
    const other = await createCouple(s.t);
    for (const user of [s.a, s.b, other.first]) {
      await user.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    }
    await s.a.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    await other.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "connect_four" });
    await s.b.as.mutation(api.games.send_game_invite, { p_kind: "story_chain" });
    const { game_id } = await s.a.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});
    expect(game_id).toBeDefined();
    await other.first.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});

    const deleteCoupleRows = vi.fn<GameBackend["deleteCoupleRows"]>(async () => 5);
    GAME_BACKENDS.mind_meld = { ...nullBackend, deleteCoupleRows };
    try {
      // 1 settings + 2 presence + 2 invites, 1 game and its used words from Draw & Guess, 5 from the fake entry.
      const usedWords = (await s.t.run((ctx) => ctx.db.query("game_used_words").collect())).filter((row) => row.couple_id === s.couple.coupleId);
      expect(usedWords).toHaveLength(3);
      expect(await s.t.run((ctx) => deleteCoupleGameRows(ctx, s.couple.coupleId))).toBe(1 + 2 + 2 + 1 + 3 + 5);
      expect(deleteCoupleRows).toHaveBeenCalledWith(expect.anything(), s.couple.coupleId);
    } finally {
      GAME_BACKENDS.mind_meld = null;
    }

    const left = await s.t.run(async (ctx) => ({
      settings: (await ctx.db.query("game_settings").collect()).map((row) => row.couple_id),
      presence: (await ctx.db.query("game_presence").collect()).map((row) => row.couple_id),
      invites: (await ctx.db.query("game_invites").collect()).map((row) => row.couple_id),
      games: (await ctx.db.query("games").collect()).map((row) => row.couple_id),
    }));
    // The other couple keeps everything.
    expect(left).toEqual({
      settings: [other.coupleId],
      presence: [other.coupleId],
      invites: [],
      games: [other.coupleId],
    });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
