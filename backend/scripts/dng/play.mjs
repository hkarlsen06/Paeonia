// Draw & Guess test helper. Plays as one test account through the admin key.
// Run from backend/ with Node 22 and CONVEX_SELF_HOSTED_ADMIN_KEY set:
//   node scripts/dng/play.mjs state
//   node scripts/dng/play.mjs pick <easy|medium|hard|custom> [custom word]
//   node scripts/dng/play.mjs draw <file.pkdrawing>
//   node scripts/dng/play.mjs fetch <out.pkdrawing>     (the current round's drawing)
//   node scripts/dng/play.mjs seen
//   node scripts/dng/play.mjs guess <text>
//   node scripts/dng/play.mjs giveup
// PLAY_AS picks the Clerk subject. The default is Hjalmar.
import { createHash, randomUUID } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { ConvexHttpClient } from "convex/browser";

const subject = process.env.PLAY_AS ?? "user_3KVUgELskLqEzQzJXz12wbkj2yS";
const client = new ConvexHttpClient(process.env.CONVEX_SELF_HOSTED_URL ?? "https://api.paeonia.no");
client.setAdminAuth(process.env.CONVEX_SELF_HOSTED_ADMIN_KEY, {
  subject,
  issuer: "https://clerk.paeonia.no",
  tokenIdentifier: `dng|${subject}`,
});

// A fresh client id per call is fine: every operation here is a one-shot.
const op = () => ({
  p_client_operation_id: randomUUID(),
  p_client_id: randomUUID(),
  p_client_sequence: 1,
  p_local_created_at: new Date().toISOString(),
});
const [command, ...rest] = process.argv.slice(2);
const screen = await client.query("drawAndGuess:get_draw_and_guess", {});
const game = screen.game;
const round = screen.current_round;

switch (command) {
  case "state": {
    const me = screen.partner_user_id === round?.drawer_user_id ? "guesser" : "drawer";
    const summary = {
      my_turn: game.turn_user_id !== screen.partner_user_id,
      state: game.state,
      language: screen.settings?.language,
      turn_number: game.turn_number,
      points: { me: game.my_points, partner: game.partner_points, shared: game.shared_points },
      choices: screen.choices?.map((c) => `${c.difficulty}: ${c.word}`),
      round: round && {
        id: round.id,
        my_role: me,
        state: round.state,
        word: me === "drawer" || round.state !== "guessing" ? round.word : "(hidden)",
        // What the guesser's tiles show: one underscore per letter.
        tiles: [...round.word].map((c) => (c === " " ? " " : "_")).join(""),
        has_drawing: Boolean(round.drawing_media_asset_id),
        attempts: round.attempts.map((a) => `${a.text}${a.correct ? " (correct)" : ""}`),
      },
    };
    console.log(JSON.stringify(summary, null, 1));
    break;
  }
  case "pick": {
    const [choice, ...word] = rest;
    const offered = screen.choices?.find((c) => c.difficulty === choice);
    const result = await client.mutation("drawAndGuess:pick_draw_word", {
      p_game_id: game.id,
      p_round_id: randomUUID(),
      p_choice: choice,
      p_custom_word: choice === "custom" ? word.join(" ") : null,
      p_word_id: offered?.word_id ?? null,
      ...op(),
    });
    console.log(JSON.stringify(result));
    break;
  }
  case "draw": {
    const data = readFileSync(rest[0]);
    const reserveOp = op();
    const [reservation] = await client.mutation("media:create_pending_media_upload", {
      p_reserved_parent_kind: "game_move",
      p_reserved_parent_id: round.id,
      p_upload_purpose: "game_drawing_payload",
      p_media_type: "drawing_payload",
      p_file_extension: "pkdrawing",
      p_couple_id: screen.couple_id,
      p_path_context: { game_id: game.id },
      ...reserveOp,
    });
    const upload = await fetch(reservation.upload_url, {
      method: "POST",
      headers: { "Content-Type": "application/octet-stream" },
      body: data,
    });
    const { storageId } = await upload.json();
    const [finalized] = await client.mutation("media:finalize_media_upload", {
      p_media_asset_id: reservation.media_asset_id,
      p_reserved_by_client_operation_id: reserveOp.p_client_operation_id,
      p_bucket: reservation.bucket,
      p_storage_path: reservation.storage_path,
      p_storage_id: storageId,
      p_reserved_parent_kind: "game_move",
      p_reserved_parent_id: round.id,
      p_upload_purpose: "game_drawing_payload",
      p_media_type: "drawing_payload",
      p_mime_type: "application/octet-stream",
      p_byte_size: data.length,
      p_sha256_hex: createHash("sha256").update(data).digest("hex"),
      p_width: null,
      p_height: null,
      p_duration_ms: null,
      ...op(),
    });
    const sent = await client.mutation("drawAndGuess:submit_drawing", {
      p_round_id: round.id,
      p_media_asset_id: finalized.media_asset_id,
      ...op(),
    });
    console.log(JSON.stringify(sent));
    break;
  }
  case "fetch": {
    const [signed] = await client.mutation("media:get_media_signed_url", {
      p_media_asset_id: round.drawing_media_asset_id,
      p_expires_in_seconds: 300,
    });
    const response = await fetch(signed.signed_url);
    if (!response.ok) throw new Error(`download failed: ${response.status}`);
    writeFileSync(rest[0], Buffer.from(await response.arrayBuffer()));
    console.log(`saved ${rest[0]}`);
    break;
  }
  case "seen":
    console.log(JSON.stringify(await client.mutation("drawAndGuess:mark_round_seen", { p_round_id: round.id })));
    break;
  case "guess":
    console.log(
      JSON.stringify(
        await client.mutation("drawAndGuess:submit_guess", { p_round_id: round.id, p_guess: rest.join(" "), ...op() }),
      ),
    );
    break;
  case "giveup":
    console.log(JSON.stringify(await client.mutation("drawAndGuess:give_up_round", { p_round_id: round.id, ...op() })));
    break;
  default:
    console.log("commands: state | pick <choice> [word] | draw <file> | fetch <out> | seen | guess <text> | giveup");
}
