// Exquisite corpse test helper. Plays one test account through the admin key, also live over the relay.
// Run from backend/ with Node 22 and CONVEX_SELF_HOSTED_ADMIN_KEY set:
//   node scripts/corpse/play.mjs ensure                         creates the couple's game (this account starts)
//   node scripts/corpse/play.mjs state
//   node scripts/corpse/play.mjs draw <strokes.json> [idea]    sends the next part. idea: a deck index, default none
//   node scripts/corpse/play.mjs live <strokes.json> [seconds]  joins the relay as the drawer, streams the pen and
//                                                               the strip stroke by stroke, taps Done, then sends
//   node scripts/corpse/play.mjs watch [seconds]                joins the relay and prints what the partner sends
//   node scripts/corpse/play.mjs fetch <dir>                    downloads every file of the game this account may read
//   node scripts/corpse/play.mjs check-hidden                   tries to read the partner's unfinished parts (must fail)
//   node scripts/corpse/play.mjs seen                           marks the latest finished figure's reveal seen
//   node scripts/corpse/play.mjs presence <on|off>
//   node scripts/corpse/play.mjs invite
// strokes.json is the dng/pk.swift format on the 320 point canvas. PK is the compiled pk.swift (default /tmp/dng-pk).
// PLAY_AS picks the account: "first" (Hjalmar, the default), "second" (Elena), or a Clerk subject.
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ConvexHttpClient } from "convex/browser";
import WebSocket from "ws";

const ACCOUNTS = { first: "user_3KVUgELskLqEzQzJXz12wbkj2yS", second: "user_3KVV3oyVHCORVwIObVOjvLojmpe" };
const subject = ACCOUNTS[process.env.PLAY_AS ?? "first"] ?? process.env.PLAY_AS;
const pk = process.env.PK ?? "/tmp/dng-pk";
const client = new ConvexHttpClient(process.env.CONVEX_SELF_HOSTED_URL ?? "https://api.paeonia.no");
client.setAdminAuth(process.env.CONVEX_SELF_HOSTED_ADMIN_KEY, {
  subject,
  issuer: "https://clerk.paeonia.no",
  tokenIdentifier: `corpse|${subject}`,
});

const SIDE = 320;
const FOLD_Y = SIDE * 0.88;
const PARTS = ["head", "body", "legs"];

