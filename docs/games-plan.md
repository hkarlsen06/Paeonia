# Games plan

Plan and decisions for the Games tab. Nothing is built yet. Sections marked "Decided" were agreed with the developer. Everything else is the current proposal and can change.

Keep this file current. When a games decision changes, or games code lands, update the matching section in the same change. Move items from "Open questions" to "Decisions" once the developer settles them, and replace proposals with what was actually built.

Each game gets its own design doc in `docs/games/` once the developer picks it. That doc owns the game's rules, scoring and content. This file owns what all games share.

- `docs/games/draw-and-guess.md`: the first game.

## Decisions

Decided on 2026-10-12.

- **Draw & Guess is the first game.** Design in `docs/games/draw-and-guess.md`.
- **Every game is crafted.** A game ships only when it passes the quality bar below. It is better to ship fewer games than to ship thin ones.
- **First-time setup.** The first time a couple opens Games, they choose two couple settings: play style and game language. The partner who opens Games first completes setup. The other partner sees what was picked on their first visit and skips setup. There is no step where both must agree. Either partner can change a setting later, and the last change wins.
- **Play style.** The couple chooses whether they like to play against each other or together as a team. "Against each other" gives each partner their own score and a winner. "Together" gives one shared score. Each game's design doc says how the game plays in each style. A game where scores make no sense, such as Touch, can ignore the setting.
- **Game language.** The couple picks a language they both understand. Word lists, decoy letters and other game content use it, whatever language each partner's app is in. The choices are the app's languages, English and Norwegian Bokmal. When both partners already use the same app language, setup preselects it.
- **No game streaks.** Games never get a streak of their own. A game turn counts toward the couple's existing streak through a new activity kind in `ACTIVITY_KINDS` (`backend/convex/lib/streaks.ts`). Each game's design doc says which action counts.
- **Live is not deferred.** When a game's design includes live play, live ships in the game's first version.
- **Invite to play.** Every game with live play has a "Tell [Name] you want to play" button. It shows when the partner doesn't have the game open. Tapping it sends the partner a push, "[Name] wants to play [game] with you", and opening the push goes straight into the game.
- **Scores grow forever.** Scores never reset. There are no seasons or weekly matches.

Decided on 2026-10-11.

- **Games is the fifth tab.** It becomes a new `MainTab` case. Its position among the tabs is still open.
- **Overflow plan.** If the tab bar ever needs a sixth entry, the You tab becomes a More tab. Memories keeps its own tab.
- **Included in the subscription.** Games are part of the subscription the couple already has. There is no separate purchase and no per-game unlock. Use the same couple entitlement check as other paid features.
- **Saving to Memories is opt-in.** Only creative games offer it, such as Exquisite corpse and Draw & Guess drawings. Board games and quick duels never offer it. When a creative game or round ends, both partners are asked whether to save it. If either one says yes, it is saved. Nothing is saved without a yes.
- **No forfeits on a timer.** An async game waits as long as it needs to. This follows the forgiving-streak rule in `AGENTS.md`.

## Quality bar

Check every game design against this list before building it.

1. **Fun within 30 seconds.** The first turn teaches the rules by playing. No tutorial screen.
2. **Works apart.** Partners are often in different time zones, so every game works async. A game with live play also works when only one partner is online.
3. **Only in Paeonia.** GamePigeon already offers classic board games inside iMessage. A game earns its place by using what only Paeonia has: the drawing canvas, the couple's shared context, and Memories.
4. **A designed reveal.** The moment a partner sees the other's move gets the most attention to timing, haptics and animation.
5. **Hand-written content.** Word lists and prompts are written by hand for each language, never translated filler.
6. **Ends gently.** No abandoned games, no guilt, no punishment for slow replies.

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

All game copy goes through the String Catalog in English and Norwegian Bokmal. Game content such as word lists follows the couple's game language, so every list needs both languages. Any dictionary-based game needs licensed word lists for both.

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

- **Draw & Guess.** The first game. It plays async, with live watching when both are online. Its full design is in `docs/games/draw-and-guess.md`.
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

## Order

Draw & Guess comes first. It builds the turn engine, the drawing replay and the save-to-Memories flow. Exquisite corpse reuses all three, so it is the likely second game. Mind Meld is the cheapest game that tests a simultaneous reveal on Convex. Connect Four fails quality bar item 3 unless it gets a Paeonia-specific twist.

## Open questions

- Which game comes after Draw & Guess.
- Where Games sits in the tab order.
- How often a partner can send an invite to play, so it never turns into spam.
- How the save-to-Memories prompt works in detail: who is recorded as the memory's creator, how long the prompt waits for an answer, and whether either partner can dismiss it.
- Whether a couple can have more than one active game of the same kind.
- When the single turn reminder goes out.
- How precise the location in Guess my spot is, and whether the sender can blur it to a neighborhood.
