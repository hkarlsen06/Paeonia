import { describe, expect, test } from "vitest";
import { buildLiveActivityRequest, type PreparedLiveActivityPush } from "./apns";
import {
  GAME_ACTIVITY_END_DELAY_MS,
  GAME_ACTIVITY_REFRESH_MS,
  type GameActivityEvent,
  type GameActivityState,
  type GameTurn,
  type LiveActivityDelivery,
  nextGameActivity,
} from "./liveActivities";
import type { GameKind } from "./games";

const T0 = "2026-11-10T12:00:00.000Z";
const at = (ms: number) => new Date(Date.parse(T0) + ms).toISOString();

const running: GameActivityState = { id: "activity-1", game_kind: "mind_meld", turn: "none", pushed_at: T0 };
const ending = (row: GameActivityState, endsAt = at(60_000)): GameActivityState => ({ ...row, ends_at: endsAt });

const heartbeat = (game_kind: GameKind = "mind_meld", turn: GameTurn = "none", viewer_present = false): GameActivityEvent => ({
  kind: "heartbeat",
  game_kind,
  turn,
  viewer_present,
  at: at(30_000),
});
const turn = (value: GameTurn, viewer_present = false, moved = false): GameActivityEvent => ({
  kind: "turn",
  turn: value,
  viewer_present,
  moved,
  at: at(30_000),
});
const left = (game_kind: GameKind, ms: number): GameActivityEvent => ({ kind: "left", game_kind, at: at(ms) });
const check = (partner_present: boolean, ms: number): GameActivityEvent => ({ kind: "check", partner_present, at: at(ms) });
const push = (
  event: "start" | "update" | "end",
  game_kind: GameKind = "mind_meld",
  delivery: LiveActivityDelivery = "now",
  activity_id = "activity-1",
) => ({
  event,
  delivery,
  activity_id,
  game_kind,
});

