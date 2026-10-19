import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { deleteCoupleGameRows } from "./lib/gameRegistry";
import { haversineMeters, pointsFor } from "./lib/guessMySpot";
import { newUuid } from "./lib/ids";
import { canReadMediaAsset } from "./lib/mediaAssets";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { endCouple, failure, op, photo, uploadAsset } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

const START = Date.parse("2026-10-18T12:00:00.000Z");

let scheduled: TestConvex | null = null;
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(async () => {
  if (scheduled) await scheduled.finishAllScheduledFunctions(vi.runAllTimers);
  scheduled = null;
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

type Setup = { t: TestConvex; couple: TestCouple; a: TestUser; b: TestUser; gameId: string };

const BERGEN = { latitude: 60.3913, longitude: 5.3221 };
const OSLO = { latitude: 59.9139, longitude: 10.7522 };

/** A couple with devices and a game. `a` sends first. */
async function startGame(): Promise<Setup> {
  const t = newTest();
  scheduled = t;
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await addDevice(t, a.userId);
  await addDevice(t, b.userId);
  const { game_id } = await a.as.mutation(api.guessMySpot.ensure_guess_my_spot_game, {});
  return { t, couple, a, b, gameId: game_id };
}

const view = (user: TestUser) => user.as.query(api.guessMySpot.get_guess_my_spot, {});
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

/** Uploads a photo for `roundId` as `user`, like the app does before it sends the round. */
const uploadPhoto = async (s: Setup, user: TestUser, roundId: string, purpose = photo(s.couple.coupleId, "guess_my_spot_round", "guess_my_spot_photo")) =>
  (await uploadAsset(s.t, user, { ...purpose, parentId: roundId })).assetId;

type SendOptions = { roundId?: string; assetId?: string; args?: ReturnType<typeof op>; roundNumber?: number; extra?: Record<string, unknown> };

/** Uploads a photo and sends it at `spot`. Returns the round id. */
async function send(s: Setup, user: TestUser, spot = BERGEN, options: SendOptions = {}) {
  const roundId = options.roundId ?? newUuid();
  const assetId = options.assetId ?? (await uploadPhoto(s, user, roundId));
  const data = await view(user);
  await user.as.mutation(api.guessMySpot.send_guess_my_spot_photo, {
    ...(options.args ?? op()),
    p_round_id: roundId,
    p_round_number: options.roundNumber ?? data.game!.round_count + 1,
    p_media_asset_id: assetId,
    p_latitude: spot.latitude,
    p_longitude: spot.longitude,
    p_place_name: "Bergen, Norway",
    p_taken_on: "2024-06-12",
    ...options.extra,
  });
  return roundId;
}

const guess = (user: TestUser, roundId: string, at = BERGEN, args = op()) =>
  user.as.mutation(api.guessMySpot.submit_guess_my_spot_guess, { ...args, p_round_id: roundId, p_latitude: at.latitude, p_longitude: at.longitude });

describe("access", () => {
  test("a user without a couple or a subscription cannot play", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(loner.as.mutation(api.guessMySpot.ensure_guess_my_spot_game, {}))).code).toBe("42501");
    expect((await failure(loner.as.query(api.guessMySpot.get_guess_my_spot, {}))).code).toBe("42501");
    expect((await failure(loner.as.query(api.guessMySpot.get_guess_my_spot_history, {}))).code).toBe("42501");
    const unpaid = await createCouple(t, { entitled: false });
    expect((await failure(unpaid.first.as.mutation(api.guessMySpot.ensure_guess_my_spot_game, {}))).code).toBe("42501");
  });

  test("another couple cannot guess or mark a round", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    const other = await createCouple(s.t);
    expect((await failure(guess(other.first, roundId))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.guessMySpot.mark_guess_my_spot_reveal_seen, { p_round_id: roundId }))).code).toBe("42501");
  });

  test("a replay after access ended is refused", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    const args = op();
    await guess(s.b, roundId, OSLO, args);
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect((await failure(guess(s.b, roundId, OSLO, args))).code).toBe("42501");
  });
  test("a send replayed after re-pairing with someone else is refused", async () => {
    const s = await startGame();
    const roundId = newUuid();
    const args = op();
    await send(s, s.a, BERGEN, { roundId, args });
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    // The sender pairs with someone new, in a couple that has its own game.
    const other = await createSignedInUser(s.t, { name: "Someone New" });
    await s.t.run(async (ctx) => {
      const now = new Date().toISOString();
      const pairId = newUuid();
      const coupleId = newUuid();
      const [low, high] = s.a.userId < other.userId ? [s.a.userId, other.userId] : [other.userId, s.a.userId];
      await ctx.db.insert("relationship_pairs", { id: pairId, user_low_id: low, user_high_id: high, created_at: now });
      await ctx.db.insert("couples", { id: coupleId, pair_id: pairId, status: "active", created_by_user_id: s.a.userId, created_at: now, updated_at: now });
      for (const [userId, role] of [[s.a.userId, "creator"], [other.userId, "partner"]] as const) {
        await ctx.db.insert("couple_members", { couple_id: coupleId, user_id: userId, role, status: "active", joined_at: now, updated_at: now });
      }
    });
    const replay = s.a.as.mutation(api.guessMySpot.send_guess_my_spot_photo, {
      ...args,
      p_round_id: roundId,
      p_round_number: 1,
      p_media_asset_id: newUuid(),
      p_latitude: BERGEN.latitude,
      p_longitude: BERGEN.longitude,
      p_place_name: "Bergen, Norway",
      p_taken_on: "2024-06-12",
    });
    expect((await failure(replay)).code).toBe("42501");
  });
});

