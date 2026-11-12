import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
// Tests for what every game shares: settings, the overview, invites, presence, the relay ticket,
// and the registry that the shared code uses to reach a game. Draw & Guess has its own tests in
// drawAndGuess.test.ts.
import { api, components, internal } from "./_generated/api";
import { hmacSha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import { deleteCoupleGameRows, GAME_BACKENDS, gamePushStillWanted, type GameBackend } from "./lib/gameRegistry";
import { gameDeepLink } from "./lib/games";
import { gameRoom } from "./lib/presence";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { GAME_KINDS } from "./lib/validators";
import { endCouple, failure } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, transactionClock, transactionIso, transactionNow, type TestConvex } from "./test.setup";

const START = Date.parse("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(START));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

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
    expect((await failure(loner.as.mutation(api.games.mark_game_settings_seen, {}))).code).toBe("42501");
    for (const kind of GAME_KINDS) {
      expect((await failure(loner.as.mutation(api.games.send_game_invite, { p_kind: kind }))).code).toBe("42501");
      expect((await failure(loner.as.mutation(api.games.set_game_presence, { p_kind: kind, p_present: true }))).code).toBe("42501");
      expect((await failure(loner.as.mutation(api.games.create_game_live_ticket, { p_kind: kind }))).code).toBe("42501");
      expect((await failure(loner.as.mutation(api.games.hide_waiting_game, { p_kind: kind }))).code).toBe("42501");
    }
  });

  test("a couple without a subscription cannot use them either", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.query(api.games.get_games_overview, {}))).code).toBe("42501");
    expect((await failure(couple.first.as.mutation(api.games.send_game_invite, { p_kind: "mind_meld" }))).code).toBe("42501");
    expect((await failure(couple.first.as.mutation(api.games.mark_game_settings_seen, {}))).code).toBe("42501");
    expect((await failure(couple.first.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true }))).code).toBe("42501");
    expect((await failure(couple.first.as.mutation(api.games.hide_waiting_game, { p_kind: "mind_meld" }))).code).toBe("42501");
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

  test("whoever sets them has seen them, and the partner is seen once they say so", async () => {
    const s = await startCouple();
    expect((await failure(s.b.as.mutation(api.games.mark_game_settings_seen, {}))).code).toBe("23514");
    const set = await s.a.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    expect(set.seen_by_user_ids).toEqual([s.a.userId]);
    expect((await s.b.as.mutation(api.games.mark_game_settings_seen, {})).seen_by_user_ids).toEqual([s.a.userId, s.b.userId]);
    expect((await s.b.as.mutation(api.games.mark_game_settings_seen, {})).seen_by_user_ids).toEqual([s.a.userId, s.b.userId]);
    const changed = await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "nb" });
    expect(changed.seen_by_user_ids).toEqual([s.a.userId, s.b.userId]);
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
      hidden_kinds: [],
      play_days: { streak: 0, total: 0, today: "2026-10-10" },
    });
    expect((await s.b.as.query(api.games.get_games_overview, {})).partner_user_id).toBe(s.a.userId);
  });

  test("counts the couple days both partners had a game open, in a row and in total", async () => {
    const s = await startCouple();
    const open = (user: typeof s.a, kind: "ludo" | "mind_meld") =>
      user.as.mutation(api.games.set_game_presence, { p_kind: kind, p_present: true });
    const playDays = async () => (await s.b.as.query(api.games.get_games_overview, {})).play_days;
    const day = 86_400_000;

    // Day 1 both play, in different games. Day 2 only one partner plays, with many heartbeats.
    await open(s.a, "ludo");
    await open(s.b, "mind_meld");
    expect(await playDays()).toEqual({ streak: 1, total: 1, today: "2026-10-10" });
    vi.setSystemTime(new Date(START + day));
    await open(s.a, "ludo");
    tick(30);
    await open(s.a, "ludo");
    expect(await playDays()).toEqual({ streak: 1, total: 1, today: "2026-10-11" });
    // Day 3 both play, so the streak starts again at 1. On day 4 it holds until someone misses the day.
    vi.setSystemTime(new Date(START + 2 * day));
    await open(s.b, "ludo");
    await open(s.a, "mind_meld");
    vi.setSystemTime(new Date(START + 3 * day));
    expect(await playDays()).toEqual({ streak: 1, total: 2, today: "2026-10-13" });
    vi.setSystemTime(new Date(START + 4 * day));
    expect(await playDays()).toEqual({ streak: 0, total: 2, today: "2026-10-14" });

    const rows = await s.t.run((ctx) => ctx.db.query("game_play_days").collect());
    expect(rows.map((row) => [row.day, row.user_ids.length])).toEqual([
      ["2026-10-10", 2],
      ["2026-10-11", 1],
      ["2026-10-12", 2],
    ]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a play day is the couple day, which follows the partner whose clock is furthest behind", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "America/Los_Angeles"] });
    // 01:00 on 2026-10-11 in Oslo is still 16:00 on 2026-10-10 in Los Angeles.
    vi.setSystemTime(new Date("2026-10-10T23:00:00.000Z"));
    await couple.first.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: true });
    // 23:30 in Los Angeles, the same couple day, though Oslo's date moved on long ago.
    vi.setSystemTime(new Date("2026-10-11T06:30:00.000Z"));
    await couple.second.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: true });
    expect((await couple.first.as.query(api.games.get_games_overview, {})).play_days).toEqual({
      streak: 1,
      total: 1,
      today: "2026-10-10",
    });
    // At midnight in Los Angeles a new couple day starts, and the streak waits for it.
    vi.setSystemTime(new Date("2026-10-11T07:30:00.000Z"));
    expect((await couple.first.as.query(api.games.get_games_overview, {})).play_days).toEqual({
      streak: 1,
      total: 1,
      today: "2026-10-11",
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("returns the couple's settings once set", async () => {
    const s = await startCouple();
    const set = await s.a.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "nb" });
    expect((await s.b.as.query(api.games.get_games_overview, {})).settings).toEqual(set);
  });

  test("lists a kind while either partner has it open, once either partner opened it, or with an invite from the caller", async () => {
    const s = await startCouple();
    const opened = await transactionIso(s.t);
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "connect_four", p_present: true });
    const invited = await s.a.as.mutation(api.games.send_game_invite, { p_kind: "story_chain" });
    // A kind that was opened and closed again keeps its entry for the time it was played.
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "dots_and_boxes", p_present: true });
    tick(90);
    const closed = new Date(Date.now()).toISOString();
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "dots_and_boxes", p_present: false });

    // Entries follow the order of GAME_KINDS: mind_meld, story_chain, connect_four, dots_and_boxes.
    expect((await s.a.as.query(api.games.get_games_overview, {})).presence).toEqual([
      { kind: "mind_meld", my_present: true, partner_present: false, last_invite_at: null, last_played_at: opened },
      { kind: "story_chain", my_present: false, partner_present: false, last_invite_at: invited.sent_at, last_played_at: null },
      { kind: "connect_four", my_present: false, partner_present: true, last_invite_at: null, last_played_at: opened },
      { kind: "dots_and_boxes", my_present: false, partner_present: false, last_invite_at: null, last_played_at: closed },
    ]);
    // The partner's view swaps the two sides, the invite belongs to the sender only, and play times are shared.
    expect((await s.b.as.query(api.games.get_games_overview, {})).presence).toEqual([
      { kind: "mind_meld", my_present: false, partner_present: true, last_invite_at: null, last_played_at: opened },
      { kind: "connect_four", my_present: true, partner_present: false, last_invite_at: null, last_played_at: opened },
      { kind: "dots_and_boxes", my_present: false, partner_present: false, last_invite_at: null, last_played_at: closed },
    ]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an open screen moves the play time forward every 5 minutes, and closing it moves it at once", async () => {
    const s = await startCouple();
    const playedAt = async () => (await s.b.as.query(api.games.get_games_overview, {})).presence[0]?.last_played_at;
    const heartbeat = () => s.a.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: true });
    await heartbeat();
    const timestamp = await transactionClock(s.t);
    expect(await playedAt()).toBe(timestamp(new Date(START).toISOString()));

    tick(4 * 60 + 59);
    await heartbeat();
    expect(await playedAt()).toBe(timestamp(new Date(START).toISOString()));
    vi.setSystemTime(new Date(Date.parse(timestamp(START)) + 5 * 60_000));
    await heartbeat();
    expect(await playedAt()).toBe(new Date(Date.parse(timestamp(START)) + 5 * 60_000).toISOString());

    tick(30);
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: false });
    expect(await playedAt()).toBe(new Date(Date.parse(timestamp(START)) + 5 * 60_000 + 30_000).toISOString());
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
  test("each kind has its own presence, and a screen goes offline 60 seconds after its last heartbeat", async () => {
    // The presence component times sessions out with scheduled functions, so fake every timer.
    vi.useFakeTimers();
    const s = await startCouple();
    const partnerSees = async () =>
      (await s.b.as.query(api.games.get_games_overview, {})).presence.filter((entry) => entry.partner_present).map((entry) => entry.kind);
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    expect(await partnerSees()).toEqual(["draw_and_guess", "mind_meld"]);

    // Closing a screen ends it at once.
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: false });
    expect(await partnerSees()).toEqual(["mind_meld"]);

    // An app that stops sending heartbeats goes offline without a cron.
    const lastHeartbeat = Date.now();
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(Date.now() - lastHeartbeat).toBeGreaterThanOrEqual(60_000);
    expect(await partnerSees()).toEqual([]);
  });

  test("ending the relationship removes both partners' presence, and a former partner can no longer send or read it", async () => {
    const s = await startCouple();
    const other = await createCouple(s.t);
    for (const user of [s.a, s.b]) await user.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await other.first.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    const room = (coupleId: string) =>
      s.t.run((ctx) => ctx.runQuery(components.presence.public.listRoom, { roomId: gameRoom(coupleId, "mind_meld") }));
    expect(await room(s.couple.coupleId)).toHaveLength(2);

    await s.t.run((ctx) => endRelationshipForPair(ctx, s.couple.pairId, s.a.userId, "user_left"));
    expect(await room(s.couple.coupleId)).toEqual([]);
    expect((await room(other.coupleId)).map((row) => row.userId)).toEqual([other.first.userId]);
    for (const user of [s.a, s.b]) {
      expect((await failure(user.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true }))).code).toBe("42501");
      expect((await failure(user.as.query(api.games.get_games_overview, {}))).code).toBe("42501");
    }
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an open game screen does not silence an invite", async () => {
    const s = await startCouple();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "mind_meld" });
    expect(await outbox(s.t)).toHaveLength(1);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an invite for another kind is stored per kind and limited to one every 15 minutes", async () => {
    const s = await startCouple();
    const kind = "ultimate_tic_tac_toe";
    const sent = await s.a.as.mutation(api.games.send_game_invite, { p_kind: kind });
    const timestamp = await transactionClock(s.t);
    expect(sent.sent_at).toBe(timestamp(new Date(START).toISOString()));
    const [row] = await outbox(s.t);
    expect(row).toMatchObject({
      recipient_user_id: s.b.userId,
      payload: { type: "game_invite", game_kind: kind, couple_id: s.couple.coupleId, route: "games", deeplink: gameDeepLink(kind) },
    });
    expect(row.payload).not.toHaveProperty("game_id");

    tick(14 * 60 + 59);
    expect((await failure(s.a.as.mutation(api.games.send_game_invite, { p_kind: kind }))).code).toBe("53300");
    // The limit is per sender and per kind.
    await s.b.as.mutation(api.games.send_game_invite, { p_kind: kind });
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "story_chain" });
    vi.setSystemTime(new Date(Date.parse(sent.sent_at) + 15 * 60_000));
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
      ludo: "paeonia://games/ludo",
      consensio: "paeonia://games/consensio",
      piccante: "paeonia://games/piccante",
      guess_my_spot: "paeonia://games/guess-my-spot",
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
      expect(Date.parse(ticket!.expires_at)).toBe(await transactionNow(s.t) + 60_000);

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
    expect(GAME_BACKENDS.exquisite_corpse).not.toBeNull();
    expect(GAME_BACKENDS.connect_four).not.toBeNull();
    expect(GAME_BACKENDS.dots_and_boxes).not.toBeNull();
    expect(GAME_BACKENDS.ultimate_tic_tac_toe).not.toBeNull();
    expect(GAME_BACKENDS.ludo).not.toBeNull();
    expect(GAME_BACKENDS.piccante).not.toBeNull();
    expect(Object.keys(GAME_BACKENDS)).toEqual([...GAME_KINDS]);
  });

  test("a game without a backend has out-of-date game pushes, and only open invites stay wanted", async () => {
    const s = await startCouple();
    const wanted = (kind: Parameters<typeof gamePushStillWanted>[1], data: Record<string, unknown>) =>
      s.t.run((ctx) => gamePushStillWanted(ctx, kind, data, s.b.userId));
    const mindMeld = payload(s.couple.coupleId, "mind_meld");
    for (const kind of ["game_turn_ready", "game_result", "game_turn_reminder"] as const) {
      expect(await wanted(kind, mindMeld)).toEqual({ wanted: false, reason: "out_of_date" });
    }
    expect(await wanted("game_invite", mindMeld)).toEqual({ wanted: false, reason: "out_of_date" });
    const invite = await s.a.as.mutation(api.games.send_game_invite, { p_kind: "mind_meld" });
    expect(await wanted("game_invite", {
      ...mindMeld, actor_user_id: s.a.userId, invite_sent_at: invite.sent_at,
    })).toEqual({ wanted: true });
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
    // Stand-ins replace two entries and put back what was there, so a game that
    // registered its real backend keeps it.
    const saved = { mind_meld: GAME_BACKENDS.mind_meld, story_chain: GAME_BACKENDS.story_chain };
    GAME_BACKENDS.mind_meld = { ...nullBackend, sendDueTurnReminders };
    GAME_BACKENDS.story_chain = { ...nullBackend, sendDueTurnReminders };
    try {
      expect(await s.t.mutation(internal.gameHooks.send_due_game_turn_reminders, {})).toBe(4);
      expect(sendDueTurnReminders).toHaveBeenCalledWith(expect.anything(), await transactionIso(s.t));
    } finally {
      GAME_BACKENDS.mind_meld = saved.mind_meld;
      GAME_BACKENDS.story_chain = saved.story_chain;
    }
  });

  test("cleanup deletes the shared rows of every kind, then asks each game for its own", async () => {
    const s = await startCouple();
    const other = await createCouple(s.t);
    await s.a.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    await other.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "connect_four" });
    await s.b.as.mutation(api.games.send_game_invite, { p_kind: "story_chain" });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: true });
    await other.first.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: true });
    const { game_id } = await s.a.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});
    expect(game_id).toBeDefined();
    await other.first.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});

    const deleteCoupleRows = vi.fn<GameBackend["deleteCoupleRows"]>(async () => 5);
    GAME_BACKENDS.mind_meld = { ...nullBackend, deleteCoupleRows };
    try {
      // 1 settings + 2 invites + 1 play time + 1 play day, 1 game and its used words from Draw & Guess, 5 from the fake entry.
      const usedWords = (await s.t.run((ctx) => ctx.db.query("game_used_words").collect())).filter((row) => row.couple_id === s.couple.coupleId);
      expect(usedWords).toHaveLength(3);
      expect(await s.t.run((ctx) => deleteCoupleGameRows(ctx, s.couple.coupleId))).toBe(1 + 2 + 1 + 1 + 1 + 3 + 5);
      expect(deleteCoupleRows).toHaveBeenCalledWith(expect.anything(), s.couple.coupleId);
    } finally {
      GAME_BACKENDS.mind_meld = null;
    }

    const left = await s.t.run(async (ctx) => ({
      settings: (await ctx.db.query("game_settings").collect()).map((row) => row.couple_id),
      invites: (await ctx.db.query("game_invites").collect()).map((row) => row.couple_id),
      plays: (await ctx.db.query("game_plays").collect()).map((row) => row.couple_id),
      playDays: (await ctx.db.query("game_play_days").collect()).map((row) => row.couple_id),
      games: (await ctx.db.query("games").collect()).map((row) => row.couple_id),
    }));
    // The other couple keeps everything.
    expect(left).toEqual({
      settings: [other.coupleId],
      invites: [],
      plays: [other.coupleId],
      playDays: [other.coupleId],
      games: [other.coupleId],
    });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
