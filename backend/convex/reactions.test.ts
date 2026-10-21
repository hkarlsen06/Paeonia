import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { REACTION_TARGET_KINDS } from "./lib/validators";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import type { ReactionTargetKind } from "./lib/reactions";
import { endCouple, failure, op } from "./media.testing";
import { makeMemory } from "./reports.fixtures";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

// --- Things to react to ----------------------------------------------------------

type FeedKind = Exclude<ReactionTargetKind, "daily_answer" | "thread_message">;

/** Makes one thing of the kind in the couple's data. The first partner made it. */
type Maker = (t: TestConvex, couple: TestCouple) => Promise<string>;

const makers: Record<FeedKind, Maker> = {
  story: async (t, couple) => {
    const id = newUuid();
    await t.run((ctx) =>
      ctx.db.insert("stories", {
        id,
        couple_id: couple.coupleId,
        author_user_id: couple.first.userId,
        media_asset_id: newUuid(),
        created_at: NOW,
      }),
    );
    return id;
  },
  memory: async (t, couple) => (await makeMemory(t, couple)).id,
  widget_drawing: async (t, couple) => {
    const canvasId = newUuid();
    const id = newUuid();
    await t.run(async (ctx) => {
      await ctx.db.insert("widget_canvases", { id: canvasId, couple_id: couple.coupleId, created_at: NOW, updated_at: NOW });
      await ctx.db.insert("widget_drawing_revisions", {
        id,
        canvas_id: canvasId,
        author_user_id: couple.first.userId,
        format: "pkdrawing",
        format_version: 1,
        payload_media_asset_id: newUuid(),
        payload_bytes: 10,
        uncompressed_bytes: 10,
        compression: "none",
        renderer_version: 1,
        client_decode_validated_at: NOW,
        client_renderer_version: "1",
        client_validation_version: "1",
        moderation_status: "visible",
        created_at: NOW,
        updated_at: NOW,
      });
    });
    return id;
  },
  draw_and_guess_round: async (t, couple) => {
    const id = newUuid();
    await t.run((ctx) =>
      ctx.db.insert("game_moves", {
        id,
        game_id: newUuid(),
        couple_id: couple.coupleId,
        round_number: 1,
        drawer_user_id: couple.first.userId,
        guesser_user_id: couple.second.userId,
        state: "solved",
        difficulty: "easy",
        word: "cat",
        points: 1,
        drawing_media_asset_id: newUuid(),
        started_at: NOW,
        speed_bonus: 0,
        created_at: NOW,
        updated_at: NOW,
      }),
    );
    return id;
  },
  exquisite_corpse_figure: async (t, couple) => {
    const id = newUuid();
    await t.run((ctx) =>
      ctx.db.insert("exquisite_corpse_figures", {
        id,
        couple_id: couple.coupleId,
        game_id: newUuid(),
        number: 1,
        starter_user_id: couple.first.userId,
        created_at: NOW,
        finished_at: NOW,
        updated_at: NOW,
      }),
    );
    return id;
  },
  story_chain_story: async (t, couple) => {
    const id = newUuid();
    await t.run((ctx) =>
      ctx.db.insert("story_chain_stories", {
        id,
        game_id: newUuid(),
        couple_id: couple.coupleId,
        story_number: 1,
        starter_user_id: couple.first.userId,
        state: "finished",
        lines: [],
        seen_by: [],
        created_at: NOW,
        updated_at: NOW,
      }),
    );
    return id;
  },
};

const FEED_KINDS = REACTION_TARGET_KINDS.filter((kind): kind is FeedKind => kind !== "daily_answer" && kind !== "thread_message");

/** Breaks the thing the way its kind can be broken: deleted, hidden or not finished. */
const breakers: Record<FeedKind, (t: TestConvex, id: string) => Promise<void>> = {
  story: async (t, id) => {
    await t.run(async (ctx) => {
      const row = await ctx.db.query("stories").withIndex("by_uuid", (q) => q.eq("id", id)).unique();
      await ctx.db.patch(row!._id, { deleted_at: NOW });
    });
  },
  memory: async (t, id) => {
    await t.run(async (ctx) => {
      const row = await ctx.db.query("memories").withIndex("by_uuid", (q) => q.eq("id", id)).unique();
      await ctx.db.patch(row!._id, { moderation_status: "hidden" });
    });
  },
  widget_drawing: async (t, id) => {
    await t.run(async (ctx) => {
      const row = await ctx.db.query("widget_drawing_revisions").withIndex("by_uuid", (q) => q.eq("id", id)).unique();
      await ctx.db.patch(row!._id, { deleted_at: NOW });
    });
  },
  draw_and_guess_round: async (t, id) => {
    await t.run(async (ctx) => {
      const row = await ctx.db.query("game_moves").withIndex("by_uuid", (q) => q.eq("id", id)).unique();
      await ctx.db.patch(row!._id, { state: "guessing" });
    });
  },
  exquisite_corpse_figure: async (t, id) => {
    await t.run(async (ctx) => {
      const row = await ctx.db.query("exquisite_corpse_figures").withIndex("by_uuid", (q) => q.eq("id", id)).unique();
      await ctx.db.replace(row!._id, { ...row!, finished_at: undefined });
    });
  },
  story_chain_story: async (t, id) => {
    await t.run(async (ctx) => {
      const row = await ctx.db.query("story_chain_stories").withIndex("by_uuid", (q) => q.eq("id", id)).unique();
      await ctx.db.patch(row!._id, { state: "writing" });
    });
  },
};