describe("the round", () => {
  test("makes one game with the caller sending first", async () => {
    const s = await startGame();
    expect(await s.b.as.mutation(api.guessMySpot.ensure_guess_my_spot_game, {})).toEqual({ game_id: s.gameId, created: false });
    expect((await view(s.a)).game).toMatchObject({ id: s.gameId, turn_user_id: s.a.userId, shared_points: 0, round_count: 0, version: 1 });
  });

  test("the guesser never reads the spot, the place or the date before guessing", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    expect((await view(s.a)).current_round).toMatchObject({
      id: roundId,
      spot_latitude: BERGEN.latitude,
      spot_longitude: BERGEN.longitude,
      place_name: "Bergen, Norway",
      taken_on: "2024-06-12",
      photo_width: 100,
      photo_height: 80,
    });
    const theirs = await view(s.b);
    expect(theirs.current_round).toMatchObject({ id: roundId, spot_latitude: null, spot_longitude: null, place_name: null, taken_on: null, guess_latitude: null });
    expect(JSON.stringify(theirs)).not.toMatch(/Bergen|2024-06-12|60\.3913/);
    expect(theirs.game).toMatchObject({ turn_user_id: s.b.userId, round_count: 1 });
  });

  test("a guess scores by distance and makes the guesser the next sender", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    const result = await guess(s.b, roundId, OSLO);
    expect(result).toMatchObject({ id: roundId, spot_latitude: BERGEN.latitude, place_name: "Bergen, Norway", guess_latitude: OSLO.latitude });
    expect(result.distance_m).toBeGreaterThan(300_000);
    expect(result.distance_m).toBeLessThan(310_000);
    expect(result.points).toBe(Math.round(5000 * 0.5 ** (result.distance_m! / 1_500_000)));
    expect((await view(s.a)).game).toMatchObject({ turn_user_id: s.b.userId, shared_points: result.points });

    const next = await send(s, s.b, OSLO);
    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ id: next, round_number: 2, sender_user_id: s.b.userId, spot_latitude: null });
    expect(data.previous_round).toMatchObject({ id: roundId, place_name: "Bergen, Norway", my_reveal_seen_at: null });
  });

  test("the turn is enforced", async () => {
    const s = await startGame();
    expect((await failure(send(s, s.b))).message).toMatch(/your turn/);
    const roundId = await send(s, s.a);
    expect((await failure(send(s, s.a))).message).toMatch(/your turn/);
    expect((await failure(guess(s.a, roundId))).code).toBe("42501");
    await guess(s.b, roundId);
    expect((await failure(guess(s.b, roundId, OSLO))).message).toMatch(/already has a guess/);
  });

  test("a send queued for a turn that moved on is refused", async () => {
    const s = await startGame();
    const first = await send(s, s.a);
    await guess(s.b, first);
    const second = await send(s, s.b);
    await guess(s.a, second);
    expect((await failure(send(s, s.a, BERGEN, { roundNumber: 2 }))).message).toMatch(/moved on/);
    await send(s, s.a, BERGEN, { roundNumber: 3 });
  });

  test("spots, place names and dates are checked", async () => {
    const s = await startGame();
    expect((await failure(send(s, s.a, { latitude: 91, longitude: 0 }))).message).toMatch(/latitude/);
    expect((await failure(send(s, s.a, { latitude: 0, longitude: 181 }))).message).toMatch(/longitude/);
    expect((await failure(send(s, s.a, BERGEN, { extra: { p_place_name: "x".repeat(121) } }))).message).toMatch(/place name/);
    expect((await failure(send(s, s.a, BERGEN, { extra: { p_taken_on: "2026-10-25" } }))).message).toMatch(/taken on/);
    const roundId = await send(s, s.a, { latitude: 60.12345678, longitude: 5.1 }, { extra: { p_place_name: "  ", p_taken_on: null } });
    expect((await view(s.a)).current_round).toMatchObject({ id: roundId, spot_latitude: 60.123457, place_name: null, taken_on: null });
    expect((await failure(guess(s.b, roundId, { latitude: -90.5, longitude: 0 }))).message).toMatch(/latitude/);
  });

  test("a repeated operation returns the same answer", async () => {
    const s = await startGame();
    const roundId = newUuid();
    const assetId = await uploadPhoto(s, s.a, roundId);
    const sendArgs = op();
    await send(s, s.a, BERGEN, { roundId, assetId, args: sendArgs, roundNumber: 1 });
    await send(s, s.a, BERGEN, { roundId, assetId, args: sendArgs, roundNumber: 1 });
    const guessArgs = op();
    const first = await guess(s.b, roundId, OSLO, guessArgs);
    expect(await guess(s.b, roundId, OSLO, guessArgs)).toEqual(first);
    expect((await view(s.a)).game!.shared_points).toBe(first.points);
  });

  test("sending counts toward the streak and guessing does not", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    await guess(s.b, roundId);
    const events = await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events.map((event) => [event.activity_kind, event.user_id])).toEqual([["game_turn_completed", s.a.userId]]);
  });
});

