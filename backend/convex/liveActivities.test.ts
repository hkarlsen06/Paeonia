import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { ApnsSendRequest, ApnsSendResult } from "./lib/apns";
import type { GameKind } from "./lib/games";
import { newUuid } from "./lib/ids";
import { failure, op } from "./media.testing";
import { deliverDueLiveActivityPushes } from "./push.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

// Stands in for APNs. `push:send_push` imports `sendWithEnvironmentFallback` from lib/apns.
const send = vi.hoisted(() => vi.fn<(request: ApnsSendRequest) => Promise<ApnsSendResult>>());
vi.mock("./lib/apns", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./lib/apns")>()),
  sendWithEnvironmentFallback: (request: ApnsSendRequest) => send(request),
}));

const T0 = Date.parse("2026-11-10T12:00:00.000Z");
/** When the next run of the `check-game-activities` cron is due. Crons do not run in convex-test, so `elapse` runs it. */
let nextCheckAt = T0;

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(T0));
  nextCheckAt = T0 + 30_000;
  send.mockResolvedValue({ ok: true, providerMessageId: "apns-id", environment: "sandbox" });
});
afterEach(() => {
  vi.useRealTimers();
  send.mockReset();
});

const START_TOKEN = "a1".repeat(32);
const UPDATE_TOKEN = "b2".repeat(32);

/** `partner` opens the games, `viewer` gets the Live Activity on a phone with a push-to-start token. */
async function setup() {
  const t = newTest();
  const couple = await createCouple(t);
  const partner = couple.first;
  const viewer = couple.second;
  const installId = newUuid();
  await register(viewer, { p_install_id: installId, p_kind: "start", p_token: START_TOKEN });
  return { t, partner, viewer, installId, coupleId: couple.coupleId };
}

function register(user: TestUser, args: { p_install_id: string; p_kind: "start" | "update"; p_token: string; p_activity_id?: string }) {
  return user.as.mutation(api.liveActivities.register_live_activity_token, { p_apns_environment: "sandbox", p_locale: "en_US", ...args });
}

/** A phone of `user` ended activity `activityId` on its own and tells the server. */
const endedOnPhone = (user: TestUser, installId: string, activityId: string) =>
  user.as.mutation(api.liveActivities.end_game_live_activity, { p_activity_id: activityId, p_install_id: installId });

/** The phone's sign-in ended. Sent without a sign-in, as after a session that ended elsewhere. */
const endInstall = (t: TestConvex, installId: string) =>
  t.mutation(api.liveActivities.end_live_activity_install, { p_install_id: installId });

/** Runs what a mutation queued for right now, such as a push fan-out. convex-test runs `runAfter(0)` one millisecond later. */
async function runDueNow(t: TestConvex) {
  vi.advanceTimersByTime(1);
  await t.finishInProgressScheduledFunctions();
}

/** A game screen opens or sends its heartbeat (`true`), or closes (`false`). */
async function presence(t: TestConvex, user: TestUser, kind: GameKind, present: boolean) {
  await user.as.mutation(api.games.set_game_presence, { p_kind: kind, p_present: present });
  await runDueNow(t);
}

const activities = (t: TestConvex) => t.run((ctx) => ctx.db.query("game_live_activities").collect());
const viewerRow = async (t: TestConvex, viewer: TestUser) => (await activities(t)).find((row) => row.viewer_user_id === viewer.userId);
const tokens = (t: TestConvex) => t.run((ctx) => ctx.db.query("live_activity_tokens").collect());
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("live_activity_push_outbox").collect());
const queued = async (t: TestConvex, event: "start" | "update" | "end") => (await outbox(t)).filter((row) => row.event === event);

/**
 * Moves the clock in 5 second steps and runs what came due: presence timeouts, and the
 * `check-game-activities` cron every 30 seconds.
 */
async function elapse(t: TestConvex, ms: number, each?: () => Promise<void>) {
  for (let passed = 0; passed < ms; passed += 5_000) {
    vi.advanceTimersByTime(5_000);
    await t.finishInProgressScheduledFunctions();
    while (Date.now() >= nextCheckAt) {
      await t.mutation(internal.liveActivities.check_game_activities, {});
      await runDueNow(t);
      nextCheckAt += 30_000;
    }
    if (each) await each();
  }
}

/** The players keep their game screens open for `ms`, with the app's heartbeat every 30 seconds. */
async function keepPlaying(t: TestConvex, players: [TestUser, GameKind][], ms: number) {
  let sinceHeartbeat = 0;
  await elapse(t, ms, async () => {
    sinceHeartbeat += 5_000;
    if (sinceHeartbeat >= 30_000) {
      sinceHeartbeat = 0;
      for (const [user, kind] of players) await presence(t, user, kind, true);
    }
  });
}

