// Board games test helper. Plays as a test account through the admin key, so
// one simulator can play against the other partner. Run from backend/ with
// Node 22 and CONVEX_SELF_HOSTED_ADMIN_KEY set:
//   node scripts/boardGames/play.mjs state [kind]
//   node scripts/boardGames/play.mjs start <kind>
//   node scripts/boardGames/play.mjs move <kind> <move> [stake]
//   node scripts/boardGames/play.mjs rematch <kind>
//   node scripts/boardGames/play.mjs auto <kind> [moves]   (both partners play random legal moves)
// <kind> is connect_four, dots_and_boxes or ultimate_tic_tac_toe. A move is a
// column (0 to 6), a line (0 to 39) or a cell (0 to 80). PLAY_AS=first|second
// picks the account. The default is first (Hjalmar).
import { randomUUID } from "node:crypto";
import { ConvexHttpClient } from "convex/browser";

const SUBJECTS = { first: "user_3KVUgELskLqEzQzJXz12wbkj2yS", second: "user_3KVV3oyVHCORVwIObVOjvLojmpe" };
const MOVE_LIMITS = { connect_four: 7, dots_and_boxes: 40, ultimate_tic_tac_toe: 81 };

function clientFor(account) {
  const subject = SUBJECTS[account];
  const client = new ConvexHttpClient(process.env.CONVEX_SELF_HOSTED_URL ?? "https://api.paeonia.no");
  client.setAdminAuth(process.env.CONVEX_SELF_HOSTED_ADMIN_KEY, {
    subject,
    issuer: "https://clerk.paeonia.no",
    tokenIdentifier: `boardGames|${subject}`,
  });
  return client;
}

// A fresh client id per call is fine: every operation here is a one-shot.
const op = () => ({
  p_client_operation_id: randomUUID(),
  p_client_id: randomUUID(),
  p_client_sequence: 1,
  p_local_created_at: new Date().toISOString(),
});

async function gameOf(client, kind) {
  const state = await client.query("boardGames:get_board_games", {});
  return { state, game: state.games.find((game) => game.kind === kind) ?? null };
}

function summary(state, game) {
  if (!game) return { started: false };
  return {
    game_number: game.game_number,
    status: game.status,
    version: game.version,
    moves: game.moves.join(" "),
    my_turn: game.turn_user_id === state.user_id,
    winner: game.winner_user_id === null ? null : game.winner_user_id === state.user_id ? "me" : "partner",
    stake: game.stake,
    photo: game.photo_media_asset_id,
    score: { mine: game.my_wins, partner: game.partner_wins, draws: game.draws, games: game.games_finished },
  };
}

/** Plays one random legal move: the server refuses an illegal one with 23514, so try another. */
async function playRandom(client, game) {
  const tried = new Set();
  const limit = MOVE_LIMITS[game.kind];
  while (tried.size < limit) {
    const move = Math.floor(Math.random() * limit);
    if (tried.has(move)) continue;
    tried.add(move);
    try {
      return await client.mutation("boardGames:make_move", {
        ...op(),
        p_game_id: game.id,
        p_expected_version: game.version,
        p_move: move,
      });
    } catch (error) {
      // A refusal arrives as a ConvexError with { code, message } in `data`.
      if (error?.data?.message !== "that move is not allowed") throw error;
    }
  }
  throw new Error("no legal move left");
}

const [command, kind, ...rest] = process.argv.slice(2);
const account = process.env.PLAY_AS ?? "first";
const client = clientFor(account);

switch (command) {
  case "state": {
    const state = await client.query("boardGames:get_board_games", {});
    const games = state.games.filter((game) => !kind || game.kind === kind);
    console.log(JSON.stringify(Object.fromEntries(games.map((game) => [game.kind, summary(state, game)])), null, 1));
    break;
  }
  case "start": {
    await client.mutation("boardGames:ensure_board_game", { p_kind: kind });
    // The game may already exist and have been started by the other account.
    const { state, game } = await gameOf(client, kind);
    console.log(JSON.stringify(summary(state, game), null, 1));
    break;
  }
  case "move": {
    const { state, game } = await gameOf(client, kind);
    const [move, stake] = rest;
    const answer = await client.mutation("boardGames:make_move", {
      ...op(),
      p_game_id: game.id,
      p_expected_version: game.version,
      p_move: Number(move),
      ...(stake ? { p_stake: stake } : {}),
    });
    console.log(JSON.stringify(summary(state, answer), null, 1));
    break;
  }
  case "rematch": {
    const { state, game } = await gameOf(client, kind);
    const answer = await client.mutation("boardGames:start_rematch", {
      ...op(),
      p_game_id: game.id,
      p_expected_version: game.version,
    });
    console.log(JSON.stringify(summary(state, answer), null, 1));
    break;
  }
  case "auto": {
    // Both partners play until the game ends, or for the given number of moves.
    const budget = rest[0] ? Number(rest[0]) : Infinity;
    const clients = { first: clientFor("first"), second: clientFor("second") };
    let played = 0;
    while (played < budget) {
      const { state, game } = await gameOf(clients.first, kind);
      if (!game || game.status !== "playing") break;
      const mover = game.turn_user_id === state.user_id ? clients.first : clients.second;
      const { game: current } = await gameOf(mover, kind);
      await playRandom(mover, current);
      played += 1;
    }
    const { state, game } = await gameOf(client, kind);
    console.log(JSON.stringify({ played, ...summary(state, game) }, null, 1));
    break;
  }
  default:
    console.error("usage: play.mjs state|start|move|rematch|auto <kind> ...");
    process.exit(2);
}
