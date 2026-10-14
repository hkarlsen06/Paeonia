// Story Chain test helper. Plays as one test account through the admin key.
// Run from backend/ with Node 22 or later and CONVEX_SELF_HOSTED_ADMIN_KEY set:
//   node scripts/story-chain/play.mjs state
//   node scripts/story-chain/play.mjs ensure
//   node scripts/story-chain/play.mjs start <1|2|3|own>
//   node scripts/story-chain/play.mjs line [--last] [--dare <1|2|3|word>] <text>
//   node scripts/story-chain/play.mjs name <title>
//   node scripts/story-chain/play.mjs seen
//   node scripts/story-chain/play.mjs type [--last] <text>    (types the text live in the relay room, then sends it)
// PLAY_AS picks the Clerk subject. The default is Hjalmar.
import { randomUUID } from "node:crypto";
import { ConvexHttpClient } from "convex/browser";

const subject = process.env.PLAY_AS ?? "user_3KVUgELskLqEzQzJXz12wbkj2yS";
const client = new ConvexHttpClient(process.env.CONVEX_SELF_HOSTED_URL ?? "https://api.paeonia.no");
client.setAdminAuth(process.env.CONVEX_SELF_HOSTED_ADMIN_KEY, {
  subject,
  issuer: "https://clerk.paeonia.no",
  tokenIdentifier: `story-chain|${subject}`,
});

// A fresh client id per call is fine: every operation here is a one-shot.
const op = () => ({
  p_client_operation_id: randomUUID(),
  p_client_id: randomUUID(),
  p_client_sequence: 1,
  p_local_created_at: new Date().toISOString(),
});
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const args = process.argv.slice(2);
const command = args.shift();
const flag = (name) => {
  const index = args.indexOf(name);
  if (index === -1) return null;
  const [, value] = args.splice(index, 2);
  return value ?? true;
};
const isLast = args.includes("--last") ? (args.splice(args.indexOf("--last"), 1), true) : false;
const dare = flag("--dare");

const screen = await client.query("storyChain:get_story_chain", {});
const game = screen.game;
const story = screen.current_story;

async function addLine(text) {
  const offered = screen.word_choices ?? [];
  const pick = dare && /^[123]$/.test(dare) ? offered[Number(dare) - 1] : null;
  return await client.mutation("storyChain:add_story_line", {
    p_story_id: story.id,
    p_line_id: randomUUID(),
    p_text: text,
    p_is_last: isLast,
    p_dare_word: pick ? null : (dare ?? null),
    p_dare_word_id: pick?.word_id ?? null,
    ...op(),
  });
}

switch (command) {
  case "state": {
    const mine = (line) => (line.author_user_id === screen.partner_user_id ? "partner" : "me");
    console.log(
      JSON.stringify(
        {
          my_turn: game ? game.turn_user_id !== screen.partner_user_id : null,
          game: game && { state: game.state, turn_number: game.turn_number, stories: game.story_count, finished: game.finished_count, version: game.version },
          openings: screen.opening_choices?.map((choice) => choice.text),
          words: screen.word_choices?.map((choice) => choice.word),
          story: story && {
            number: story.story_number,
            state: story.state,
            title: story.title,
            opening: story.opening_text,
            lines: story.lines.map((line) => `${line.number}. [${mine(line)}] ${line.text}${line.dare_word ? ` (gave ${line.dare_word})` : ""}`),
            seen_by_me: story.seen_by_me,
          },
          previous: screen.previous_story && { number: screen.previous_story.story_number, title: screen.previous_story.title, seen_by_me: screen.previous_story.seen_by_me },
        },
        null,
        1,
      ),
    );
    break;
  }
  case "ensure":
    console.log(JSON.stringify(await client.mutation("storyChain:ensure_story_chain_game", {})));
    break;
  case "start": {
    const choice = args[0];
    const opening = choice === "own" ? null : screen.opening_choices?.[Number(choice) - 1];
    if (choice !== "own" && !opening) throw new Error("no such opening on offer");
    const result = await client.mutation("storyChain:start_story", {
      p_game_id: game.id,
      p_story_id: randomUUID(),
      p_opening_id: opening?.opening_id ?? null,
      ...op(),
    });
    console.log(JSON.stringify(result));
    break;
  }
  case "line":
    console.log(JSON.stringify(await addLine(args.join(" "))));
    break;
  case "name":
    console.log(
      JSON.stringify(await client.mutation("storyChain:name_story", { p_story_id: story.id, p_title: args.join(" "), ...op() })),
    );
    break;
  case "seen": {
    const unseen = [story, screen.previous_story].find((item) => item?.state === "finished" && !item.seen_by_me);
    if (!unseen) throw new Error("no unseen finished story");
    console.log(JSON.stringify(await client.mutation("storyChain:mark_story_seen", { p_story_id: unseen.id })));
    break;
  }
  case "type": {
    // Joins the game's relay room like the app, types the line one letter at a time, then sends it.
    const text = args.join(" ");
    const ticket = await client.mutation("games:create_game_live_ticket", { p_kind: "story_chain" });
    if (!ticket) throw new Error("the relay is not set up");
    const socket = new WebSocket(ticket.url, { headers: { Authorization: `Bearer ${ticket.ticket}` } });
    // The relay greets with `welcome`, which names this socket. The hello says what it is doing.
    const ownId = await new Promise((resolve, reject) => {
      socket.onerror = reject;
      socket.onmessage = (event) => {
        const message = JSON.parse(String(event.data));
        if (message.type === "welcome") resolve(message.id);
      };
    });
    socket.onmessage = (event) => {
      const message = JSON.parse(String(event.data));
      if (message.type === "joined") socket.send(JSON.stringify({ type: "hello", from: ownId, role: "drawing" }));
    };
    const number = story.lines.length + 1;
    const live = (draft, lineId = null) =>
      socket.send(
        JSON.stringify({
          game: "story_chain",
          message: liveMessage({ story: story.id, number, text: draft, isLast, lineId, sent: lineId !== null }),
        }),
      );
    socket.send(JSON.stringify({ type: "hello", from: ownId, role: "drawing" }));
    await sleep(500);
    for (let end = 1; end <= text.length; end += 1) {
      live(text.slice(0, end));
      await sleep(90);
    }
    const result = await addLine(text);
    live(text, result.line_id);
    console.log(JSON.stringify(result));
    await sleep(500);
    socket.close();
    break;
  }
  default:
    console.log("commands: state | ensure | start <1|2|3|own> | line [--last] [--dare <1|2|3|word>] <text> | name <title> | seen | type [--last] <text>");
}

/** The app's `StoryChainLiveMessage` on the wire. Keep the keys in step with the Swift type. */
function liveMessage({ story, number, text, isLast, lineId, sent }) {
  return { story, number, text, last: isLast, ...(lineId ? { line: lineId } : {}), sent };
}