/** Sends the due pushes through `push:send_push` and returns the `aps` of each APNs request it made. */
async function deliveredAps(t: TestConvex) {
  send.mockClear();
  await deliverDueLiveActivityPushes(t);
  return send.mock.calls.map(([request]) => ({ request, aps: JSON.parse(request.body).aps as Record<string, unknown> }));
}

/** The couple's Four in a Row game, made by `starter`, who moves first. */
async function fourInARow(t: TestConvex, starter: TestUser) {
  await starter.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "en" });
  return await starter.as.mutation(api.boardGames.ensure_board_game, { p_kind: "connect_four" });
}

/** `user` drops a piece in the first column, which passes the turn. */
async function dropPiece(t: TestConvex, user: TestUser, game: { id: string; version: number }) {
  const next = await user.as.mutation(api.boardGames.make_move, { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: 0 });
  await runDueNow(t);
  return next;
}

/** The viewer's phone got the start and registered the activity's update token. */
async function registerUpdateToken(t: TestConvex, viewer: TestUser, installId: string, token = UPDATE_TOKEN) {
  const activity = (await viewerRow(t, viewer))!;
  expect(await register(viewer, { p_install_id: installId, p_kind: "update", p_token: token, p_activity_id: activity.id })).toBe("playing");
  return activity;
}

describe("register_live_activity_token", () => {
  test("refuses a signed-out caller", async () => {
    const t = newTest();
    const result = t.mutation(api.liveActivities.register_live_activity_token, {
      p_install_id: newUuid(),
      p_kind: "start",
      p_token: START_TOKEN,
      p_apns_environment: "sandbox",
    });
    expect((await failure(result)).code).toBe("42501");
  });

  test("refuses an install that holds another account's tokens, and saves nothing", async () => {
    const { t, partner, installId } = await setup();
    expect(await register(partner, { p_install_id: installId, p_kind: "start", p_token: "c3".repeat(32) })).toBe("install_taken");
    expect((await tokens(t)).map((row) => row.token)).toEqual([START_TOKEN]);
  });

  test("refuses an update token for another viewer's activity, and saves nothing", async () => {
    const { t, partner, viewer } = await setup();
    await presence(t, partner, "mind_meld", true);
    const activity = (await viewerRow(t, viewer))!;
    expect(await register(partner, { p_install_id: newUuid(), p_kind: "update", p_token: UPDATE_TOKEN, p_activity_id: activity.id })).toBe("ended");
    expect((await tokens(t)).map((row) => row.kind)).toEqual(["start"]);
  });

  test("an activity the server no longer knows answers ended and keeps no token", async () => {
    const { t, viewer } = await setup();
    expect(await register(viewer, { p_install_id: newUuid(), p_kind: "update", p_token: UPDATE_TOKEN, p_activity_id: newUuid() })).toBe("ended");
    expect(await tokens(t)).toHaveLength(1);
  });

  test("a token that moved to another account leaves the old one", async () => {
    const { t, partner } = await setup();
    await register(partner, { p_install_id: newUuid(), p_kind: "start", p_token: START_TOKEN });
    expect((await tokens(t)).map((row) => row.user_id)).toEqual([partner.userId]);
  });

  test("a new push-to-start token replaces the install's old one", async () => {
    const { t, viewer, installId } = await setup();
    await register(viewer, { p_install_id: installId, p_kind: "start", p_token: "d4".repeat(32) });
    expect((await tokens(t)).map((row) => row.token)).toEqual(["d4".repeat(32)]);
  });

  test("an account keeps its five most recently registered start tokens", async () => {
    const { t, partner, viewer, installId } = await setup();
    const later = [];
    for (let phone = 0; phone < 6; phone++) {
      vi.advanceTimersByTime(1_000);
      const token = `${phone}`.repeat(64);
      later.push(token);
      await register(viewer, { p_install_id: newUuid(), p_kind: "start", p_token: token });
    }
    expect((await tokens(t)).map((row) => row.token).sort()).toEqual(later.slice(1).sort());
    expect((await tokens(t)).some((row) => row.install_id === installId)).toBe(false);

    await presence(t, partner, "mind_meld", true);
    expect(await queued(t, "start")).toHaveLength(5);
  });

  test("uses a rate limit", async () => {
    const { viewer, installId } = await setup();
    let refused: { code: string } | null = null;
    for (let call = 0; call < 100 && !refused; call++) {
      try {
        await register(viewer, { p_install_id: installId, p_kind: "start", p_token: START_TOKEN });
      } catch (error) {
        refused = (error as { data: { code: string } }).data;
      }
    }
    expect(refused?.code).toBe("53300");
  });
});