describe("the photo", () => {
  test("must be the sender's finalized upload for this round", async () => {
    const s = await startGame();
    const roundId = newUuid();
    const usable = (promise: Promise<unknown>) => failure(promise);

    const otherRound = await uploadPhoto(s, s.a, newUuid());
    expect(await usable(send(s, s.a, BERGEN, { roundId, assetId: otherRound }))).toEqual({ code: "23514", message: "guess my spot photo is not usable" });

    const story = (await uploadAsset(s.t, s.a, { ...photo(s.couple.coupleId, "story", "story_photo"), parentId: roundId })).assetId;
    expect(await usable(send(s, s.a, BERGEN, { roundId, assetId: story }))).toEqual({ code: "23514", message: "guess my spot photo is not usable" });

    const partners = await uploadPhoto(s, s.b, roundId);
    expect(await usable(send(s, s.a, BERGEN, { roundId, assetId: partners }))).toEqual({ code: "42501", message: "guess my spot photo is not available" });
    expect(await usable(send(s, s.a, BERGEN, { roundId, assetId: newUuid() }))).toEqual({ code: "42501", message: "guess my spot photo is not available" });

    const pending = await s.a.as.mutation(api.media.create_pending_media_upload, {
      ...op(),
      p_reserved_parent_kind: "guess_my_spot_round",
      p_reserved_parent_id: roundId,
      p_upload_purpose: "guess_my_spot_photo",
      p_media_type: "image",
      p_file_extension: "jpg",
      p_couple_id: s.couple.coupleId,
    });
    expect(await usable(send(s, s.a, BERGEN, { roundId, assetId: pending[0].media_asset_id }))).toEqual({ code: "23514", message: "guess my spot photo is not usable" });

    const first = await send(s, s.a, BERGEN, { roundId });
    const used = (await view(s.a)).current_round!.photo_media_asset_id;
    await guess(s.b, first);
    expect((await failure(send(s, s.b, BERGEN, { assetId: used }))).code).toBe("42501");
  });

  test("a photo can't be reused for a second round", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    const assetId = (await view(s.a)).current_round!.photo_media_asset_id;
    await guess(s.b, roundId);
    await send(s, s.b);
    await guess(s.a, (await view(s.a)).current_round!.id);
    // Same asset, reserved for the first round, for a new round id.
    expect((await failure(send(s, s.a, BERGEN, { assetId }))).message).toBe("guess my spot photo is not usable");
    expect((await failure(send(s, s.a, BERGEN, { roundId, assetId }))).code).toBe("23505");
  });

  test("the upload needs the round kind, an image and the couple", async () => {
    const s = await startGame();
    const reserve = (args: Record<string, unknown>) =>
      s.a.as.mutation(api.media.create_pending_media_upload, {
        ...op(),
        p_reserved_parent_kind: "guess_my_spot_round",
        p_reserved_parent_id: newUuid(),
        p_upload_purpose: "guess_my_spot_photo",
        p_media_type: "image",
        p_file_extension: "jpg",
        p_couple_id: s.couple.coupleId,
        ...args,
      } as never);
    expect((await failure(reserve({ p_reserved_parent_kind: "story" }))).code).toBe("23514");
    expect((await failure(reserve({ p_couple_id: undefined }))).code).toBe("23514");
    const other = await createCouple(s.t);
    expect((await failure(reserve({ p_couple_id: other.coupleId }))).code).toBe("42501");
    const [reservation] = await reserve({});
    expect(reservation).toMatchObject({ bucket: "couple-media", storage_path: `${s.couple.coupleId}/image/${reservation.media_asset_id}.jpg` });
  });

  test("both partners can read a sent photo, a stranger can't, and the round keeps it alive", async () => {
    const s = await startGame();
    const roundId = newUuid();
    const assetId = await uploadPhoto(s, s.a, roundId);
    const readable = (userId: string) =>
      s.t.run(async (ctx) => {
        const asset = await ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", assetId)).unique();
        return await canReadMediaAsset(ctx, userId, asset!);
      });
    expect(await readable(s.b.userId)).toBe(false);
    await send(s, s.a, BERGEN, { roundId, assetId });
    expect(await readable(s.a.userId)).toBe(true);
    expect(await readable(s.b.userId)).toBe(true);
    const stranger = await createCouple(s.t);
    expect(await readable(stranger.first.userId)).toBe(false);
    expect(await s.t.run((ctx) => queueOrphanedMediaAssetForDelete(ctx, assetId))).toBe(false);
  });
});

