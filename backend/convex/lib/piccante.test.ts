import { describe, expect, test } from "vitest";
import { applyPiccanteAction, newPiccanteState, piccanteView, type PiccanteState } from "./piccante";
const now = "2026-11-03T12:00:00.000Z";
const apply = (s: PiccanteState, user: string, action: Parameters<typeof applyPiccanteAction>[2]) => applyPiccanteAction(s, user, action, now);
function hidden(first = 0, second = 8) {
  let s = newPiccanteState("a", "b", 1, now);
  s = apply(s, "a", { kind: "size", size: 3 });
  s = apply(s, "a", { kind: "hide", tile: first, note: "Back rub!" });
  return apply(s, "b", { kind: "hide", tile: second, note: "My secret!" });
}
describe("Piccante rules", () => {
  test("either member can choose and becomes the first hider", () => {
    const initial = newPiccanteState("a", "b", 1, now);
    expect(initial.turn_user_id).toBeUndefined();
    expect(() => apply(initial, "outsider", { kind: "size", size: 3 })).toThrow();
    for (const chooser of ["a", "b"]) {
      const sized = apply(initial, chooser, { kind: "size", size: 5 });
      expect(sized).toMatchObject({ starter_user_id: chooser, turn_user_id: chooser, phase: "hiding", size: 5 });
      expect(sized.partner_user_id).toBe(chooser === "a" ? "b" : "a");
      expect(() => apply(sized, sized.partner_user_id, { kind: "hide", tile: 0 })).toThrow();
    }
  });
  test("starter hides first, second hider bites first, safe bites alternate", () => {
    const s = hidden();
    expect(s.turn_user_id).toBe("b");
    const bitten = apply(s, "b", { kind: "bite", tile: 1 });
    expect(bitten.turn_user_id).toBe("a");
    expect(bitten.bites).toEqual([{ tile: 1, user_id: "b" }]);
    expect(s.bites).toEqual([]);
    expect(() => apply(bitten, "a", { kind: "bite", tile: 1 })).toThrow();
    expect(() => apply(s, "a", { kind: "bite", tile: 2 })).toThrow();
  });
  test("every chili burns, including the biter's own", () => {
    for (const tile of [0, 8]) {
      const s = apply(hidden(), "b", { kind: "bite", tile });
      expect(s).toMatchObject({ phase: "finished", loser_user_id: "b", winner_user_id: "a" });
      expect(s.turn_user_id).toBeUndefined();
      expect(() => apply(s, "a", { kind: "bite", tile: 2 })).toThrow();
    }
  });
  test("same chocolate holds both chilis and burns once", () => {
    const s = apply(hidden(4, 4), "b", { kind: "bite", tile: 4 });
    expect(s.chilis.map(c => c.tile)).toEqual([4, 4]);
    expect(s.bites).toHaveLength(1);
    expect(s.winner_user_id).toBe("a");
  });
  test("sniff is private, limited to once, cannot target own chili, keeps turn", () => {
    const s = hidden();
    expect(() => apply(s, "b", { kind: "sniff", tile: 8 })).toThrow();
    const sniffed = apply(s, "b", { kind: "sniff", tile: 0 });
    expect(sniffed.sniffs).toEqual([{ user_id: "b", tile: 0, has_chili: true }]);
    expect(sniffed.turn_user_id).toBe("b");
    expect(() => apply(sniffed, "b", { kind: "sniff", tile: 1 })).toThrow();
    expect(apply(s, "b", { kind: "sniff", tile: 2 }).sniffs[0].has_chili).toBe(false);
  });
  test("validates dimensions, tile bounds, hide order and scalar note length", () => {
    const s = newPiccanteState("a", "b", 1, now);
    expect(() => apply(s, "b", { kind: "hide", tile: 0 })).toThrow();
    for (const size of [0, 2, 6, 3.5, Number.NaN]) expect(() => apply(s, "a", { kind: "size", size })).toThrow();
    const sized = apply(s, "a", { kind: "size", size: 3 });
    for (const tile of [-1, 9, 1.5, Number.NaN]) expect(() => apply(sized, "a", { kind: "hide", tile })).toThrow();
    expect(() => apply(sized, "a", { kind: "hide", tile: 0, note: "😀".repeat(61) })).toThrow();
    expect(() => apply(sized, "a", { kind: "hide", tile: 0, note: "Two\nlines" })).toThrow();
    expect(apply(sized, "a", { kind: "hide", tile: 0, note: "😀".repeat(60) }).chilis[0].note).toHaveLength(120);
    expect(() => apply(sized, "outsider", { kind: "hide", tile: 0 })).toThrow();
  });
  test("rematch swaps starter and resets secrets", () => {
    expect(() => apply(hidden(), "a", { kind: "rematch" })).toThrow();
    const finished = apply(hidden(), "b", { kind: "bite", tile: 0 });
    expect(apply(finished, "a", { kind: "rematch" })).toMatchObject({ game_number: 2, starter_user_id: "b", phase: "choosing", chilis: [], bites: [], sniffs: [] });
  });
  test("projection never contains partner chili, note or sniff before completion", () => {
    const state = apply(hidden(), "b", { kind: "sniff", tile: 0 });
    const game = { id: "game", version: 1, wins_by_user: {}, games_finished: 0 };
    const a = piccanteView(state, game, "a");
    expect(a).toMatchObject({ my_chili: 0, my_note: "Back rub!", my_sniff: null, partner_sniff_used: true, chilis: [] });
    expect(JSON.stringify(a)).not.toContain("My secret!");
    expect(piccanteView(state, game, "b").my_sniff).toEqual({ tile: 0, has_chili: true });
    const end = piccanteView(apply(state, "b", { kind: "bite", tile: 0 }), game, "a");
    expect(end.chilis).toHaveLength(2);
    expect(JSON.stringify(end)).toContain("My secret!");
  });
});
