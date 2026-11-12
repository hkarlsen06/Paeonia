import { describe, expect, test } from "vitest";
import { buildLiveActivityRequest, type PreparedLiveActivityPush } from "./apns";
import {
  GAME_ACTIVITY_AWAY_GRACE_MS,
  GAME_ACTIVITY_CLOSE_GRACE_MS,
  GAME_ACTIVITY_REFRESH_MS,
  type GameActivityEvent,
  type GameActivityState,
  needsStartCheck,
  nextGameActivity,
  type StartCheck,
} from "./liveActivities";

const T0 = "2026-11-10T12:00:00.000Z";
const at = (ms: number) => new Date(Date.parse(T0) + ms).toISOString();

const playing: GameActivityState = { id: "activity-1", game_kind: "mind_meld", phase: "playing", started_at: T0, pushed_at: T0 };
const idle: GameActivityState = { ...playing, phase: "idle" };
const held: GameActivityState = { ...playing, phase: "held" };
const off: GameActivityState = { ...playing, phase: "off" };
const leaving = (row: GameActivityState, endsAt = at(60_000)): GameActivityState => ({ ...row, ends_at: endsAt });

const checked = (start: StartCheck, game_kind: GameActivityState["game_kind"] = "mind_meld"): GameActivityEvent => ({
  kind: "start_checked",
  game_kind,
  at: at(30_000),
  new_id: "activity-2",
  start,
});
const heartbeat = (game_kind: GameActivityState["game_kind"] = "mind_meld"): GameActivityEvent => ({ kind: "heartbeat", game_kind, at: at(30_000) });
const check = (partner_present: boolean, ms: number): GameActivityEvent => ({ kind: "check", partner_present, at: at(ms) });
const push = (event: "start" | "update" | "end", activity_id: string, game_kind: GameActivityState["game_kind"], quiet = false) => ({
  event,
  quiet,
  activity_id,
  game_kind,
});

describe("needsStartCheck", () => {
  test("is needed with no row, an idle row, a switch, and a held row in another game", () => {
    expect(needsStartCheck(null, "mind_meld")).toBe(true);
    expect(needsStartCheck(idle, "mind_meld")).toBe(true);
    expect(needsStartCheck(playing, "piccante")).toBe(true);
    expect(needsStartCheck(held, "piccante")).toBe(true);
  });

  test("is not needed in the running or held game, or with game pushes off", () => {
    expect(needsStartCheck(playing, "mind_meld")).toBe(false);
    expect(needsStartCheck(held, "mind_meld")).toBe(false);
    expect(needsStartCheck(off, "piccante")).toBe(false);
  });
});