describe("seen marks", () => {
  test("keep the first time for each partner", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    expect((await failure(s.a.as.mutation(api.guessMySpot.mark_guess_my_spot_reveal_seen, { p_round_id: roundId }))).message).toMatch(/no guess/);
    await guess(s.b, roundId);
    const version = (await view(s.a)).game!.version;
    const first = await s.b.as.mutation(api.guessMySpot.mark_guess_my_spot_reveal_seen, { p_round_id: roundId });
    tick(60);
    expect(await s.b.as.mutation(api.guessMySpot.mark_guess_my_spot_reveal_seen, { p_round_id: roundId })).toEqual(first);
    expect((await view(s.b)).current_round!.my_reveal_seen_at).toBe(first.reveal_seen_at);
    expect((await view(s.a)).current_round!.my_reveal_seen_at).toBeNull();
    expect((await view(s.a)).game!.version).toBe(version + 1);
  });
});

describe("history", () => {
  test("lists guessed rounds newest first with records per guesser", async () => {
    const s = await startGame();
    let sender = s.a;
    let guesser = s.b;
    const offsets = [0, 0.1, 0.2, 0.3];
    for (const offset of offsets) {
      const roundId = await send(s, sender);
      await guess(guesser, roundId, { latitude: BERGEN.latitude + offset, longitude: BERGEN.longitude });
      [sender, guesser] = [guesser, sender];
    }
    const open = await send(s, sender);
    const page = await s.a.as.query(api.guessMySpot.get_guess_my_spot_history, {});
    expect(page.rounds.map((round) => round.round_number)).toEqual([4, 3, 2, 1]);
    expect(JSON.stringify(page)).not.toContain(open);
    const distances = page.rounds.map((round) => round.distance_m!).reverse();
    // b guessed rounds 1 and 3, a guessed rounds 2 and 4.
    expect(page.records.partner).toEqual({ guesses: 2, closest_m: 0, average_m: Math.round(distances[2] / 2) });
    expect(page.records.mine).toEqual({ guesses: 2, closest_m: distances[1], average_m: Math.round((distances[1] + distances[3]) / 2) });
    expect(page.records.shared_points).toBe(page.rounds.reduce((sum, round) => sum + round.points!, 0));
    // a guessed rounds 2 and 4, so a's own total is their points only.
    const pointsOf = (numbers: number[]) =>
      page.rounds.filter((round) => numbers.includes(round.round_number)).reduce((sum, round) => sum + round.points!, 0);
    expect(page.records.my_points).toBe(pointsOf([2, 4]));
    expect(page.records.partner_points).toBe(pointsOf([1, 3]));
    expect(page.rounds[0]).toMatchObject({ place_name: "Bergen, Norway", spot_latitude: BERGEN.latitude });
  });

  test("is empty before the first game", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await couple.first.as.query(api.guessMySpot.get_guess_my_spot_history, {})).toEqual({
      rounds: [],
      records: {
        shared_points: 0,
        my_points: 0,
        partner_points: 0,
        mine: { guesses: 0, closest_m: null, average_m: null },
        partner: { guesses: 0, closest_m: null, average_m: null },
      },
    });
  });
});