describe("end_live_activity_install", () => {
  test("needs no sign-in, and leaves the tokens of other installs", async () => {
    const { t, viewer, installId } = await setup();
    const otherInstall = newUuid();
    await register(viewer, { p_install_id: otherInstall, p_kind: "start", p_token: "e5".repeat(32) });
    await endInstall(t, installId);
    expect((await tokens(t)).map((row) => row.install_id)).toEqual([otherInstall]);
  });

  test("refuses an id that is not an install id", async () => {
    const { t } = await setup();
    expect((await failure(endInstall(t, "not-an-id"))).code).toBe("22P02");
    expect(await tokens(t)).toHaveLength(1);
  });

  test("a flood of made-up ids writes nothing and cannot block an honest end", async () => {
    const { t, partner, viewer, installId } = await setup();
    const rowsOf = () =>
      t.run(async (ctx) => {
        const counts: number[] = [];
        for (const table of ["live_activity_tokens", "live_activity_push_outbox", "game_live_activities"] as const) {
          counts.push((await ctx.db.query(table).collect()).length);
        }
        return counts;
      });
    const before = await rowsOf();
    for (let call = 0; call < 1_200; call++) {
      await endInstall(t, newUuid());
      if (call === 600) {
        // The viewer signs out in the middle of the flood.
        await endInstall(t, installId);
        expect((await tokens(t)).filter((row) => row.user_id === viewer.userId)).toHaveLength(0);
      }
    }
    expect(await rowsOf()).toEqual([before[0] - 1, before[1], before[2]]);

    await presence(t, partner, "mind_meld", true);
    expect(await queued(t, "start")).toHaveLength(0);
  });

  test("the second end removes a registration that was on its way during the sign-out", async () => {
    const { t, viewer, installId } = await setup();
    await endInstall(t, installId);
    await register(viewer, { p_install_id: installId, p_kind: "start", p_token: START_TOKEN });
    await endInstall(t, installId);
    expect(await tokens(t)).toHaveLength(0);
  });
});

describe("end_game_live_activity", () => {
  async function running() {
    const context = await setup();
    const { t, partner, viewer, installId } = context;
    await presence(t, partner, "mind_meld", true);
    const activity = await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);
    return { ...context, activity };
  }

  test("refuses a signed-out caller", async () => {
    const { t, installId, activity } = await running();
    const result = t.mutation(api.liveActivities.end_game_live_activity, { p_activity_id: activity.id, p_install_id: installId });
    expect((await failure(result)).code).toBe("42501");
    expect(await activities(t)).toEqual([expect.objectContaining({ id: activity.id })]);
  });

  test("changes nothing for an activity of another viewer", async () => {
    const { t, partner, installId, activity } = await running();
    await endedOnPhone(partner, installId, activity.id);
    await runDueNow(t);
    expect(await activities(t)).toEqual([expect.objectContaining({ id: activity.id })]);
    expect(await queued(t, "end")).toHaveLength(0);
  });

  test("the only phone that ended the activity on its own lets a new one start", async () => {
    const { t, partner, viewer, installId, activity } = await running();
    await endedOnPhone(viewer, installId, activity.id);
    await runDueNow(t);
    expect(await viewerRow(t, viewer)).toBeUndefined();

    await presence(t, partner, "mind_meld", true);
    expect((await viewerRow(t, viewer))!.id).not.toBe(activity.id);
  });

  test("a phone that ended its stale activity gets no more of its pushes, and the other phones keep it without a new alert", async () => {
    const { t, partner, viewer, installId, activity } = await running();
    const otherPhone = newUuid();
    await register(viewer, { p_install_id: otherPhone, p_kind: "start", p_token: "f6".repeat(32) });
    await register(viewer, { p_install_id: otherPhone, p_kind: "update", p_token: "f7".repeat(32), p_activity_id: activity.id });
    await deliveredAps(t);

    // The first phone's activity went stale and the app ended it on opening.
    await endedOnPhone(viewer, installId, activity.id);
    await runDueNow(t);
    expect(await deliveredAps(t)).toEqual([]);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);
    expect(await viewerRow(t, viewer)).toMatchObject({ id: activity.id });
    expect(await queued(t, "start")).toHaveLength(1);

    await presence(t, partner, "mind_meld", false);
    await presence(t, partner, "draw_and_guess", true);
    const sent = await deliveredAps(t);
    expect(sent.map(({ request, aps }) => [request.token, aps.event])).toEqual([["f7".repeat(32), "update"]]);
  });

  test("a phone that missed a switch and opened the old game gets the game the partner is in now", async () => {
    const { t, partner, viewer, installId, activity } = await running();
    // The update naming Draw & Guess never reached the phone.
    await presence(t, partner, "mind_meld", false);
    await presence(t, partner, "draw_and_guess", true);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("live_activity_push_outbox").collect()) await ctx.db.delete(row._id);
    });
    // The viewer taps the activity, which still says Mind Meld. The phone ends it and opens the game.
    await endedOnPhone(viewer, installId, activity.id);
    await presence(t, viewer, "mind_meld", true);
    await keepPlaying(t, [[partner, "draw_and_guess"], [viewer, "mind_meld"]], 30_000);

    const [start] = await queued(t, "start");
    expect(start).toMatchObject({ game_kind: "draw_and_guess" });
    expect(start.activity_id).not.toBe(activity.id);
  });
});