describe("nextGameActivity", () => {
  describe("a start", () => {
    test("stores the activity with its game and turn, and queues one start push", () => {
      expect(nextGameActivity(null, { kind: "start", id: "activity-2", game_kind: "connect_four", turn: "yours", at: at(30_000) })).toEqual({
        row: { id: "activity-2", game_kind: "connect_four", turn: "yours", pushed_at: at(30_000) },
        push: push("start", "connect_four", "alert", "activity-2"),
      });
    });

    test("changes nothing while an activity runs", () => {
      expect(nextGameActivity(running, { kind: "start", id: "activity-2", game_kind: "mind_meld", turn: "none", at: at(30_000) })).toBeNull();
    });
  });

  describe("the partner's heartbeat", () => {
    test("changes nothing in the same game and turn", () => {
      expect(nextGameActivity(running, heartbeat())).toBeNull();
    });

    test("moves the activity to another game or turn with one update, which alerts for another game", () => {
      expect(nextGameActivity(running, heartbeat("draw_and_guess"))).toEqual({
        row: { ...running, game_kind: "draw_and_guess", pushed_at: at(30_000) },
        push: push("update", "draw_and_guess", "alert"),
      });
      expect(nextGameActivity(running, heartbeat("mind_meld", "theirs"))).toEqual({
        row: { ...running, turn: "theirs", pushed_at: at(30_000) },
        push: push("update"),
      });
    });

    test("sends the update quietly while the viewer has that game open", () => {
      expect(nextGameActivity(running, heartbeat("connect_four", "yours", true))?.push).toEqual(push("update", "connect_four", "quiet"));
    });

    test("clears the end of a partner who came back in time, with an update only when something changed", () => {
      expect(nextGameActivity(ending(running), heartbeat())).toEqual({ row: running, push: null });
      expect(nextGameActivity(ending(running), heartbeat("piccante"))).toEqual({
        row: { ...running, game_kind: "piccante", pushed_at: at(30_000) },
        push: push("update", "piccante", "alert"),
      });
    });
  });

  describe("the turn read again", () => {
    test("sends one update when it changed, quietly while the viewer has the game open", () => {
      expect(nextGameActivity(running, turn("none"))).toBeNull();
      expect(nextGameActivity(running, turn("theirs"))).toEqual({ row: { ...running, turn: "theirs", pushed_at: at(30_000) }, push: push("update") });
      expect(nextGameActivity(running, turn("theirs", true))?.push).toEqual(push("update", "mind_meld", "quiet"));
    });

    test("rings for a move that waits for the viewer, even when the turn was theirs already", () => {
      const waiting = { ...running, turn: "yours" as const };
      expect(nextGameActivity(running, turn("yours", false, true))?.push).toEqual(push("update", "mind_meld", "ring"));
      expect(nextGameActivity(waiting, turn("yours", false, true))).toEqual({
        row: { ...waiting, pushed_at: at(30_000) },
        push: push("update", "mind_meld", "ring"),
      });
      expect(nextGameActivity(waiting, turn("yours", true, true))).toBeNull();
      expect(nextGameActivity(running, turn("theirs", false, true))?.push).toEqual(push("update"));
    });

    test("alerts when the turn became the viewer's with no move, unless they have the game open", () => {
      expect(nextGameActivity(running, turn("yours"))?.push).toEqual(push("update", "mind_meld", "alert"));
      expect(nextGameActivity(running, turn("yours", true))?.push).toEqual(push("update", "mind_meld", "quiet"));
      expect(nextGameActivity({ ...running, turn: "yours" }, turn("none"))?.push).toEqual(push("update"));
    });

    test("brings the end closer once no turn is left, and never moves it later", () => {
      const waiting = ending({ ...running, turn: "yours" }, at(10 * 60_000));
      expect(nextGameActivity(waiting, turn("none"))?.row).toEqual({
        ...running,
        ends_at: at(30_000 + GAME_ACTIVITY_END_DELAY_MS.none),
        pushed_at: at(30_000),
      });
      expect(nextGameActivity(ending(running, at(40_000)), turn("theirs"))?.row).toEqual({
        ...running,
        turn: "theirs",
        ends_at: at(40_000),
        pushed_at: at(30_000),
      });
    });

    test("changes nothing with no activity", () => {
      expect(nextGameActivity(null, turn("yours"))).toBeNull();
    });
  });

  describe("the partner closing a game screen", () => {
    test("sets the end a minute after the close with no turn, and ten minutes after with one", () => {
      expect(nextGameActivity(running, left("mind_meld", 10_000))).toEqual({ row: ending(running, at(70_000)), push: null });
      for (const value of ["yours", "theirs"] as const) {
        const row = { ...running, turn: value };
        expect(nextGameActivity(row, left("mind_meld", 10_000))).toEqual({ row: ending(row, at(10_000 + 10 * 60_000)), push: null });
      }
    });

    test("keeps an earlier end, and changes nothing for another game", () => {
      expect(nextGameActivity(ending(running, at(20_000)), left("mind_meld", 10_000))).toBeNull();
      expect(nextGameActivity(running, left("piccante", 10_000))).toBeNull();
    });
  });

  describe("a check that finds the partner in a game", () => {
    test("changes nothing soon after the last push", () => {
      expect(nextGameActivity(running, check(true, GAME_ACTIVITY_REFRESH_MS - 1))).toBeNull();
    });

    test("sends a quiet update once the last push is old, so the activity does not go stale", () => {
      expect(nextGameActivity(running, check(true, GAME_ACTIVITY_REFRESH_MS))).toEqual({
        row: { ...running, pushed_at: at(GAME_ACTIVITY_REFRESH_MS) },
        push: push("update", "mind_meld", "quiet"),
      });
    });

    test("clears the end of a partner who came back", () => {
      expect(nextGameActivity(ending(running), check(true, 30_000))).toEqual({ row: running, push: null });
    });
  });

  describe("a check that finds the partner in no game", () => {
    test("first sets the end by the turn, so a partner whose presence timed out has time to come back", () => {
      expect(nextGameActivity(running, check(false, 90_000))).toEqual({ row: ending(running, at(90_000 + 60_000)), push: null });
      const yours = { ...running, turn: "yours" as const };
      expect(nextGameActivity(yours, check(false, 90_000))).toEqual({ row: ending(yours, at(90_000 + 10 * 60_000)), push: null });
    });

    test("waits until the end, then deletes the row with one end push", () => {
      expect(nextGameActivity(ending(running, at(60_000)), check(false, 59_999))).toBeNull();
      expect(nextGameActivity(ending(running, at(60_000)), check(false, 60_000))).toEqual({ row: null, push: push("end") });
    });

    test("keeps the activity from going stale while it ends", () => {
      const row = ending({ ...running, turn: "yours" }, at(GAME_ACTIVITY_REFRESH_MS + 60_000));
      expect(nextGameActivity(row, check(false, GAME_ACTIVITY_REFRESH_MS))).toEqual({
        row: { ...row, pushed_at: at(GAME_ACTIVITY_REFRESH_MS) },
        push: push("update", "mind_meld", "quiet"),
      });
    });
  });

  describe("the end of an activity", () => {
    test("a viewer with no phone left that holds it ends it, and an older activity changes nothing", () => {
      expect(nextGameActivity(ending(running), { kind: "viewer_ended", activity_id: "activity-1" })).toEqual({ row: null, push: push("end") });
      expect(nextGameActivity(running, { kind: "viewer_ended", activity_id: "activity-0" })).toBeNull();
    });

    test("game pushes off ends it", () => {
      expect(nextGameActivity(running, { kind: "stop" })).toEqual({ row: null, push: push("end") });
      expect(nextGameActivity(null, { kind: "stop" })).toBeNull();
    });
  });
});