describe("pushes", () => {
  const rowsOf = async (s: Setup, kind: string) => (await outbox(s.t)).filter((row) => row.kind === kind);
  const types = (rows: { payload: unknown }[]) => rows.map((row) => (row.payload as { type: string; step?: string }).step ?? (row.payload as { type: string }).type).sort();

  test("a send tells the guesser, without the place or the spot", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    const rows = await rowsOf(s, "game_turn_ready");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      payload: { game_kind: "guess_my_spot", round_id: roundId, actor_user_id: s.a.userId, deeplink: "paeonia://games/guess-my-spot" },
    });
    expect(JSON.stringify(await outbox(s.t))).not.toMatch(/Bergen|60\.39|latitude|points/);
  });

  test("a guess then a send within 5 minutes send one push", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    await deliverDuePushes(s.t);
    await guess(s.b, roundId, OSLO);
    expect(await deliverDuePushes(s.t)).toEqual([]);
    tick(60);
    await send(s, s.b);
    tick(5 * 60);
    expect(types(await deliverDuePushes(s.t))).toEqual(["guessed"]);
    expect((await rowsOf(s, "game_result"))[0].last_error).toBe("notification is out of date");
  });

  test("a guess with no send sends the result push after 5 minutes", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    await deliverDuePushes(s.t);
    await guess(s.b, roundId, OSLO);
    tick(5 * 60);
    expect(types(await deliverDuePushes(s.t))).toEqual(["game_result"]);
    tick(60);
    await send(s, s.b);
    expect(types(await deliverDuePushes(s.t))).toEqual(["game_turn_ready"]);
  });

  test("a result push is dropped when the sender opened the game or saw the reveal", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    await deliverDuePushes(s.t);
    await guess(s.b, roundId, OSLO);
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "guess_my_spot", p_present: true });
    tick(5 * 60);
    expect(await deliverDuePushes(s.t)).toEqual([]);

    const s2 = await startGame();
    const second = await send(s2, s2.a);
    await deliverDuePushes(s2.t);
    await guess(s2.b, second, OSLO);
    await s2.a.as.mutation(api.guessMySpot.mark_guess_my_spot_reveal_seen, { p_round_id: second });
    tick(5 * 60);
    expect(await deliverDuePushes(s2.t)).toEqual([]);
  });

  test("a turn push is dropped once the guess is in, and skipped while the partner is here", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    await guess(s.b, roundId);
    expect(types(await deliverDuePushes(s.t))).toEqual([]);
    expect((await rowsOf(s, "game_turn_ready"))[0].last_error).toBe("notification is out of date");

    const s2 = await startGame();
    await s2.b.as.mutation(api.games.set_game_presence, { p_kind: "guess_my_spot", p_present: true });
    await send(s2, s2.a);
    expect(await outbox(s2.t)).toHaveLength(0);
  });

  test("a turn push is dropped when the partner opens the game before it goes out", async () => {
    const s = await startGame();
    await send(s, s.a);
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "guess_my_spot", p_present: true });
    expect(await deliverDuePushes(s.t)).toEqual([]);
    expect((await rowsOf(s, "game_turn_ready"))[0].last_error).toBe("notification is out of date");
  });
});

