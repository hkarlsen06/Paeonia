import { canAccessCoupleContent, listActiveMembers } from "./access";
import { boardGameTurnToken, parseBoardGameTurnToken } from "./boardGameStore";
import { getByUuid } from "./db";
import type { GameBackend } from "./gameRegistry";
import { enqueueGamePush, TURN_REMINDER_AFTER_MS } from "./games";
import { addMs } from "./time";

// What the shared games code asks of the board games. `GAME_BACKENDS` (gameRegistry.ts) registers this
// one object under all three kinds, and every hook works on the couple's rows of every board game.
// Pushes are checked by game id. The cleanup and the reminder cron run once per registered kind,
// and the later runs find nothing left to do (the rows are already deleted, the reminders already marked).

export const boardGameBackend: GameBackend = {
  /**
   * A turn push needs the pushed move to still be the last one and the turn to still be the recipient's.
   * A result push needs the pushed game to be finished and still held as the current or the previous game.
   * A reminder needs the reminded turn to still be theirs and still waiting.
   */
  async pushStillWanted(ctx, push, payload, recipientUserId) {
    const game = await getByUuid(ctx, "board_games", typeof payload.game_id === "string" ? payload.game_id : null);
    if (!game) return false;
    const turn = parseBoardGameTurnToken(payload.round_id);
    switch (push) {
      case "game_turn_ready":
        return (
          turn !== null &&
          game.status === "playing" &&
          game.game_number === turn.gameNumber &&
          game.moves.length === turn.moveCount &&
          game.turn_user_id === recipientUserId
        );
      case "game_result":
        return turn !== null && ((game.status === "finished" && game.game_number === turn.gameNumber) || game.previous?.game_number === turn.gameNumber);
      case "game_turn_reminder":
        // The token names the reminded turn, so a reminder that waited in the outbox never goes out for a later turn.
        return (
          turn !== null &&
          game.status === "playing" &&
          game.game_number === turn.gameNumber &&
          game.moves.length === turn.moveCount &&
          game.turn_user_id === recipientUserId &&
          game.turn_reminder_sent_at !== undefined
        );
      case "game_invite":
        return true;
    }
  },

  /**
   * Each of the couple's board games in play whose turn is the user's. A finished game counts for
   * nobody: no row keeps whether a partner has seen the ending.
   */
  async waitingFor(ctx, coupleId, userId) {
    const games = await ctx.db.query("board_games").withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId)).collect();
    return games.filter((game) => game.status === "playing" && game.turn_user_id === userId).length;
  },

  async deleteCoupleRows(ctx, coupleId) {
    const games = await ctx.db.query("board_games").withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId)).collect();
    const marks = await ctx.db.query("board_game_marks").withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId)).collect();
    const history = await ctx.db
      .query("board_game_history")
      .withIndex("by_couple_id_kind_game_number", (q) => q.eq("couple_id", coupleId))
      .collect();
    for (const row of [...games, ...marks, ...history]) await ctx.db.delete(row._id);
    return games.length + marks.length + history.length;
  },

  /**
   * The single reminder for a turn that waited 72 hours. `turn_reminder_sent_at` is set before anything
   * else and cleared only when a new turn begins. A finished game has it set from its last move.
   */
  async sendDueTurnReminders(ctx, now) {
    const due = await ctx.db
      .query("board_games")
      .withIndex("by_turn_reminder_sent_at_turn_started_at", (q) =>
        q.eq("turn_reminder_sent_at", undefined).lte("turn_started_at", addMs(now, -TURN_REMINDER_AFTER_MS)),
      )
      .take(100);
    let sent = 0;
    for (const game of due) {
      // A plain patch, not patchBoardGame: a version bump would refuse the move a phone is sending right now.
      await ctx.db.patch(game._id, { turn_reminder_sent_at: now });
      const recipientId = game.turn_user_id;
      if (game.status !== "playing" || !recipientId || !(await canAccessCoupleContent(ctx, recipientId, game.couple_id))) continue;
      const waiting = (await listActiveMembers(ctx, game.couple_id)).find((member) => member.user_id !== recipientId);
      sent += await enqueueGamePush(ctx, {
        kind: "game_turn_reminder",
        game_kind: game.kind,
        couple_id: game.couple_id,
        game_id: game.id,
        round_id: boardGameTurnToken(game),
        actor_user_id: waiting?.user_id ?? recipientId,
        recipient_user_id: recipientId,
        dedupe_key: `game_turn_reminder:${game.id}:${game.game_number}:${game.turn_started_at}`,
      });
    }
    return sent;
  },
};