describe("one phone, several sign-ins", () => {
  test("signing in again after a sign-out whose end never arrived keeps one start token", async () => {
    const { t, partner, viewer } = await setup();
    // The old install's end failed, and the same account signs in with a new install.
    await register(viewer, { p_install_id: newUuid(), p_kind: "start", p_token: START_TOKEN });
    expect((await tokens(t)).filter((row) => row.kind === "start")).toHaveLength(1);

    await presence(t, partner, "mind_meld", true);
    expect(await queued(t, "start")).toHaveLength(1);
  });

  test("the old install's end that arrives after the new sign-in leaves the new install's token", async () => {
    const { t, viewer, installId } = await setup();
    const newInstall = newUuid();
    await register(viewer, { p_install_id: newInstall, p_kind: "start", p_token: "f6".repeat(32) });
    await endInstall(t, installId);
    expect((await tokens(t)).map((row) => row.install_id)).toEqual([newInstall]);
  });

  test("a new account on the phone gets its partner's games and never the old account's", async () => {
    const { t, partner: oldPartner } = await setup();
    const next = await createCouple(t);
    // The old account's session ended elsewhere, so the phone could not end its install yet.
    await register(next.second, { p_install_id: newUuid(), p_kind: "start", p_token: START_TOKEN });

    await presence(t, oldPartner, "mind_meld", true);
    await presence(t, next.first, "piccante", true);
    const starts = await queued(t, "start");
    expect(starts.map((row) => row.recipient_user_id)).toEqual([next.second.userId]);
    const [sent] = await deliveredAps(t);
    expect(sent.request.token).toBe(START_TOKEN);
    expect(sent.aps).toMatchObject({ "content-state": { gameKind: "piccante" } });
  });
});