describe("turn reminder", () => {
  const run = (s: Setup) => s.t.mutation(internal.guessMySpot.send_due_guess_my_spot_reminders, {});
  const reminders = async (s: Setup) => (await outbox(s.t)).filter((row) => row.kind === "game_turn_reminder");

  test("one reminder per turn, for a guess and for a send", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    tick(71 * 3600);
    expect(await run(s)).toBe(0);
    tick(3600);
    expect(await run(s)).toBe(1);
    expect(await run(s)).toBe(0);
    expect((await reminders(s))[0]).toMatchObject({ recipient_user_id: s.b.userId, payload: { actor_user_id: s.a.userId, game_id: s.gameId } });

    await guess(s.b, roundId);
    tick(72 * 3600);
    expect(await run(s)).toBe(1);
    expect((await reminders(s)).map((row) => row.recipient_user_id)).toEqual([s.b.userId, s.b.userId]);
  });

  test("a reminder queued for a turn that moved on is dropped", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    await deliverDuePushes(s.t);
    tick(72 * 3600);
    await run(s);
    await guess(s.b, roundId);
    expect(await deliverDuePushes(s.t)).toEqual([]);
  });
});

describe("cleanup", () => {
  test("deletes every Guess my spot row of the couple", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a);
    await guess(s.b, roundId);
    await s.t.run((ctx) => deleteCoupleGameRows(ctx, s.couple.coupleId));
    const left = await s.t.run(async (ctx) => [
      ...(await ctx.db.query("guess_my_spot_games").collect()),
      ...(await ctx.db.query("guess_my_spot_rounds").collect()),
    ]);
    expect(left).toEqual([]);
  });
});

describe("play style points", () => {
  test("only the guesser scores, and the shared total has every guess", async () => {
    const s = await startGame();
    const first = await send(s, s.a);
    await guess(s.b, first, OSLO);
    const second = await send(s, s.b);
    await guess(s.a, second, BERGEN);
    const forA = (await view(s.a)).game!;
    const forB = (await view(s.b)).game!;
    const firstPoints = pointsFor(haversineMeters(OSLO, BERGEN));
    expect(forA).toMatchObject({ my_points: 5000, partner_points: firstPoints, shared_points: 5000 + firstPoints });
    expect(forB).toMatchObject({ my_points: firstPoints, partner_points: 5000 });
  });
});