const react = (user: TestUser, kind: ReactionTargetKind, id: string, emoji: string | null) =>
  user.as.mutation(api.reactions.set_reaction, { p_kind: kind, p_target_id: id, p_emoji: emoji });
const reactionsSeenBy = async (user: TestUser) => (await user.as.query(api.reactions.get_reactions, {})).reactions;
const rows = (t: TestConvex) => t.run((ctx) => ctx.db.query("reactions").collect());
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

const DENIED = { code: "42501", message: "active entitled couple access is required" };

// --- Who can react, and how ------------------------------------------------------

describe.each(FEED_KINDS)("set_reaction on %s", (kind) => {
  test("a partner reacts, changes the emoji and takes it back, and both read it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = await makers[kind](t, couple);

    await react(couple.second, kind, id.toUpperCase(), "❤️");
    const reaction = { target_kind: kind, target_id: id, user_id: couple.second.userId, emoji: "❤️" };
    expect(await reactionsSeenBy(couple.first)).toEqual([reaction]);
    expect(await reactionsSeenBy(couple.second)).toEqual([reaction]);

    await react(couple.second, kind, id, " 👍🏽 ");
    expect(await reactionsSeenBy(couple.first)).toEqual([{ ...reaction, emoji: "👍🏽" }]);
    await react(couple.first, kind, id, "😂");
    expect((await reactionsSeenBy(couple.second)).map((row) => row.emoji).sort()).toEqual(["👍🏽", "😂"].sort());
    expect(await rows(t)).toHaveLength(2);

    await react(couple.second, kind, id, null);
    await react(couple.second, kind, id, null);
    expect((await reactionsSeenBy(couple.first)).map((row) => row.user_id)).toEqual([couple.first.userId]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("strangers, former partners and unknown ids are refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = await makers[kind](t, couple);
    const stranger = await createSignedInUser(t);
    expect(await failure(react(stranger, kind, id, "❤️"))).toEqual(DENIED);
    expect(await failure(react(couple.first, kind, newUuid(), "❤️"))).toEqual(DENIED);
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(react(couple.second, kind, id, "❤️"))).toEqual(DENIED);
    expect(await rows(t)).toEqual([]);
  });

  test("a thing that is gone or not finished takes no reaction", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = await makers[kind](t, couple);
    await breakers[kind](t, id);
    expect(await failure(react(couple.second, kind, id, "❤️"))).toEqual({
      code: "23514",
      message: "reaction target is not available",
    });
    expect(await rows(t)).toEqual([]);
  });

  test("anything but one emoji is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const id = await makers[kind](t, couple);
    for (const emoji of ["love", "1", "❤️👍", "  ", ""]) {
      expect(await failure(react(couple.second, kind, id, emoji))).toEqual({
        code: "23514",
        message: "reaction must be one emoji",
      });
    }
  });
});

describe("get_reactions", () => {
  test("holds the couple's reactions only, and nothing from the question chat", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const story = await makers.story(t, couple);
    await react(couple.second, "story", story, "❤️");
    await react(other.second, "story", await makers.story(t, other), "😂");
    await t.run((ctx) =>
      ctx.db.insert("reactions", {
        target_kind: "thread_message",
        target_id: newUuid(),
        couple_id: couple.coupleId,
        user_id: couple.first.userId,
        emoji: "👍",
        created_at: NOW,
        updated_at: NOW,
      }),
    );
    expect(await reactionsSeenBy(couple.first)).toEqual([
      { target_kind: "story", target_id: story, user_id: couple.second.userId, emoji: "❤️" },
    ]);
    expect((await couple.first.as.query(api.reactions.get_reactions, {})).couple_id).toBe(couple.coupleId);
  });

  test("is refused to someone without a couple and to a former partner", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    expect((await failure(stranger.as.query(api.reactions.get_reactions, {}))).code).toBe("42501");
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect((await failure(couple.second.as.query(api.reactions.get_reactions, {}))).code).toBe("42501");
  });
});

// --- The push ----------------------------------------------------------------------