describe("buildLiveActivityRequest", () => {
  /** T0 in seconds, as APNs reads it. */
  const seconds = 1_794_312_000;
  const base: PreparedLiveActivityPush = {
    outbox_id: "outbox-1",
    target_token_id: "token-1",
    token: "a1b2c3d4e5f60718293a4b5c6d7e8f90",
    apns_environment: "sandbox",
    activity_id: "6f1c2d3e-4b5a-4c7d-8e9f-0a1b2c3d4e5f",
    event: "update",
    quiet: false,
    alert: null,
    game_kind: "mind_meld",
    turn: "none",
    queued_at: T0,
    start: null,
  };
  const body = (push: PreparedLiveActivityPush) => JSON.parse(buildLiveActivityRequest(push, "no.paeonia.app").body);

  test("a start carries the attributes, the alert, the ask for an update token, and a stale date two minutes out", () => {
    const push = { ...base, event: "start" as const, alert: { title: "Panci is playing Mind Meld", body: "Tap to join.", sound: false }, start: { partner_name: "Panci" } };
    const request = buildLiveActivityRequest(push, "no.paeonia.app");
    expect(request).toMatchObject({
      token: base.token,
      preferredEnvironment: "sandbox",
      topic: "no.paeonia.app.push-type.liveactivity",
      pushType: "liveactivity",
      priority: "10",
      expiration: "1794312120",
      collapseId: null,
    });
    expect(JSON.parse(request.body)).toEqual({
      aps: {
        timestamp: seconds,
        event: "start",
        "content-state": { gameKind: "mind_meld", phase: "playing", turn: "none" },
        "stale-date": 1_794_312_120,
        "attributes-type": "GameLiveActivityAttributes",
        attributes: { activityID: base.activity_id, partnerName: "Panci" },
        alert: { title: "Panci is playing Mind Meld", body: "Tap to join." },
        "input-push-token": 1,
      },
    });
  });

  test("an update carries the game, the turn and a stale date fifteen minutes out, and a quiet one goes at priority 5", () => {
    expect(body({ ...base, game_kind: "connect_four", turn: "yours" })).toEqual({
      aps: {
        timestamp: seconds,
        event: "update",
        "content-state": { gameKind: "connect_four", phase: "playing", turn: "yours" },
        "stale-date": 1_794_312_900,
      },
    });
    expect(buildLiveActivityRequest(base, "no.paeonia.app").expiration).toBe("1794312900");
    expect(buildLiveActivityRequest({ ...base, quiet: true }, "no.paeonia.app").priority).toBe("5");
  });

  test("an update with an alert carries its words and no attributes, and a ring names the sound inside the alert", () => {
    const words = { title: "Panci is playing Connect Four", body: "It's your turn." };
    expect(body({ ...base, alert: { ...words, sound: false } }).aps).toEqual({
      timestamp: seconds,
      event: "update",
      "content-state": { gameKind: "mind_meld", phase: "playing", turn: "none" },
      "stale-date": 1_794_312_900,
      alert: words,
    });
    expect(body({ ...base, alert: { ...words, sound: true } }).aps.alert).toEqual({ ...words, sound: "default" });
  });

  test("an end shows the ended state and leaves the Lock Screen at once", () => {
    const request = buildLiveActivityRequest({ ...base, event: "end" }, "no.paeonia.app");
    expect(request.expiration).toBe("1794340800");
    expect(JSON.parse(request.body)).toEqual({
      aps: {
        timestamp: seconds,
        event: "end",
        "content-state": { gameKind: "mind_meld", phase: "ended", turn: "none" },
        "dismissal-date": seconds,
      },
    });
  });
});
