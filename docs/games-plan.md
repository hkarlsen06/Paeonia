# Games plan

Plan and decisions for the Games tab. Nothing is built yet. Sections marked "Decided" were agreed with the developer. Everything else is the current proposal and can change.

Keep this file current. When a games decision changes, or games code lands, update the matching section in the same change. Move items from "Open questions" to "Decisions" once the developer settles them, and replace proposals with what was actually built.

## Decisions

Decided on 2026-10-11.

- **Games is the fifth tab.** It becomes a new `MainTab` case. Its position among the tabs is still open.
- **Overflow plan.** If the tab bar ever needs a sixth entry, the You tab becomes a More tab. Memories keeps its own tab.
- **Included in the subscription.** Games are part of the subscription the couple already has. There is no separate purchase and no per-game unlock. Use the same couple entitlement check as other paid features.
- **Saving to Memories is opt-in.** Only creative games offer it, such as Exquisite corpse and Draw & Guess drawings. Board games and quick duels never offer it. When a creative game ends, both partners are asked whether to save it. If either one says yes, it is saved. Nothing is saved without a yes.
- **No forfeits on a timer.** An async game waits as long as it needs to. This follows the forgiving-streak rule in `AGENTS.md`.

## Architecture

Proposed. Two transports already exist, and they suit different jobs.

| | Relay (`relay/`, Worker plus one Durable Object per couple) | Convex |
|---|---|---|
| Latency | Phone to phone, about 30 to 80 ms | Mutation then subscription update, about 100 to 300 ms |
| Storage | None. Forwards messages and forgets them | Saved, validated, authorized |
| Use for | Continuous streams: finger positions, strokes, puck physics | Turns, scores, hidden information, history, push |

Convex owns the state of every game. The relay carries only movement that never needs saving. Games built on simultaneous reveal (both act, then both see the result) run on Convex alone.

### Relay changes

- Today every socket for a couple joins one room, capped at `MAX_SOCKETS_PER_ROOM = 4` (Home and the canvas on two phones). Games would hit the cap. Add a channel to the relay ticket and route with ``getByName(`${coupleId}:${channel}`)`` so each game gets its own room.
- Sockets close after `SESSION_MS` (10 minutes). A live game must reconnect with a fresh ticket and fetch the current state again from Convex or from the phone that owns it.
- The relay reads nothing it forwards. The app defines the message format, as `WidgetDrawing/Live/WidgetLiveMessage.swift` does for drawing.

### Convex model

- A `games` table: `id`, `couple_id`, `kind`, `state`, `turn_user_id`, `version`, `status`, `created_at`, `updated_at`. Follow the snake_case and uuid conventions in `backend/convex/schema.ts`.
- A `game_moves` table holding each move in order, for replays and reveals.
- One `make_move({ game_id, expected_version, move })` mutation. It checks couple access, whose turn it is, and the version, then runs a pure rules function for that `kind`. A stale version fails instead of overwriting.
- A `view_for(state, user_id)` function per kind. Queries return only that projection, so hidden information (Battleship boards, unrevealed answers, the drawing under the fold) never reaches the other phone.
- Game data joins relationship end and account deletion cleanup (`lib/relationshipCleanup.ts`, `lib/accountDeletion.ts`).
- A saved game becomes an ordinary `memories` row with its media, so the existing moderation and report flow covers it.

### Real-time fairness

Reaction games compare reaction times, not arrival order. Each phone measures from the moment its own screen showed the signal. Both phones schedule the signal for a shared future time, with clock offset measured by a ping over the relay.

For two-phone physics (air hockey), the phone the puck is on runs the physics and hands it over at the edge of its half. Neither phone waits on the other's lag.

### Notifications

- Turn notifications go through `pushQueue` and `lib/notificationCopy.ts`.
- Lock-screen text names the game and that it is your turn. It never shows the move, a drawing, or written content.
- After a few days without a move, send at most one gentle reminder, then stay quiet.
- A "Your move" widget fits the existing widget target. It is optional for the first release.

### Localization

All game copy goes through the String Catalog in English and Norwegian Bokmal. Word lists (Draw & Guess) need both languages. Any dictionary-based game needs licensed word lists for both.

## Game catalog

Effort is relative: S reuses most existing code, L needs a large new engine or content.

### Real-time (both online)

| Game | Transport | Memories | Effort |
|---|---|---|---|
| Draw & Guess | Relay strokes, Convex round state | Yes, the drawings | S |
| Mind Meld | Convex only | No | S |
| Touch | Relay | No | S |
| Reaction duel | Relay, Convex for results | No | S |
| Air hockey | Relay | No | M |

- **Draw & Guess.** One partner draws a word, the other types guesses. Reuses `WidgetDrawing/Live/*`. Partners can write custom words for each other.
- **Mind Meld.** Both type a word at the same time and the words are revealed together. Each next round, both try to name a word that connects the last two. You win when you say the same word.
- **Touch.** Both put a finger on the screen and see the partner's finger as a glow. When they overlap, both phones buzz and a flower opens.
- **Reaction duel.** Tap when the flower opens. Uses the fairness rule above.
- **Air hockey.** Each phone is half of the table and the puck crosses between them.

### Async (one turn, then hours of waiting)

| Game | Hidden information | Memories | Effort |
|---|---|---|---|
| Exquisite corpse | Yes | Yes | M |
| Story chain | No | Yes | S |
| Guess my spot | Yes, the location | No | M |
| Connect Four, Dots and Boxes, Ultimate tic-tac-toe | No | No | S each |
| Battleship with date ideas | Yes | No | M |
| Chess | No | No | L |
| Wordfeud-style word game | Yes, the tile rack | No | L |

- **Exquisite corpse.** Each partner draws one part (head, body, legs) and sees only a thin strip of the part before. The full drawing is revealed at the end.
- **Story chain.** Each turn adds one or two sentences, sometimes with a word that must be used.
- **Guess my spot.** Send a photo of where you are. The partner drops a pin on a map and scores by distance. The sender's coordinates stay hidden until the guess.
- **Board games.** Short classic turns. Connect Four is the proposed first test of the turn engine.
- **Battleship with date ideas.** Hide date ideas instead of ships. Sinking one turns it into a plan.
- **Chess and word games.** Popular but expensive. Chess needs a rules engine. A word game needs licensed English and Norwegian dictionaries. Deferred.

## Proposed first release

Draw & Guess, Mind Meld, Connect Four, and Exquisite corpse. Between them they use all three paths (relay real-time, Convex simultaneous reveal, Convex async turns). Most of the work is the shared engine, so later games are mostly UI plus one rules function.

## Open questions

- Which games ship first. The list above is a proposal.
- Where Games sits in the tab order.
- How the save-to-Memories prompt works in detail: who is recorded as the memory's creator, how long the prompt waits for an answer, and whether either partner can dismiss it.
- Whether a couple can have more than one active game of the same kind.
- When the single turn reminder goes out.
- How precise the location in Guess my spot is, and whether the sender can blur it to a neighborhood.
