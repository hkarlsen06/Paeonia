import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, components } from "./_generated/api";
import { gameChatSubjectId } from "./lib/gameChatSubjects";
import { appRoom } from "./lib/presence";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { failure } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-11-15T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const enterApp = (user: TestUser) => user.as.mutation(api.appPresence.set_app_presence, { p_present: true });
const setShows = (user: TestUser, shows: boolean) =>
  user.as.mutation(api.appPresence.set_shows_presence, { p_shows: shows });
const partnerOf = (user: TestUser) => user.as.query(api.appPresence.get_partner_presence, {});
const inAppRoom = (t: TestConvex, coupleId: string) =>
  t.run((ctx) => ctx.runQuery(components.presence.public.listRoom, { roomId: appRoom(coupleId) }));

describe("access", () => {
  test("a user without a couple, or without access, is refused by every function", async () => {
    const t = newTest();
    const stranger = await createSignedInUser(t);
    const unpaid = await createCouple(t, { entitled: false });
    for (const user of [stranger, unpaid.first]) {
      expect((await failure(enterApp(user))).code).toBe("42501");
      expect((await failure(setShows(user, false))).code).toBe("42501");
      expect((await failure(partnerOf(user))).code).toBe("42501");
    }
    expect(await inAppRoom(t, unpaid.coupleId)).toEqual([]);
  });
});

describe("partner presence", () => {
  test("shows the partner only while they are in the app", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await partnerOf(couple.second)).toEqual({ shows_presence: true, partner: null });

    await enterApp(couple.first);
    expect(await partnerOf(couple.second)).toEqual({
      shows_presence: true,
      partner: { games: [], chat: null, typing: null },
    });
    expect((await partnerOf(couple.first)).partner).toBeNull();

    await couple.first.as.mutation(api.appPresence.set_app_presence, { p_present: false });
    expect((await partnerOf(couple.second)).partner).toBeNull();
  });

  test("hiding works both ways, and turning it off leaves the app room at once", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await enterApp(couple.first);
    await enterApp(couple.second);
    expect(await inAppRoom(t, couple.coupleId)).toHaveLength(2);

    expect(await setShows(couple.first, false)).toEqual({ shows_presence: false });
    expect((await inAppRoom(t, couple.coupleId)).map((row) => row.userId)).toEqual([couple.second.userId]);
    expect(await partnerOf(couple.first)).toEqual({ shows_presence: false, partner: null });
    expect(await partnerOf(couple.second)).toEqual({ shows_presence: true, partner: null });

    // A heartbeat from a phone that has not heard of the change yet shows nothing.
    await enterApp(couple.first);
    expect((await inAppRoom(t, couple.coupleId)).map((row) => row.userId)).toEqual([couple.second.userId]);

    await setShows(couple.first, true);
    await enterApp(couple.first);
    await setShows(couple.second, false);
    expect(await partnerOf(couple.second)).toEqual({ shows_presence: false, partner: null });
    expect(await partnerOf(couple.first)).toEqual({ shows_presence: true, partner: null });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("says which games and chat the partner has open, and where they type", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const gameChat = await gameChatSubjectId(couple.coupleId, "mind_meld");
    await enterApp(couple.first);
    await couple.first.as.mutation(api.games.set_game_presence, { p_kind: "ludo", p_present: true });
    await couple.first.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await couple.first.as.mutation(api.chatPresence.set_chat_open, {
      p_couple_id: couple.coupleId, p_subject_kind: "couple", p_is_open: true,
    });
    await couple.first.as.mutation(api.chatPresence.set_chat_typing, {
      p_couple_id: couple.coupleId, p_subject_kind: "game", p_subject_id: gameChat, p_is_typing: true,
    });

    expect((await partnerOf(couple.second)).partner).toEqual({
      games: ["mind_meld", "ludo"],
      chat: { kind: "couple" },
      typing: { kind: "game", game_kind: "mind_meld" },
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("ending the relationship clears the app room", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await enterApp(couple.first);
    await enterApp(couple.second);
    expect(await inAppRoom(t, couple.coupleId)).toHaveLength(2);

    await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.first.userId, "user_left"));
    expect(await inAppRoom(t, couple.coupleId)).toEqual([]);
    expect((await failure(enterApp(couple.second))).code).toBe("42501");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