const op = () => ({
  p_client_operation_id: randomUUID(),
  p_client_id: randomUUID(),
  p_client_sequence: 1,
  p_local_created_at: new Date().toISOString(),
});
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The app's `ExquisiteCorpseIDs`: name-based UUID v5 in the game's namespace, so a part sent here has
// the id the partner's phone expects for live messages.
const NAMESPACE = Buffer.from([
  0x6b, 0x2d, 0x0e, 0x31, 0x9c, 0x47, 0x4e, 0x5a, 0x8f, 0x13, 0x55, 0xc2, 0x70, 0xa4, 0x19, 0xe8,
]);
function uuid5(name) {
  const bytes = createHash("sha1").update(Buffer.concat([NAMESPACE, Buffer.from(name, "utf8")])).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
const figureIdFor = (game) => game.figure_id ?? uuid5(`figure:${game.id}:${game.figure_number}`);
const partIdFor = (game, userId) => uuid5(`part:${game.id}:${game.figure_number}:${game.part_index}:${userId}`);

// The strip: every stroke cut to y >= FOLD_Y, with a point on the fold where it crosses. The app cuts
// the real curve. A polyline cut is close enough for testing.
function clipToStrip(strokes) {
  const out = [];
  for (const stroke of strokes) {
    let run = [];
    const flush = () => {
      if (run.length > 1) out.push({ ...stroke, points: run });
      run = [];
    };
    stroke.points.forEach(([x, y], i) => {
      const [px, py] = i > 0 ? stroke.points[i - 1] : [x, y];
      const crossing = (py < FOLD_Y) !== (y < FOLD_Y) && i > 0;
      const atFold = () => {
        const t = (FOLD_Y - py) / (y - py);
        return [px + (x - px) * t, FOLD_Y];
      };
      if (y >= FOLD_Y) {
        if (crossing) run.push(atFold());
        run.push([x, y]);
      } else if (crossing) {
        run.push(atFold());
        flush();
      }
    });
    flush();
  }
  return out;
}

function makeDrawing(strokes, name) {
  const dir = join(tmpdir(), "corpse-play");
  mkdirSync(dir, { recursive: true });
  const json = join(dir, `${name}.json`);
  const out = join(dir, `${name}.pkdrawing`);
  writeFileSync(json, JSON.stringify(strokes));
  execFileSync(pk, ["make", json, out], { stdio: "ignore" });
  return readFileSync(out);
}

async function upload(data, screen, game, partId, purpose) {
  const reserveOp = op();
  const shared = {
    p_reserved_parent_kind: "exquisite_corpse_part",
    p_reserved_parent_id: partId,
    p_upload_purpose: purpose,
    p_media_type: "drawing_payload",
  };
  const [reservation] = await client.mutation("media:create_pending_media_upload", {
    ...shared,
    p_file_extension: "pkdrawing",
    p_couple_id: screen.couple_id,
    p_path_context: { game_id: game.id },
    ...reserveOp,
  });
  const response = await fetch(reservation.upload_url, {
    method: "POST",
    headers: { "Content-Type": "application/octet-stream" },
    body: data,
  });
  const { storageId } = await response.json();
  const [finalized] = await client.mutation("media:finalize_media_upload", {
    ...shared,
    p_media_asset_id: reservation.media_asset_id,
    p_reserved_by_client_operation_id: reserveOp.p_client_operation_id,
    p_bucket: reservation.bucket,
    p_storage_path: reservation.storage_path,
    p_storage_id: storageId,
    p_mime_type: "application/octet-stream",
    p_byte_size: data.length,
    p_sha256_hex: createHash("sha256").update(data).digest("hex"),
    p_width: null,
    p_height: null,
    p_duration_ms: null,
    ...op(),
  });
  return finalized.media_asset_id;
}

async function sendPart(screen, strokes, ideaArg) {
  const game = screen.game;
  if (game.turn_user_id !== screen.user_id) throw new Error("it is not this account's turn");
  const partId = partIdFor(game, screen.user_id);
  const drawingId = await upload(makeDrawing(strokes, "part"), screen, game, partId, "exquisite_corpse_drawing");
  const stripId =
    game.part_index < 2
      ? await upload(makeDrawing(clipToStrip(strokes), "strip"), screen, game, partId, "exquisite_corpse_strip")
      : null;
  const idea = ideaArg === undefined || ideaArg === "none" ? null : screen.ideas[Number(ideaArg)] ?? null;
  return await client.mutation("exquisiteCorpse:submit_exquisite_corpse_part", {
    p_game_id: game.id,
    p_figure_id: figureIdFor(game),
    p_part_id: partId,
    p_part_index: game.part_index,
    p_drawing_media_asset_id: drawingId,
    p_strip_media_asset_id: stripId,
    p_idea_id: idea?.id ?? null,
    ...op(),
  });
}

// --- Relay ------------------------------------------------------------------

async function joinRelay(role, onGame) {
  const ticket = await client.mutation("games:create_game_live_ticket", { p_kind: "exquisite_corpse" });
  if (!ticket) throw new Error("the relay is not set up");
  const socket = new WebSocket(ticket.url, { headers: { Authorization: `Bearer ${ticket.ticket}` } });
  let ownId = null;
  const hello = (needsCanvas) =>
    socket.send(JSON.stringify({ type: "hello", from: ownId, role, ...(needsCanvas ? { needsCanvas: true } : {}) }));
  const room = { socket, peers: 0, arrived: null };
  socket.on("message", (raw) => {
    const message = JSON.parse(raw.toString());
    if (message.game === "exquisite_corpse") return onGame?.(message.message);
    switch (message.type) {
      case "welcome":
        ownId = message.id;
        room.peers = message.peers ?? 0;
        hello(false);
        if (room.peers > 0) room.arrived?.();
        break;
      case "joined":
        room.peers += 1;
        hello(false);
        room.arrived?.();
        break;
      case "left":
        room.peers = Math.max(0, room.peers - 1);
        console.log("partner left");
        break;
      case "hello":
        console.log(`partner says ${message.role}`);
        break;
      default:
        break;
    }
  });
  await new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
  room.sendGame = (message) => socket.send(JSON.stringify({ game: "exquisite_corpse", message }));
  return room;
}

// --- Commands ---------------------------------------------------------------

const [command, ...rest] = process.argv.slice(2);
const screen = await client.query("exquisiteCorpse:get_exquisite_corpse", {});
const game = screen.game;

switch (command) {
  case "ensure":
    console.log(JSON.stringify(await client.mutation("exquisiteCorpse:ensure_exquisite_corpse_game", {})));
    break;
  case "state": {
    const describe = (figure) =>
      figure && {
        id: figure.id,
        number: figure.number,
        finished: Boolean(figure.finished_at),
        my_reveal_seen: Boolean(figure.my_reveal_seen_at),
        starred: figure.starred_by_me,
        parts: figure.parts.map((part) => ({
          part: PARTS[part.part_index],
          mine: part.drawer_user_id === screen.user_id,
          strip: Boolean(part.strip_media_asset_id),
          drawing: Boolean(part.drawing_media_asset_id),
          idea: part.idea?.text ?? null,
        })),
      };
    console.log(
      JSON.stringify(
        {
          my_turn: game?.turn_user_id === screen.user_id,
          next_part: game && PARTS[game.part_index],
          figure_number: game?.figure_number,
          figures_finished: game?.figures_finished,
          current_figure: describe(screen.current_figure),
          latest_finished: describe(screen.recent_figures[0]),
          ideas: screen.ideas.map((idea, index) => `${index}: ${idea.text}`),
        },
        null,
        1,
      ),
    );
    break;
  }
  case "draw":
    console.log(JSON.stringify(await sendPart(screen, JSON.parse(readFileSync(rest[0], "utf8")), rest[1])));
    break;
  case "live": {
    const strokes = JSON.parse(readFileSync(rest[0], "utf8"));
    const seconds = Number(rest[1] ?? 20);
    const partId = partIdFor(game, screen.user_id);
    const room = await joinRelay("drawing");
    let drawn = [];
    const sendStrip = () =>
      room.sendGame({ type: "strip", part: partId.toUpperCase(), drawing: makeDrawing(clipToStrip(drawn), "live-strip").toString("base64") });
    // The partner may join late: they get the whole strip again, as the app does.
    room.arrived = sendStrip;
    const pause = (seconds * 1000) / Math.max(1, strokes.reduce((sum, stroke) => sum + stroke.points.length, 0));
    for (const stroke of strokes) {
      for (const [x, y] of stroke.points) {
        room.sendGame({ type: "pen", part: partId.toUpperCase(), x: Math.round((x / SIDE) * 20) / 20, y: Math.round((y / SIDE) * 20) / 20 });
        await sleep(Math.max(125, pause));
      }
      room.sendGame({ type: "pen", part: partId.toUpperCase() });
      drawn = [...drawn, stroke];
      sendStrip();
      console.log(`stroke ${drawn.length} of ${strokes.length}`);
    }
    room.sendGame({ type: "done", part: partId.toUpperCase() });
    console.log(JSON.stringify(await sendPart(screen, strokes, rest[2])));
    await sleep(3000);
    room.socket.close();
    break;
  }
  case "watch": {
    const seconds = Number(rest[0] ?? 60);
    const room = await joinRelay("watching", (message) => {
      if (message.type === "strip") console.log(`strip of ${message.part}: ${message.drawing.length} base64 chars`);
      else console.log(JSON.stringify(message));
    });
    await sleep(seconds * 1000);
    room.socket.close();
    break;
  }
  case "fetch": {
    mkdirSync(rest[0], { recursive: true });
    const figures = [screen.current_figure, ...screen.recent_figures].filter(Boolean);
    for (const figure of figures) {
      for (const part of figure.parts) {
        for (const [kind, id] of [["drawing", part.drawing_media_asset_id], ["strip", part.strip_media_asset_id]]) {
          if (!id) continue;
          const [signed] = await client.mutation("media:get_media_signed_url", { p_media_asset_id: id, p_expires_in_seconds: 300 });
          const response = await fetch(signed.signed_url);
          if (!response.ok) throw new Error(`download failed: ${response.status}`);
          const file = join(rest[0], `figure${figure.number}-${PARTS[part.part_index]}-${kind}.pkdrawing`);
          writeFileSync(file, Buffer.from(await response.arrayBuffer()));
          console.log(`saved ${file}`);
        }
      }
    }
    break;
  }
  case "check-hidden": {
    // The partner's own view names their full drawings. This account must not be able to read them
    // before the figure is finished, and must be able to read every strip.
    const partnerSubject = subject === ACCOUNTS.first ? ACCOUNTS.second : ACCOUNTS.first;
    const partner = new ConvexHttpClient(process.env.CONVEX_SELF_HOSTED_URL ?? "https://api.paeonia.no");
    partner.setAdminAuth(process.env.CONVEX_SELF_HOSTED_ADMIN_KEY, {
      subject: partnerSubject,
      issuer: "https://clerk.paeonia.no",
      tokenIdentifier: `corpse|${partnerSubject}`,
    });
    const theirs = await partner.query("exquisiteCorpse:get_exquisite_corpse", {});
    const figure = theirs.current_figure;
    for (const part of figure?.parts ?? []) {
      if (part.drawer_user_id === screen.user_id) continue;
      for (const [kind, id] of [["drawing", part.drawing_media_asset_id], ["strip", part.strip_media_asset_id]]) {
        if (!id) continue;
        try {
          await client.mutation("media:get_media_signed_url", { p_media_asset_id: id, p_expires_in_seconds: 60 });
          console.log(`${PARTS[part.part_index]} ${kind}: readable`);
        } catch (error) {
          console.log(`${PARTS[part.part_index]} ${kind}: refused (${String(error.message).split("\n")[0].slice(0, 120)})`);
        }
      }
    }
    break;
  }
  case "seen": {
    const figure = screen.recent_figures[0];
    console.log(JSON.stringify(await client.mutation("exquisiteCorpse:mark_exquisite_corpse_reveal_seen", { p_figure_id: figure.id })));
    break;
  }
  case "presence":
    console.log(JSON.stringify(await client.mutation("games:set_game_presence", { p_kind: "exquisite_corpse", p_present: rest[0] === "on" })));
    break;
  case "invite":
    console.log(JSON.stringify(await client.mutation("games:send_game_invite", { p_kind: "exquisite_corpse" })));
    break;
  default:
    console.log("commands: ensure | state | check-hidden | draw <strokes.json> [idea] | live <strokes.json> [seconds] [idea] | watch [seconds] | fetch <dir> | seen | presence <on|off> | invite");
}