describe("the push for a first reaction", () => {
  test("tells the author of a story once, whatever the person does with the reaction afterwards", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId, { locale: "en" });
    await addDevice(t, couple.second.userId);
    const story = await makers.story(t, couple);

    await react(couple.second, "story", story, "❤️");
    const [row, ...rest] = await outbox(t);
    expect(rest).toEqual([]);
    expect(row).toMatchObject({
      kind: "reaction_added",
      recipient_user_id: couple.first.userId,
      title: "Second Partner reacted ❤️",
      body: "to your story",
      apns_collapse_id: `reaction_added:${couple.coupleId}`,
    });
    expect(row.payload).toEqual({
      type: "reaction_added",
      couple_id: couple.coupleId,
      target_kind: "story",
      target_id: story,
      emoji: "❤️",
      actor_user_id: couple.second.userId,
      route: "home",
      deeplink: `paeonia://stories/story?storyId=${story}`,
    });

    await react(couple.second, "story", story, "😂");
    await react(couple.second, "story", story, null);
    await react(couple.second, "story", story, "🥰");
    expect(await outbox(t)).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("is Norwegian on a Norwegian phone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId, { locale: "nb-NO" });
    await react(couple.second, "memory", await makers.memory(t, couple), "😍");
    expect(await outbox(t)).toMatchObject([{ title: "Second Partner reagerte 😍", body: "på minnet ditt" }]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("stays quiet on your own things", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId);
    await addDevice(t, couple.second.userId);
    await react(couple.first, "story", await makers.story(t, couple), "❤️");
    await react(couple.first, "widget_drawing", await makers.widget_drawing(t, couple), "❤️");
    expect(await outbox(t)).toEqual([]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("goes to the other partner for a game creation both made", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId);
    await addDevice(t, couple.second.userId);
    await react(couple.first, "exquisite_corpse_figure", await makers.exquisite_corpse_figure(t, couple), "😂");
    await react(couple.second, "draw_and_guess_round", await makers.draw_and_guess_round(t, couple), "👏");
    const sent = await outbox(t);
    expect(sent.map((row) => [row.recipient_user_id, row.body, row.payload.deeplink]).sort()).toEqual(
      [
        [couple.second.userId, "to your creature", "paeonia://games/exquisite-corpse"],
        [couple.first.userId, "to your round of Draw & Guess", "paeonia://games/draw-and-guess"],
      ].sort(),
    );
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test.each([
    ["story", "memories_enabled"],
    ["memory", "memories_enabled"],
    ["widget_drawing", "widget_updates_enabled"],
    ["draw_and_guess_round", "games_enabled"],
  ] as const)("a %s reaction follows the %s setting", async (kind, column) => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId);
    await t.run(async (ctx) => {
      const preference = await ctx.db
        .query("notification_preferences")
        .withIndex("by_user_id", (q) => q.eq("user_id", couple.first.userId))
        .unique();
      await ctx.db.patch(preference!._id, { [column]: false });
    });
    await react(couple.second, kind, await makers[kind](t, couple), "❤️");
    expect(await outbox(t)).toEqual([]);
    expect(await rows(t)).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

// --- Deleting ------------------------------------------------------------------------

describe("deleting reactions", () => {
  test("deleting a story or hiding a memory takes its reactions with it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const story = await makers.story(t, couple);
    const memory = await makers.memory(t, couple);
    const kept = await makers.story(t, couple);
    for (const [kind, id] of [["story", story], ["memory", memory], ["story", kept]] as const) {
      await react(couple.first, kind, id, "😂");
      await react(couple.second, kind, id, "❤️");
    }
    await couple.first.as.mutation(api.stories.delete_story, { p_story_id: story, ...op() });
    await couple.first.as.mutation(api.memories.hide_memory, { p_memory_id: memory, p_expected_revision: 1, ...op() });
    expect((await rows(t)).map((row) => row.target_id)).toEqual([kept, kept]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("hiding a memory takes the reactions on its comments with it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = newUuid();
    await couple.first.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: memoryId,
      p_title: "Our trip",
      p_memory_date: "2026-10-01",
      p_note_body: "note",
    });
    const [comment] = await couple.first.as.mutation(api.threads.create_memory_thread_with_message, {
      ...op(),
      p_memory_id: memoryId,
      p_body: "hello",
    });
    await react(couple.second, "thread_message", comment.message_id, "❤️");
    expect(await rows(t)).toHaveLength(1);

    await couple.first.as.mutation(api.memories.hide_memory, { p_memory_id: memoryId, p_expected_revision: 1, ...op() });

    expect(await rows(t)).toEqual([]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the relationship purge deletes the couple's reactions and spares other couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    await react(couple.second, "story", await makers.story(t, couple), "❤️");
    await react(couple.first, "exquisite_corpse_figure", await makers.exquisite_corpse_figure(t, couple), "❤️");
    const spared = await makers.story(t, other);
    await react(other.second, "story", spared, "❤️");

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    await t.run((ctx) => purgeCoupleContent(ctx, row));
    expect((await rows(t)).map((reaction) => reaction.target_id)).toEqual([spared]);
  });
});