describe("the partner in a game", () => {
  test("the first heartbeat starts the activity and queues one start push at once, naming the partner and the game", async () => {
    const { t, partner, viewer } = await setup();
    await partner.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    const activity = (await viewerRow(t, viewer))!;
    expect(activity).toMatchObject({ viewer_user_id: viewer.userId, partner_user_id: partner.userId, game_kind: "mind_meld", turn: "none" });

    await runDueNow(t);
    const starts = await queued(t, "start");
    expect(starts).toHaveLength(1);
    expect(starts[0]).toMatchObject({ recipient_user_id: viewer.userId, activity_id: activity.id });

    const [sent] = await deliveredAps(t);
    expect(sent.request).toMatchObject({ token: START_TOKEN, topic: "no.paeonia.app.push-type.liveactivity", pushType: "liveactivity" });
    expect(sent.aps).toMatchObject({
      event: "start",
      "attributes-type": "GameLiveActivityAttributes",
      attributes: { activityID: activity.id, partnerName: "First" },
      "content-state": { gameKind: "mind_meld", phase: "playing", turn: "none" },
      alert: { title: "First is playing Mind Meld", body: "Tap to join." },
      "input-push-token": 1,
    });

    // Later heartbeats in the same game change nothing.
    await presence(t, partner, "mind_meld", true);
    expect(await outbox(t)).toHaveLength(1);
  });

  test("starts none for a viewer who has the game open, and starts one at the partner's next heartbeat after they leave", async () => {
    const { t, partner, viewer } = await setup();
    await presence(t, viewer, "mind_meld", true);
    await keepPlaying(t, [[partner, "mind_meld"], [viewer, "mind_meld"]], 60_000);
    expect(await outbox(t)).toHaveLength(0);
    expect(await activities(t)).toHaveLength(0);

    await presence(t, viewer, "mind_meld", false);
    await presence(t, partner, "mind_meld", true);
    expect(await queued(t, "start")).toHaveLength(1);
  });

  test("the activity stays when the viewer opens the game, and changes go quietly while they play", async () => {
    const { t, partner, viewer, installId } = await setup();
    const game = await fourInARow(t, partner);
    await presence(t, partner, "connect_four", true);
    const activity = await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);

    await presence(t, viewer, "connect_four", true);
    await keepPlaying(t, [[partner, "connect_four"], [viewer, "connect_four"]], 60_000);
    expect(await queued(t, "end")).toHaveLength(0);
    expect(await viewerRow(t, viewer)).toMatchObject({ id: activity.id, turn: "theirs" });

    await dropPiece(t, partner, game);
    const [update] = await deliveredAps(t);
    expect(update.request.priority).toBe("5");
    expect(update.aps).toMatchObject({ event: "update", "content-state": { gameKind: "connect_four", turn: "yours" } });
  });

  test("a viewer with game pushes off gets none until they turn them on", async () => {
    const { t, partner, viewer } = await setup();
    await viewer.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    await presence(t, partner, "mind_meld", true);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);
    expect(await outbox(t)).toHaveLength(0);

    await viewer.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: true });
    await presence(t, partner, "mind_meld", true);
    expect(await queued(t, "start")).toHaveLength(1);
  });

  test("a switch of game queues one update push to the same activity and no start", async () => {
    const { t, partner, viewer, installId } = await setup();
    await presence(t, partner, "mind_meld", true);
    const activity = await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);
    const updatesBefore = (await queued(t, "update")).length;

    await presence(t, partner, "mind_meld", false);
    await presence(t, partner, "draw_and_guess", true);

    expect(await activities(t)).toEqual([expect.objectContaining({ id: activity.id, game_kind: "draw_and_guess" })]);
    expect(await queued(t, "start")).toHaveLength(1);
    expect(await queued(t, "update")).toHaveLength(updatesBefore + 1);
    const sent = (await deliveredAps(t)).at(-1)!;
    expect(sent.request.token).toBe(UPDATE_TOKEN);
    expect(sent.aps).toMatchObject({ event: "update", "content-state": { gameKind: "draw_and_guess", phase: "playing", turn: "none" } });
  });

  test("an update token that registers late gets the current state", async () => {
    const { t, partner, viewer, installId } = await setup();
    await presence(t, partner, "mind_meld", true);
    await presence(t, partner, "draw_and_guess", true);
    expect(await queued(t, "update")).toHaveLength(0);

    const activity = await registerUpdateToken(t, viewer, installId);
    const updates = await queued(t, "update");
    expect(updates).toHaveLength(1);
    expect(updates[0]).toMatchObject({ activity_id: activity.id, game_kind: "draw_and_guess" });
  });

  test("a partner who returns within the grace time keeps the activity, and the stored row forgets the close", async () => {
    const { t, partner, viewer } = await setup();
    await presence(t, partner, "mind_meld", true);
    await presence(t, partner, "mind_meld", false);
    await elapse(t, 30_000);
    await presence(t, partner, "mind_meld", true);
    await keepPlaying(t, [[partner, "mind_meld"]], 3 * 60_000);

    expect(await queued(t, "end")).toHaveLength(0);
    expect("ends_at" in (await viewerRow(t, viewer))!).toBe(false);
  });

  test("a partner who closes a game with no turn gets one end push between one and two minutes after the close", async () => {
    const { t, partner, viewer, installId } = await setup();
    await presence(t, partner, "mind_meld", true);
    await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);

    await presence(t, partner, "mind_meld", false);
    const leftAt = Date.now();
    await elapse(t, 3 * 60_000);

    const ends = await queued(t, "end");
    expect(ends).toHaveLength(1);
    expect(Date.parse(ends[0].created_at) - leftAt).toBeGreaterThanOrEqual(60_000);
    expect(Date.parse(ends[0].created_at) - leftAt).toBeLessThanOrEqual(120_000);
    expect(await activities(t)).toHaveLength(0);

    const [sent] = await deliveredAps(t);
    expect(sent.request.token).toBe(UPDATE_TOKEN);
    expect(sent.aps).toMatchObject({ event: "end", "content-state": { gameKind: "mind_meld", phase: "ended", turn: "none" } });
    expect(typeof sent.aps["dismissal-date"]).toBe("number");
    expect((await tokens(t)).map((row) => row.kind)).toEqual(["start"]);
  });

  test("a partner whose app was killed gets one end push two to three minutes after its last heartbeat", async () => {
    const { t, partner, viewer, installId } = await setup();
    await presence(t, partner, "mind_meld", true);
    await registerUpdateToken(t, viewer, installId);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);
    const lastHeartbeat = Date.now();

    // No close arrives. Presence times the screen out on its own.
    await elapse(t, 4 * 60_000);

    const ends = await queued(t, "end");
    expect(ends).toHaveLength(1);
    expect(Date.parse(ends[0].created_at) - lastHeartbeat).toBeGreaterThanOrEqual(120_000);
    expect(Date.parse(ends[0].created_at) - lastHeartbeat).toBeLessThanOrEqual(180_000);
  });

  test("a connection that drops 25 seconds after a heartbeat and comes back 55 seconds later keeps the same activity", async () => {
    const { t, partner, viewer, installId } = await setup();
    await presence(t, partner, "mind_meld", true);
    const first = await registerUpdateToken(t, viewer, installId);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);

    // The last heartbeat got through. The phone drops 25 seconds later and is back 55 seconds after that.
    await elapse(t, 80_000);
    await presence(t, partner, "mind_meld", true);
    await keepPlaying(t, [[partner, "mind_meld"]], 3 * 60_000);

    expect(await queued(t, "end")).toHaveLength(0);
    expect(await queued(t, "start")).toHaveLength(1);
    expect((await viewerRow(t, viewer))!).toMatchObject({ id: first.id });
  });

  test("the next session after an end starts a new activity", async () => {
    const { t, partner } = await setup();
    await presence(t, partner, "mind_meld", true);
    const [first] = await activities(t);
    await presence(t, partner, "mind_meld", false);
    await elapse(t, 2 * 60_000);
    await presence(t, partner, "piccante", true);

    const rows = await activities(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ game_kind: "piccante" });
    expect(rows[0].id).not.toBe(first.id);
    expect(await queued(t, "start")).toHaveLength(2);
  });

  test("a scheduled job that was lost leaves no activity running for good", async () => {
    const { t, partner } = await setup();
    await presence(t, partner, "mind_meld", true);
    const [first] = await activities(t);
    await t.run(async (ctx) => {
      for (const job of await ctx.db.system.query("_scheduled_functions").collect()) {
        if (job.state.kind === "pending" && job.name.includes("liveActivities")) await ctx.scheduler.cancel(job._id);
      }
    });
    await presence(t, partner, "mind_meld", false);
    await elapse(t, 60 * 60_000);
    await presence(t, partner, "piccante", true);

    const [row] = await activities(t);
    expect(row).toMatchObject({ game_kind: "piccante" });
    expect(row.id).not.toBe(first.id);
    expect(await queued(t, "start")).toHaveLength(2);
  });
});

