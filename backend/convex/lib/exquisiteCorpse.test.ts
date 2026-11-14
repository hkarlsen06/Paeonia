import { describe, expect, test } from "vitest";
import {
  canSeePartContent,
  DECK_SIZE,
  dealIdeas,
  findIdea,
  hasStrip,
  isPartIndex,
  PART_NAMES,
  partJson,
  progressAfter,
  seededRandom,
  shuffledDeck,
  turnPushPart,
} from "./exquisiteCorpse";
import { EXQUISITE_CORPSE_IDEAS, type Idea, type IdeaLanguage, type IdeaPart } from "./exquisiteCorpseIdeas";

const LANGUAGES: IdeaLanguage[] = ["en", "nb"];
const ideas = (count: number, prefix = "idea"): Idea[] =>
  Array.from({ length: count }, (_, index) => ({ id: `${prefix}-${index}`, text: `${prefix} ${index}` }));
const ids = (list: readonly Idea[]) => list.map((idea) => idea.id);

describe("seededRandom", () => {
  test("the same seed gives the same numbers, all in [0, 1)", () => {
    const a = seededRandom("game:1:0");
    const b = seededRandom("game:1:0");
    const first = Array.from({ length: 50 }, () => a());
    expect(first).toEqual(Array.from({ length: 50 }, () => b()));
    expect(first.every((value) => value >= 0 && value < 1)).toBe(true);
  });

  test("a different seed gives different numbers", () => {
    const a = Array.from({ length: 5 }, seededRandom("game:1:0"));
    const b = Array.from({ length: 5 }, seededRandom("game:1:1"));
    expect(a).not.toEqual(b);
  });
});

describe("idea decks", () => {
  test("the same seed deals the same deck of 12 unique ideas from the list", () => {
    const list = ideas(50);
    const deck = shuffledDeck(list, "game:1:0");
    expect(deck).toEqual(shuffledDeck(list, "game:1:0"));
    expect(deck).toHaveLength(DECK_SIZE);
    expect(new Set(ids(deck)).size).toBe(DECK_SIZE);
    expect(ids(deck).every((id) => ids(list).includes(id))).toBe(true);
  });

  test("another figure or part deals another deck", () => {
    const list = ideas(50);
    expect(ids(shuffledDeck(list, "game:1:0"))).not.toEqual(ids(shuffledDeck(list, "game:2:0")));
    expect(ids(shuffledDeck(list, "game:1:0"))).not.toEqual(ids(shuffledDeck(list, "game:1:1")));
  });

  test("a short list deals every idea once, and the list stays as it was", () => {
    const list = ideas(5);
    const before = ids(list);
    const deck = shuffledDeck(list, "game:1:0");
    expect([...ids(deck)].sort()).toEqual([...before].sort());
    expect(ids(list)).toEqual(before);
  });

  test("every real list has unique ids and deals 12 ideas of its own", () => {
    for (const language of LANGUAGES) {
      PART_NAMES.forEach((part, partIndex) => {
        const list = EXQUISITE_CORPSE_IDEAS[language][part];
        expect(new Set(ids(list)).size, `${language} ${part} ids`).toBe(list.length);
        expect(list.every((idea) => idea.text.trim() !== ""), `${language} ${part} text`).toBe(true);
        const deck = dealIdeas(language, partIndex, "game:1:0");
        expect(deck).toHaveLength(Math.min(DECK_SIZE, list.length));
        expect(new Set(ids(deck)).size).toBe(deck.length);
        expect(ids(deck).every((id) => ids(list).includes(id))).toBe(true);
      });
    }
  });
});

describe("part progression", () => {
  const start = { figure_number: 1, figures_finished: 0 };
  const people = { drawer: "alice", partner: "bob" };

  test("the head, the body and the legs move on inside the same figure and pass the turn", () => {
    expect(progressAfter(start, 0, "fig", people)).toEqual({
      figureFinished: false,
      turn_user_id: "bob",
      figure_id: "fig",
      figure_number: 1,
      part_index: 1,
      figures_finished: 0,
    });
    expect(progressAfter(start, 1, "fig", people)).toMatchObject({ figureFinished: false, turn_user_id: "bob", figure_id: "fig", part_index: 2 });
    expect(progressAfter(start, 2, "fig", people)).toMatchObject({ figureFinished: false, turn_user_id: "bob", figure_id: "fig", part_index: 3 });
  });

  test("the feet finish the figure, and the feet drawer keeps the turn to start the next one with the head", () => {
    expect(progressAfter(start, 3, "fig", people)).toEqual({
      figureFinished: true,
      turn_user_id: "alice",
      figure_id: undefined,
      figure_number: 2,
      part_index: 0,
      figures_finished: 1,
    });
  });

  test("the starter draws the head and the legs, the partner the body and the feet, and the roles swap each figure", () => {
    let game = { ...start };
    let turn = "alice";
    const drawers: string[][] = [];
    for (let figure = 1; figure <= 2; figure++) {
      const parts: string[] = [];
      for (const partIndex of [0, 1, 2, 3]) {
        parts.push(turn);
        const next = progressAfter(game, partIndex, `fig-${figure}`, { drawer: turn, partner: turn === "alice" ? "bob" : "alice" });
        game = { figure_number: next.figure_number, figures_finished: next.figures_finished };
        turn = next.turn_user_id;
      }
      drawers.push(parts);
    }
    expect(drawers).toEqual([
      ["alice", "bob", "alice", "bob"],
      ["bob", "alice", "bob", "alice"],
    ]);
    expect(game).toEqual({ figure_number: 3, figures_finished: 2 });
    expect(turn).toBe("alice");
  });

  test("only the head, the body and the legs leave a strip", () => {
    expect([0, 1, 2, 3].map(hasStrip)).toEqual([true, true, true, false]);
    expect([-1, 0, 3, 4, 1.5, Number.NaN].map(isPartIndex)).toEqual([false, true, true, false, false, false]);
  });

  test("the turn push names the part that is now the partner's turn", () => {
    expect(turnPushPart(0)).toBe("body");
    expect(turnPushPart(1)).toBe("legs");
    expect(turnPushPart(2)).toBe("feet");
  });
});