describe("place details", () => {
  test("the city and country go with the spot and stay hidden from the guesser until the guess", async () => {
    const s = await startGame();
    const roundId = await send(s, s.a, BERGEN, { extra: { p_place_city: "  Bergen ", p_place_country_code: "NO" } });
    expect((await view(s.a)).current_round).toMatchObject({ place_city: "Bergen", place_country_code: "NO" });
    expect((await view(s.b)).current_round).toMatchObject({ place_city: null, place_country_code: null });
    await guess(s.b, roundId);
    expect((await view(s.b)).current_round).toMatchObject({ place_city: "Bergen", place_country_code: "NO" });
  });

  test("a country must be two capital letters and a city 1 to 80 characters", async () => {
    const s = await startGame();
    expect((await failure(send(s, s.a, BERGEN, { extra: { p_place_country_code: "nor" } }))).message).toMatch(/two letter/);
    expect((await failure(send(s, s.a, BERGEN, { extra: { p_place_city: "x".repeat(81) } }))).message).toMatch(/city/);
    await send(s, s.a, BERGEN, { extra: { p_place_city: "", p_place_country_code: null } });
    expect((await view(s.a)).current_round).toMatchObject({ place_city: null, place_country_code: null });
  });
});

describe("deleting a round", () => {
  /** A round sent by a and guessed by b. `seen` marks it seen by both. */
  async function guessedRound(seen: boolean) {
    const s = await startGame();
    const roundId = newUuid();
    const assetId = await uploadPhoto(s, s.a, roundId);
    await send(s, s.a, BERGEN, { roundId, assetId });
    await guess(s.b, roundId, OSLO);
    if (seen) {
      await s.a.as.mutation(api.guessMySpot.mark_guess_my_spot_reveal_seen, { p_round_id: roundId });
      await s.b.as.mutation(api.guessMySpot.mark_guess_my_spot_reveal_seen, { p_round_id: roundId });
    }
    return { s, roundId, assetId };
  }
  const remove = (user: TestUser, roundId: string, args = op()) =>
    user.as.mutation(api.guessMySpot.delete_guess_my_spot_round, { ...args, p_round_id: roundId });

  test("only the sender can, and only once both saw the reveal", async () => {
    const early = await guessedRound(false);
    expect((await view(early.s.a)).current_round!.can_delete).toBe(false);
    expect((await failure(remove(early.s.a, early.roundId))).message).toMatch(/can't be deleted yet/);
    const { s, roundId } = await guessedRound(true);
    expect((await view(s.a)).current_round!.can_delete).toBe(true);
    expect((await view(s.b)).current_round!.can_delete).toBe(false);
    expect((await failure(remove(s.b, roundId))).message).toMatch(/only the sender/);
    const stranger = await createCouple(s.t);
    expect((await failure(remove(stranger.first, roundId))).code).toBe("42501");
  });

  test("hides it from the history, deletes the photo, keeps the points, and a repeat answers the same", async () => {
    const { s, roundId, assetId } = await guessedRound(true);
    const before = await s.a.as.query(api.guessMySpot.get_guess_my_spot_history, {});
    const args = op();
    const first = await remove(s.a, roundId, args);
    tick(60);
    expect(await remove(s.a, roundId, args)).toEqual(first);
    expect(await remove(s.a, roundId)).toEqual(first);
    expect((await view(s.a)).current_round!.can_delete).toBe(false);
    const after = await s.a.as.query(api.guessMySpot.get_guess_my_spot_history, {});
    expect(after.rounds).toEqual([]);
    expect(after.records).toEqual(before.records);
    expect((await view(s.b)).game!.shared_points).toBe(before.records.shared_points);
    const asset = await s.t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", assetId)).unique());
    expect(asset!.storage_delete_status).toBe("pending");
    expect(await s.t.run((ctx) => canReadMediaAsset(ctx, s.b.userId, asset!))).toBe(false);
  });
});