describe("whose turn it is", () => {
  test("a turn-based game starts an activity that tells the viewer it is their turn", async () => {
    const { t, partner, viewer } = await setup();
    await fourInARow(t, viewer);
    await presence(t, partner, "connect_four", true);

    const [sent] = await deliveredAps(t);
    expect(sent.aps).toMatchObject({
      event: "start",
      "content-state": { gameKind: "connect_four", phase: "playing", turn: "yours" },
      alert: { title: "First is playing Four in a Row", body: "It's your turn." },
    });
  });

  test("a move that passes the turn sends one update with the new turn, which alerts the viewer", async () => {
    const { t, partner, viewer, installId } = await setup();
    const game = await fourInARow(t, partner);
    await presence(t, partner, "connect_four", true);
    await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);
    expect(await viewerRow(t, viewer)).toMatchObject({ turn: "theirs" });

    await dropPiece(t, partner, game);
    const sent = await deliveredAps(t);
    expect(sent.map(({ request, aps }) => [request.priority, aps.event, aps["content-state"], aps.alert])).toEqual([
      [
        "10",
        "update",
        { gameKind: "connect_four", phase: "playing", turn: "yours" },
        { title: "First is playing Four in a Row", body: "It's your turn." },
      ],
    ]);
    await keepPlaying(t, [[partner, "connect_four"]], 60_000);
    expect(await deliveredAps(t)).toEqual([]);
  });

  test("a turn that changed without a push, such as a result someone saw, is corrected at the next check", async () => {
    const { t, partner, viewer, installId } = await setup();
    await fourInARow(t, viewer);
    await presence(t, partner, "connect_four", true);
    await registerUpdateToken(t, viewer, installId);
    await presence(t, partner, "connect_four", false);
    await deliveredAps(t);
    const row = (await viewerRow(t, viewer))!;
    await t.run((ctx) => ctx.db.patch(row._id, { turn: "theirs" }));

    await elapse(t, 30_000);
    expect((await deliveredAps(t)).map(({ aps }) => aps["content-state"])).toEqual([
      { gameKind: "connect_four", phase: "playing", turn: "yours" },
    ]);
  });

  test("a close with a turn left ends the activity ten minutes later, and it never goes stale before that", async () => {
    const { t, partner, viewer, installId } = await setup();
    await fourInARow(t, viewer);
    await presence(t, partner, "connect_four", true);
    await registerUpdateToken(t, viewer, installId);
    await keepPlaying(t, [[partner, "connect_four"]], 5 * 60_000);
    await deliveredAps(t);

    await presence(t, partner, "connect_four", false);
    const leftAt = Date.now();
    await elapse(t, 9 * 60_000);
    expect(await queued(t, "end")).toHaveLength(0);
    // The last push before the close was 5 minutes earlier, and a refresh came during the wait.
    expect(await queued(t, "update")).toEqual(expect.arrayContaining([expect.objectContaining({ delivery: "quiet" })]));

    await elapse(t, 2 * 60_000);
    const ends = await queued(t, "end");
    expect(ends).toHaveLength(1);
    expect(Date.parse(ends[0].created_at) - leftAt).toBeGreaterThanOrEqual(10 * 60_000);
    expect(Date.parse(ends[0].created_at) - leftAt).toBeLessThanOrEqual(10 * 60_000 + 30_000);
  });
});

