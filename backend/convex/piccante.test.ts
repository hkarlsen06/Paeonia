import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { piccanteBackend } from "./lib/piccante";
import { endCouple, failure, op } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestUser } from "./test.setup";
const view = (u: TestUser) => u.as.query(api.piccante.get_piccante, {});
async function setup() {
  const t = newTest();
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await a.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "en" });
  const initial = await a.as.mutation(api.piccante.ensure_piccante_game, {});
  if (!initial.game) throw new Error("missing game");
  const gameId = initial.game.id;
  async function args(u = a) { return { ...op(), p_game_id: gameId, p_expected_version: (await view(u)).game!.version }; }
  return { t, couple, a, b, gameId, args };
}
async function ready() {
  const s = await setup();
  await s.a.as.mutation(api.piccante.choose_piccante_size, { ...await s.args(), p_size: 3 });
  await s.a.as.mutation(api.piccante.hide_piccante_chili, { ...await s.args(), p_tile: 0, p_note: "You owe me tea" });
  await s.b.as.mutation(api.piccante.hide_piccante_chili, { ...await s.args(s.b), p_tile: 8, p_note: "You owe me cake" });
  return s;
}
describe("Piccante authorization", () => {
  test("every public function refuses an unpaired user and an unentitled couple", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t);
    const unpaid = await createCouple(t, { entitled: false });
    for (const u of [loner, unpaid.first]) {
      const args = { ...op(), p_game_id: newUuid(), p_expected_version: 1 };
      const calls = [
        u.as.query(api.piccante.get_piccante, {}),
        u.as.query(api.piccante.get_piccante_result, { p_game_number: 1 }),
        u.as.mutation(api.piccante.ensure_piccante_game, {}),
        u.as.mutation(api.piccante.choose_piccante_size, { ...args, p_size: 3 }),
        u.as.mutation(api.piccante.hide_piccante_chili, { ...args, p_tile: 0 }),
        u.as.mutation(api.piccante.bite_piccante_chocolate, { ...args, p_tile: 0 }),
        u.as.mutation(api.piccante.sniff_piccante_chocolate, { ...args, p_tile: 0 }),
        u.as.mutation(api.piccante.start_piccante_rematch, args),
        u.as.mutation(api.piccante.mark_piccante_result_seen, { ...op(), p_game_id: args.p_game_id, p_game_number: 1 }),
      ];
      for (const result of await Promise.all(calls.map(failure))) expect(result.code).toBe("42501");
    }
  });
  test("another entitled couple cannot mutate the named game or read its result", async () => {
    const s = await ready();
    const other = (await createCouple(s.t)).first;
    const args = { ...await s.args(), ...op() };
    const calls = [
      other.as.mutation(api.piccante.choose_piccante_size, { ...args, p_size: 3 }),
      other.as.mutation(api.piccante.hide_piccante_chili, { ...args, p_tile: 0 }),
      other.as.mutation(api.piccante.bite_piccante_chocolate, { ...args, p_tile: 0 }),
      other.as.mutation(api.piccante.sniff_piccante_chocolate, { ...args, p_tile: 0 }),
      other.as.mutation(api.piccante.start_piccante_rematch, args),
      other.as.mutation(api.piccante.mark_piccante_result_seen, { ...op(), p_game_id: s.gameId, p_game_number: 1 }),
    ];
    for (const result of await Promise.all(calls.map(failure))) expect(result.code).toBe("42501");
    expect((await view(other)).game).toBeNull();
    expect(await other.as.query(api.piccante.get_piccante_result, { p_game_number: 1 })).toBeNull();
    await other.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    expect((await other.as.mutation(api.piccante.ensure_piccante_game, {})).game!.id).not.toBe(s.gameId);
  });
});
describe("Piccante integration", () => {
  test("hides secrets, sniffs privately, reveals own-chili burn and stores game chat result", async () => {
    const s = await ready();
    expect((await view(s.b)).game).toMatchObject({ my_chili: 8, my_note: "You owe me cake", chilis: [], phase: "biting", turn_user_id: s.b.userId });
    expect(JSON.stringify(await view(s.b))).not.toContain("You owe me tea");
    await s.b.as.mutation(api.piccante.sniff_piccante_chocolate, { ...await s.args(s.b), p_tile: 0 });
    expect((await view(s.a)).game).toMatchObject({ my_sniff: null, partner_sniff_used: true });
    expect((await view(s.b)).game!.my_sniff).toEqual({ tile: 0, has_chili: true });
    await s.b.as.mutation(api.piccante.bite_piccante_chocolate, { ...await s.args(s.b), p_tile: 8 });
    const end = await view(s.a);
    expect(end.game).toMatchObject({ phase: "finished", winner_user_id: s.a.userId, my_wins: 1, games_finished: 1 });
    expect(end.game!.chilis).toHaveLength(2);
    expect(end.unseen_result!.game_number).toBe(1);
    expect(await s.a.as.query(api.piccante.get_piccante_result, { p_game_number: 1 })).toMatchObject({ phase: "finished" });
    const timeline = await s.a.as.query(api.gameConversations.get_game_chat_timeline, { p_couple_id: s.couple.coupleId, p_game_kind: "piccante", p_limit: 20 });
    expect(JSON.stringify(timeline)).toContain("piccante");
  });
  test("stale versions fail, retries are idempotent, rematch preserves unseen ending", async () => {
    const s = await ready();
    const move = { ...await s.args(s.b), p_tile: 0 };
    const first = await s.b.as.mutation(api.piccante.bite_piccante_chocolate, move);
    expect(await s.b.as.mutation(api.piccante.bite_piccante_chocolate, move)).toEqual(first);
    expect((await view(s.a)).game!.games_finished).toBe(1);
    expect((await failure(s.a.as.mutation(api.piccante.start_piccante_rematch, { ...await s.args(), p_expected_version: 1 }))).code).toBe("40001");
    await s.a.as.mutation(api.piccante.start_piccante_rematch, await s.args());
    expect((await view(s.a)).game).toMatchObject({ game_number: 2, starter_user_id: s.b.userId, phase: "choosing", my_wins: 1 });
    expect((await view(s.a)).unseen_result).toBeNull();
    expect((await view(s.b)).unseen_result).toMatchObject({ game_number: 1, phase: "finished" });
    await s.a.as.mutation(api.piccante.mark_piccante_result_seen, { ...op(), p_game_id: s.gameId, p_game_number: 1 });
    expect((await view(s.a)).unseen_result).toBeNull();
    expect((await view(s.b)).unseen_result).not.toBeNull();
  });
  test("seen metadata changes the query without consuming a move version", async () => {
    const s = await ready();
    await s.b.as.mutation(api.piccante.bite_piccante_chocolate, { ...await s.args(s.b), p_tile: 0 });
    const before = await view(s.a);
    for (let attempt = 0; attempt < 2; attempt++) {
      const seen = await s.a.as.mutation(api.piccante.mark_piccante_result_seen, {
        ...op(), p_game_id: s.gameId, p_game_number: 1,
      });
      expect(seen.game!.version).toBe(before.game!.version);
      expect(seen.unseen_result).toBeNull();
      expect((await view(s.a)).unseen_result).toBeNull();
      expect((await view(s.b)).unseen_result).not.toBeNull();
    }
    await s.a.as.mutation(api.piccante.start_piccante_rematch, {
      ...op(), p_game_id: s.gameId, p_expected_version: before.game!.version,
    });
    expect((await view(s.a)).game!.game_number).toBe(2);
  });
  test("access is checked again before replaying a completed operation", async () => {
    const s = await ready();
    const args = { ...await s.args(s.b), p_tile: 0 };
    await s.b.as.mutation(api.piccante.bite_piccante_chocolate, args);
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect((await failure(s.b.as.mutation(api.piccante.bite_piccante_chocolate, args))).code).toBe("42501");
  });
  test("waiting keys change on moves but not sniffs, cleanup removes all game rows", async () => {
    const s = await ready();
    const waits = () => s.t.run(ctx => piccanteBackend.waitingFor!(ctx, s.couple.coupleId, s.b.userId));
    const before = await waits();
    await s.b.as.mutation(api.piccante.sniff_piccante_chocolate, { ...await s.args(s.b), p_tile: 1 });
    expect(await waits()).toEqual(before);
    await s.b.as.mutation(api.piccante.bite_piccante_chocolate, { ...await s.args(s.b), p_tile: 1 });
    expect(await waits()).toEqual([]);
    await s.a.as.mutation(api.piccante.bite_piccante_chocolate, { ...await s.args(), p_tile: 0 });
    expect((await waits())[0].key).toMatch(/^result:/);
    expect(await s.t.run(ctx => piccanteBackend.deleteCoupleRows(ctx, s.couple.coupleId))).toBe(2);
  });
});