describe("nextGameActivity", () => {
  describe("the partner's heartbeat after the start check", () => {
    test("starts a new activity with a new id from no row, an idle row and a held row in another game", () => {
      for (const row of [null, idle, { ...held, game_kind: "piccante" as const }]) {
        expect(nextGameActivity(row, checked("start"))).toEqual({
          row: { id: "activity-2", game_kind: "mind_meld", phase: "playing", started_at: at(30_000), pushed_at: at(30_000) },
          push: push("start", "activity-2", "mind_meld"),
        });
      }
    });

    test("notes a viewer who already has the game open as held, without a push", () => {
      expect(nextGameActivity(null, checked("viewer_present"))).toEqual({
        row: { id: "activity-2", game_kind: "mind_meld", phase: "held", started_at: at(30_000), pushed_at: at(30_000) },
        push: null,
      });
      expect(nextGameActivity(idle, checked("viewer_present", "piccante"))).toEqual({ row: { ...idle, game_kind: "piccante", phase: "held" }, push: null });
    });

    test("holds the row without a push while the couple is together, and ends a running activity on a switch", () => {
      expect(nextGameActivity(null, checked("together"))).toEqual({
        row: { id: "activity-2", game_kind: "mind_meld", phase: "held", started_at: at(30_000), pushed_at: at(30_000) },
        push: null,
      });
      expect(nextGameActivity(idle, checked("together", "piccante"))).toEqual({ row: { ...idle, game_kind: "piccante", phase: "held" }, push: null });
      expect(nextGameActivity(leaving(playing), checked("together", "draw_and_guess"))).toEqual({
        row: { ...held, game_kind: "draw_and_guess" },
        push: push("end", "activity-1", "mind_meld"),
      });
    });

    test("turns off for a viewer with game pushes off, and keeps an idle row for a viewer without a phone that can show it", () => {
      expect(nextGameActivity(idle, checked("pushes_off"))).toEqual({ row: off, push: null });
      expect(nextGameActivity(null, checked("no_token"))).toEqual({
        row: { id: "activity-2", game_kind: "mind_meld", phase: "idle", started_at: at(30_000), pushed_at: at(30_000) },
        push: null,
      });
      expect(nextGameActivity(idle, checked("no_token"))).toBeNull();
    });

    test("moves a running activity to another game with one update and no start, and clears its end", () => {
      expect(nextGameActivity(leaving(playing), checked("start", "draw_and_guess"))).toEqual({
        row: { ...playing, game_kind: "draw_and_guess", pushed_at: at(30_000) },
        push: push("update", "activity-1", "draw_and_guess"),
      });
    });

    test("ends a running activity when the partner moves into the game the viewer has open", () => {
      expect(nextGameActivity(playing, checked("viewer_present", "draw_and_guess"))).toEqual({
        row: { ...held, game_kind: "draw_and_guess" },
        push: push("end", "activity-1", "mind_meld"),
      });
    });

    test("ends a running activity on a switch when the viewer turned pushes off or has no phone left", () => {
      expect(nextGameActivity(playing, checked("pushes_off", "piccante"))).toEqual({ row: off, push: push("end", "activity-1", "mind_meld") });
      expect(nextGameActivity(playing, checked("no_token", "piccante"))).toEqual({ row: idle, push: push("end", "activity-1", "mind_meld") });
    });
  });

  describe("the partner's heartbeat with no start check", () => {
    test("changes nothing in the running or held game, or with pushes off", () => {
      for (const row of [playing, held, off]) expect(nextGameActivity(row, heartbeat())).toBeNull();
    });

    test("clears the end of a partner who came back in time", () => {
      expect(nextGameActivity(leaving(playing), heartbeat())).toEqual({ row: playing, push: null });
      expect(nextGameActivity(leaving(held), heartbeat())).toEqual({ row: held, push: null });
    });
  });

  describe("the partner closing a game screen", () => {
    test("sets the end a minute after the close, for the running or held game", () => {
      for (const row of [playing, held]) {
        expect(nextGameActivity(row, { kind: "left", game_kind: "mind_meld", at: at(10_000) })).toEqual({
          row: { ...row, ends_at: at(10_000 + GAME_ACTIVITY_CLOSE_GRACE_MS) },
          push: null,
        });
      }
    });

    test("keeps an earlier end", () => {
      expect(nextGameActivity(leaving(playing, at(20_000)), { kind: "left", game_kind: "mind_meld", at: at(10_000) })).toBeNull();
    });

    test("changes nothing for another game, an idle row or pushes off", () => {
      expect(nextGameActivity(playing, { kind: "left", game_kind: "piccante", at: at(10_000) })).toBeNull();
      expect(nextGameActivity(idle, { kind: "left", game_kind: "mind_meld", at: at(10_000) })).toBeNull();
      expect(nextGameActivity(off, { kind: "left", game_kind: "mind_meld", at: at(10_000) })).toBeNull();
    });
  });

  describe("the viewer's own heartbeat", () => {
    test("in the running activity's game joins it and ends it on every phone", () => {
      expect(nextGameActivity(playing, { kind: "viewer_heartbeat", game_kind: "mind_meld" })).toEqual({
        row: held,
        push: push("end", "activity-1", "mind_meld"),
      });
    });

    test("changes nothing in another game, or once held", () => {
      expect(nextGameActivity(playing, { kind: "viewer_heartbeat", game_kind: "piccante" })).toBeNull();
      expect(nextGameActivity(held, { kind: "viewer_heartbeat", game_kind: "mind_meld" })).toBeNull();
      expect(nextGameActivity(idle, { kind: "viewer_heartbeat", game_kind: "mind_meld" })).toBeNull();
    });
  });

  describe("a phone of the viewer that ended the activity on its own", () => {
    test("ends it on the other phones and lets the next heartbeat start a new one", () => {
      expect(nextGameActivity(leaving(playing), { kind: "viewer_ended", activity_id: "activity-1" })).toEqual({
        row: idle,
        push: push("end", "activity-1", "mind_meld"),
      });
    });

    test("changes nothing for an older activity or one that no longer runs", () => {
      expect(nextGameActivity(playing, { kind: "viewer_ended", activity_id: "activity-0" })).toBeNull();
      expect(nextGameActivity(held, { kind: "viewer_ended", activity_id: "activity-1" })).toBeNull();
    });
  });

  describe("a check that finds the partner in a game", () => {
    test("changes nothing soon after the last push", () => {
      expect(nextGameActivity(playing, check(true, GAME_ACTIVITY_REFRESH_MS - 1))).toBeNull();
      expect(nextGameActivity(held, check(true, 2 * GAME_ACTIVITY_REFRESH_MS))).toBeNull();
    });

    test("sends a quiet update once the last push is old, so the activity does not go stale", () => {
      expect(nextGameActivity(playing, check(true, GAME_ACTIVITY_REFRESH_MS))).toEqual({
        row: { ...playing, pushed_at: at(GAME_ACTIVITY_REFRESH_MS) },
        push: push("update", "activity-1", "mind_meld", true),
      });
    });

    test("clears the end of a partner who came back", () => {
      expect(nextGameActivity(leaving(playing), check(true, 30_000))).toEqual({ row: playing, push: null });
      expect(nextGameActivity(leaving(held), check(true, 30_000))).toEqual({ row: held, push: null });
    });
  });

  describe("a check that finds the partner in no game", () => {
    test("first waits, so a partner whose presence timed out has time to come back", () => {
      expect(nextGameActivity(playing, check(false, 90_000))).toEqual({
        row: leaving(playing, at(90_000 + GAME_ACTIVITY_AWAY_GRACE_MS)),
        push: null,
      });
    });

    test("ends at the next check, even one that runs a little under 30 seconds later", () => {
      const away = nextGameActivity(playing, check(false, 90_000))!.row;
      expect(nextGameActivity(away, check(false, 90_000 + 29_500))).toEqual({ row: idle, push: push("end", "activity-1", "mind_meld") });
    });

    test("waits until the end", () => {
      expect(nextGameActivity(leaving(playing, at(60_000)), check(false, 59_999))).toBeNull();
    });

    test("then ends a running activity, and lets a held row start again without a push", () => {
      expect(nextGameActivity(leaving(playing, at(60_000)), check(false, 60_000))).toEqual({ row: idle, push: push("end", "activity-1", "mind_meld") });
      expect(nextGameActivity(leaving(held, at(60_000)), check(false, 60_000))).toEqual({ row: idle, push: null });
    });

    test("changes nothing for an idle row or pushes off", () => {
      expect(nextGameActivity(idle, check(false, 60_000))).toBeNull();
      expect(nextGameActivity(off, check(false, 60_000))).toBeNull();
    });
  });

  describe("the viewer's game push setting", () => {
    test("off ends a running activity, and stops every other row from starting one", () => {
      expect(nextGameActivity(leaving(playing), { kind: "pushes_off" })).toEqual({ row: off, push: push("end", "activity-1", "mind_meld") });
      expect(nextGameActivity(held, { kind: "pushes_off" })).toEqual({ row: off, push: null });
      expect(nextGameActivity(idle, { kind: "pushes_off" })).toEqual({ row: off, push: null });
      expect(nextGameActivity(off, { kind: "pushes_off" })).toBeNull();
    });

    test("on lets the next heartbeat check for a start", () => {
      expect(nextGameActivity(off, { kind: "pushes_on" })).toEqual({ row: idle, push: null });
      expect(nextGameActivity(playing, { kind: "pushes_on" })).toBeNull();
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
    game_kind: "mind_meld",
    queued_at: T0,
    start: null,
  };
  const body = (push: PreparedLiveActivityPush) => JSON.parse(buildLiveActivityRequest(push, "no.paeonia.app").body);

  test("a start carries the attributes, the alert, the ask for an update token, and a stale date two minutes out", () => {
    const push = { ...base, event: "start" as const, start: { partner_name: "Panci", alert_title: "Panci is playing Mind Meld", alert_body: "Tap to join." } };
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
        "content-state": { gameKind: "mind_meld", phase: "playing" },
        "stale-date": 1_794_312_120,
        "attributes-type": "GameLiveActivityAttributes",
        attributes: { activityID: base.activity_id, partnerName: "Panci" },
        alert: { title: "Panci is playing Mind Meld", body: "Tap to join." },
        "input-push-token": 1,
      },
    });
  });

  test("an update carries the game and a stale date fifteen minutes out, and a quiet one goes at priority 5", () => {
    expect(body({ ...base, game_kind: "draw_and_guess" })).toEqual({
      aps: {
        timestamp: seconds,
        event: "update",
        "content-state": { gameKind: "draw_and_guess", phase: "playing" },
        "stale-date": 1_794_312_900,
      },
    });
    expect(buildLiveActivityRequest(base, "no.paeonia.app").expiration).toBe("1794312900");
    expect(buildLiveActivityRequest({ ...base, quiet: true }, "no.paeonia.app").priority).toBe("5");
  });

  test("an end shows the ended state and leaves the Lock Screen at once", () => {
    const request = buildLiveActivityRequest({ ...base, event: "end" }, "no.paeonia.app");
    expect(request.expiration).toBe("1794340800");
    expect(JSON.parse(request.body)).toEqual({
      aps: {
        timestamp: seconds,
        event: "end",
        "content-state": { gameKind: "mind_meld", phase: "ended" },
        "dismissal-date": seconds,
      },
    });
  });
});