describe("the couple is together", () => {
  let sequence = 0;
  const operation = () => ({
    p_client_operation_id: newUuid(),
    p_client_id: "00000000-0000-0000-0000-00000000e301",
    p_client_sequence: ++sequence,
    p_local_created_at: new Date().toISOString(),
  });
  const saveVisit = (user: TestUser, start: string, end: string) =>
    user.as.mutation(api.visits.save_visit, { p_visit_id: newUuid(), p_start_date: start, p_end_date: end, p_place: null, ...operation() });

  /** Both partners share their location and send a fix from the same place, which notes today as a together day. */
  async function meet(users: TestUser[], coupleId: string) {
    for (const user of users) {
      await user.as.mutation(api.location.update_location_sharing_preference, {
        p_couple_id: coupleId,
        p_is_enabled: true,
        p_consent_version: "test-v1",
        p_source: "settings_toggle",
        ...operation(),
      });
    }
    for (const user of users) {
      await user.as.mutation(api.location.update_latest_partner_location, {
        p_couple_id: coupleId,
        p_latitude: 59.9,
        p_longitude: 10.75,
        p_accuracy_m: 20,
        p_captured_at: new Date(Date.now() - 60_000).toISOString(),
        p_source: "foreground_open",
        ...operation(),
      });
    }
  }

  test("starts none during a visit that covers today", async () => {
    const { t, partner, viewer } = await setup();
    await saveVisit(partner, "2026-11-10", "2026-11-12");
    await presence(t, partner, "mind_meld", true);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);
    expect(await outbox(t)).toHaveLength(0);
    expect(await viewerRow(t, viewer)).toBeUndefined();
  });

  test("starts none on a day location showed them together", async () => {
    const { t, partner, viewer, coupleId } = await setup();
    await meet([partner, viewer], coupleId);
    await presence(t, partner, "mind_meld", true);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);
    expect(await outbox(t)).toHaveLength(0);
    expect(await viewerRow(t, viewer)).toBeUndefined();
  });

  test("a visit that ended yesterday starts the activity as usual", async () => {
    const { t, partner } = await setup();
    vi.setSystemTime(new Date("2026-11-08T12:00:00.000Z"));
    await saveVisit(partner, "2026-11-08", "2026-11-09");
    vi.setSystemTime(new Date(T0));
    await presence(t, partner, "mind_meld", true);
    expect(await queued(t, "start")).toHaveLength(1);
  });

  test("a partner who plays on past the end of a together day starts the activity at their next heartbeat", async () => {
    const { t, partner, viewer } = await setup();
    await saveVisit(partner, "2026-11-10", "2026-11-10");
    vi.setSystemTime(new Date("2026-11-10T23:58:00.000Z"));
    nextCheckAt = Date.now() + 30_000;
    await presence(t, partner, "mind_meld", true);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);
    expect(await outbox(t)).toHaveLength(0);

    await keepPlaying(t, [[partner, "mind_meld"]], 2 * 60_000);
    const [start] = await queued(t, "start");
    expect(Date.parse(start.created_at)).toBeGreaterThanOrEqual(Date.parse("2026-11-11T00:00:00.000Z"));
    expect(Date.parse(start.created_at)).toBeLessThan(Date.parse("2026-11-11T00:00:30.000Z"));
    expect(await viewerRow(t, viewer)).toBeDefined();
  });

  test("an activity that runs when the couple becomes together keeps running and follows the partner to another game", async () => {
    const { t, partner, viewer, installId, coupleId } = await setup();
    await presence(t, partner, "mind_meld", true);
    const activity = await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);

    await meet([partner, viewer], coupleId);
    await keepPlaying(t, [[partner, "mind_meld"]], 60_000);
    await presence(t, partner, "mind_meld", false);
    await presence(t, partner, "draw_and_guess", true);

    expect(await viewerRow(t, viewer)).toMatchObject({ id: activity.id, game_kind: "draw_and_guess" });
    expect(await queued(t, "end")).toHaveLength(0);
  });
});