describe("hiding", () => {
  const part = {
    id: "part-1",
    part_index: 1,
    drawer_user_id: "alice",
    created_at: "2026-10-10T12:00:00.000Z",
    strip_media_asset_id: "strip-1",
    drawing_media_asset_id: "drawing-1",
    idea_id: "body-robot",
    idea_text: "a robot",
  };

  test("the drawer sees the drawing and the idea of their own part", () => {
    expect(partJson(part, "alice", false)).toMatchObject({
      drawing_media_asset_id: "drawing-1",
      strip_media_asset_id: "strip-1",
      idea: { id: "body-robot", text: "a robot" },
    });
  });

  test("the partner gets the strip but neither the drawing nor the idea until the figure is finished", () => {
    expect(partJson(part, "bob", false)).toEqual({
      id: "part-1",
      part_index: 1,
      drawer_user_id: "alice",
      created_at: "2026-10-10T12:00:00.000Z",
      strip_media_asset_id: "strip-1",
      drawing_media_asset_id: null,
      idea: null,
    });
    expect(partJson(part, "bob", true)).toMatchObject({ drawing_media_asset_id: "drawing-1", idea: { text: "a robot" } });
  });

  test("the feet have no strip, and a part without an idea shows none", () => {
    const feet = { ...part, part_index: 3, strip_media_asset_id: undefined, idea_id: undefined, idea_text: undefined };
    expect(partJson(feet, "alice", true)).toMatchObject({ strip_media_asset_id: null, idea: null });
  });

  test("a finished figure shows everything to both partners", () => {
    expect(canSeePartContent(part, "bob", true)).toBe(true);
    expect(canSeePartContent(part, "bob", false)).toBe(false);
    expect(canSeePartContent(part, "alice", false)).toBe(true);
  });
});

describe("idea lookup", () => {
  const lists = (en: Idea[], nb: Idea[]) =>
    ({
      en: { head: en, body: [], legs: [], feet: [] },
      nb: { head: nb, body: [], legs: [], feet: [] },
    }) satisfies Record<IdeaLanguage, Record<IdeaPart, readonly Idea[]>>;

  test("finds an idea in the preferred language first", () => {
    const both = lists([{ id: "head-troll", text: "a troll" }], [{ id: "head-troll", text: "et troll" }]);
    expect(findIdea(0, "head-troll", "en", both)).toEqual({ id: "head-troll", text: "a troll" });
    expect(findIdea(0, "head-troll", "nb", both)).toEqual({ id: "head-troll", text: "et troll" });
  });

  test("falls back to the other language, so a deck dealt before a language change still works", () => {
    const split = lists([{ id: "head-owl", text: "an owl" }], [{ id: "head-elg", text: "en elg" }]);
    expect(findIdea(0, "head-elg", "en", split)).toEqual({ id: "head-elg", text: "en elg" });
    expect(findIdea(0, "head-owl", "nb", split)).toEqual({ id: "head-owl", text: "an owl" });
  });

  test("an unknown id, or an id of another part, is not found", () => {
    expect(findIdea(0, "head-nothing-like-this", "en")).toBeNull();
    const bodyId = EXQUISITE_CORPSE_IDEAS.en.body[0].id;
    expect(findIdea(1, bodyId, "en")).not.toBeNull();
    expect(findIdea(0, bodyId, "en")).toBeNull();
  });

  test("every real idea is found by its own id in its own language", () => {
    for (const language of LANGUAGES) {
      PART_NAMES.forEach((part, partIndex) => {
        for (const idea of EXQUISITE_CORPSE_IDEAS[language][part]) {
          expect(findIdea(partIndex, idea.id, language)).toEqual(idea);
        }
      });
    }
  });
});
