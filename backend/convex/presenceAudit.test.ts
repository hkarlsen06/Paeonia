import { afterEach, expect, test, vi } from "vitest";
import { api, internal, components } from "./_generated/api";
import {
  addDevice,
  newTest,
  createCouple,
  createSignedInUser,
} from "./test.setup";
import { op, failure } from "./media.testing";
import { chatTypingRoom, removePresenceRooms } from "./lib/presence";
import { seedQuestion, answeredRound } from "./dailyChat.setup";
afterEach(() => vi.useRealTimers());
const start = () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00Z"));
};
test.each(["game_turn_ready", "game_result"])(
  "queued %s is suppressed when the recipient opens the game",
  async (kind) => {
    start();
    const t = newTest();
    const c = await createCouple(t);
    await addDevice(t, c.second.userId);
    await c.first.as.mutation(api.games.set_game_settings, {
      p_play_style: "against",
      p_language: "en",
    });
    const g = await c.first.as.mutation(api.boardGames.ensure_board_game, {
      p_kind: "connect_four",
    });
    await c.first.as.mutation(api.boardGames.make_move, {
      ...op(),
      p_game_id: g.id,
      p_expected_version: g.version,
      p_move: 0,
    });
    if (kind === "game_result") {
      let game = (
        await c.first.as.query(api.boardGames.get_board_games, {})
      ).games.find((row) => row.kind === "connect_four")!;
      for (const [index, move] of [1, 0, 1, 0, 1, 0].entries()) {
        const caller = index % 2 === 0 ? c.second : c.first;
        await caller.as.mutation(api.boardGames.make_move, {
          ...op(),
          p_game_id: game.id,
          p_expected_version: game.version,
          p_move: move,
        });
        game = (
          await c.first.as.query(api.boardGames.get_board_games, {})
        ).games.find((row) => row.kind === "connect_four")!;
      }
    }
    const row = (
      await t.run((ctx) => ctx.db.query("notification_outbox").collect())
    ).find((r) => r.kind === kind)!;
    expect(row).toBeTruthy();
    await c.second.as.mutation(api.games.set_game_presence, {
      p_kind: "connect_four",
      p_present: true,
    });
    expect(
      (await c.first.as.query(api.games.get_games_overview, {})).presence.find(
        (e) => e.kind === "connect_four",
      )?.partner_present,
    ).toBe(true);
    const prepared = await t.mutation(internal.pushQueue.prepare_notification, {
      outbox_id: row.id,
    });
    expect(prepared).toBeNull();
  },
  60_000,
);
test("read receipts advance by message id within the same millisecond", async () => {
  start();
  const t = newTest();
  const c = await createCouple(t);
  const q = await seedQuestion(t);
  await answeredRound(t, c, q);
  const [a] = await c.first.as.mutation(
    api.threads.create_daily_question_thread_with_message,
    { ...op(), p_couple_id: c.coupleId, p_question_id: q.id, p_body: "first" },
  );
  const [b] = await c.first.as.mutation(api.threads.send_thread_message, {
    ...op(),
    p_thread_id: a.thread_id,
    p_body: "second",
  });
  const [older, newer] = [a.message_id, b.message_id].sort();
  await c.second.as.mutation(api.chatPresence.mark_thread_read, {
    p_thread_id: a.thread_id,
    p_message_id: older,
  });
  await c.second.as.mutation(api.chatPresence.mark_thread_read, {
    p_thread_id: a.thread_id,
    p_message_id: newer,
  });
  const state = await c.first.as.query(api.chatPresence.get_chat_presence, {
    p_couple_id: c.coupleId,
    p_subject_kind: "daily_question",
    p_subject_id: q.id,
  });
  expect(state.partner_last_read_message_id).toBe(newer);
}, 60_000);
test("cleanup drains more than 1000 offline rooms", async () => {
  start();
  const t = newTest();
  const c = await createCouple(t);
  await t.run(async (ctx) => {
    for (let i = 0; i < 1001; i++) {
      const token = await ctx.runMutation(
        components.presence.public.heartbeat,
        {
          roomId: chatTypingRoom(c.coupleId, "subject-" + i),
          userId: c.first.userId,
          sessionId: "session-" + i,
          interval: 1000000,
        },
      );
      await ctx.runMutation(components.presence.public.disconnect, {
        sessionToken: token.sessionToken,
      });
    }
  });
  await t.run((ctx) =>
    ctx.runMutation(components.presence.public.heartbeat, {
      roomId: "unrelated:typing:keep",
      userId: c.first.userId,
      sessionId: "unrelated",
      interval: 1000000,
    }),
  );
  await t.run((ctx) => removePresenceRooms(ctx, [c.first.userId], c.coupleId));
  const unrelated = await t.run((ctx) =>
    ctx.runQuery(components.presence.public.listUser, {
      userId: c.first.userId,
      limit: 2000,
    }),
  );
  expect(unrelated.map((room) => room.roomId)).toEqual([
    "unrelated:typing:keep",
  ]);
  await t.run((ctx) => removePresenceRooms(ctx, [c.first.userId], ""));
  const left = await t.run((ctx) =>
    ctx.runQuery(components.presence.public.listUser, {
      userId: c.first.userId,
      limit: 2000,
    }),
  );
  expect(left).toHaveLength(0);
}, 60_000);

test("a stranger cannot advance a couple's read receipt", async () => {
  const t = newTest();
  const c = await createCouple(t);
  const q = await seedQuestion(t);
  await answeredRound(t, c, q);
  const [message] = await c.first.as.mutation(
    api.threads.create_daily_question_thread_with_message,
    {
      ...op(),
      p_couple_id: c.coupleId,
      p_question_id: q.id,
      p_body: "Private",
    },
  );
  const stranger = await createSignedInUser(t);
  expect(
    (
      await failure(
        stranger.as.mutation(api.chatPresence.mark_thread_read, {
          p_thread_id: message.thread_id,
          p_message_id: message.message_id,
        }),
      )
    ).code,
  ).toBe("42501");
});