describe("turning game pushes off", () => {
  test("ends a running activity on the phone, and nothing starts until they are on again", async () => {
    const { t, partner, viewer, installId } = await setup();
    await presence(t, partner, "mind_meld", true);
    await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);

    await viewer.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    await runDueNow(t);
    const [end] = await deliveredAps(t);
    expect(end).toMatchObject({ request: { token: UPDATE_TOKEN }, aps: { event: "end" } });
    expect(await viewerRow(t, viewer)).toBeUndefined();

    await keepPlaying(t, [[partner, "mind_meld"]], 2 * 60_000);
    expect(await queued(t, "start")).toHaveLength(1);

    await viewer.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: true });
    await presence(t, partner, "mind_meld", true);
    expect(await queued(t, "start")).toHaveLength(2);
  });
});

describe("the couple ends while an activity runs", () => {
  async function running() {
    const context = await setup();
    const { t, partner, viewer, installId } = context;
    await presence(t, partner, "mind_meld", true);
    await registerUpdateToken(t, viewer, installId);
    await deliveredAps(t);
    return context;
  }
  const clientOperation = () => ({
    p_client_operation_id: newUuid(),
    p_client_id: newUuid(),
    p_client_sequence: 1,
    p_local_created_at: new Date().toISOString(),
  });

  test("leaving ends the activity on the viewer's phone and leaves no row and no activity token", async () => {
    const { t, viewer } = await running();
    await viewer.as.mutation(api.relationship.leave_relationship, clientOperation());
    await runDueNow(t);

    expect(await activities(t)).toHaveLength(0);
    const [end] = await deliveredAps(t);
    expect(end).toMatchObject({ request: { token: UPDATE_TOKEN }, aps: { event: "end" } });
    expect((await tokens(t)).map((row) => row.kind)).toEqual(["start"]);
  });

  test("the viewer deleting their account ends the activity on each of their phones, and keeps no token", async () => {
    const { t, viewer } = await running();
    const activity = (await viewerRow(t, viewer))!;
    const otherPhone = newUuid();
    await register(viewer, { p_install_id: otherPhone, p_kind: "start", p_token: "c3".repeat(32) });
    await register(viewer, { p_install_id: otherPhone, p_kind: "update", p_token: "d4".repeat(32), p_activity_id: activity.id });
    await deliveredAps(t);

    await viewer.as.mutation(api.identity.request_account_deletion, {});
    await runDueNow(t);

    const ends = (await deliveredAps(t)).filter(({ aps }) => aps.event === "end");
    expect(ends.map(({ request }) => request.token).sort()).toEqual([UPDATE_TOKEN, "d4".repeat(32)].sort());
    expect(await tokens(t)).toEqual([]);
  });

  test("a switch of game just before the couple ends queues no update after the end", async () => {
    const { t, partner, viewer } = await running();
    const updatesBefore = (await queued(t, "update")).length;
    // The heartbeat schedules the update, and the leave runs before it does.
    await partner.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    await viewer.as.mutation(api.relationship.leave_relationship, clientOperation());
    await runDueNow(t);

    expect(await queued(t, "end")).toHaveLength(1);
    expect(await queued(t, "update")).toHaveLength(updatesBefore);
  });

  test("the partner deleting their account ends the activity on the viewer's phone", async () => {
    const { t, partner } = await running();
    await partner.as.mutation(api.identity.request_account_deletion, {});
    await runDueNow(t);

    expect(await activities(t)).toHaveLength(0);
    const ends = (await deliveredAps(t)).filter(({ aps }) => aps.event === "end");
    expect(ends.map(({ request }) => request.token)).toEqual([UPDATE_TOKEN]);
  });
});

test("another account in the couple's place sees nothing of it", async () => {
  const t = newTest();
  const stranger = await createSignedInUser(t, { name: "Stranger" });
  await register(stranger, { p_install_id: newUuid(), p_kind: "start", p_token: START_TOKEN });
  const couple = await createCouple(t);
  await presence(t, couple.first, "mind_meld", true);
  expect((await outbox(t)).map((row) => row.recipient_user_id)).not.toContain(stranger.userId);
});
