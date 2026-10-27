# Games plan

Plan and decisions for the Games tab. Draw & Guess is built (`backend/convex/drawAndGuess.ts`, `Features/Games/DrawAndGuess/`). The shared Games wiring is kind-based: the backend (`backend/convex/games.ts`, `lib/games.ts`, `lib/gameRegistry.ts`), the relay (`relay/src/ticket.ts`) and Swift (`GameKind`) register all ten kinds below, and each game plugs in at the points in "Adding a game". Sections marked "Decided" were agreed with the developer. Everything else is the current proposal and can change.

Keep this file current. When a games decision changes, or games code lands, update the matching section in the same change. Move items from "Open questions" to "Decisions" once the developer settles them, and replace proposals with what was actually built.

Each game gets its own design doc in `docs/games/` once the developer picks it. That doc owns the game's rules, scoring and content. This file owns what all games share.

- `docs/games/draw-and-guess.md`: the first game.
- `docs/games/mind-meld.md`: the simultaneous word game.
- `docs/games/hub-artwork.md`: the standard every game's hub picture follows.
- `docs/games/ludo.md`: Ludo, the fourth board game, on the board game engine.
- `docs/games/consensio.md`: Consensio, where one partner places a marker on a line and the other guesses where it is.
- `docs/games/guess-my-spot.md`: Guess my spot, where one partner sends a photo and the other guesses on a map where it was taken.

## Decisions

Decided on 2026-10-27.

- **Finished games can start a conversation.** Every game's result and history have a conversation button. Either partner can write, and both open the same conversation from that game or from Chats. The complete result is above the messages: every revealed word pair in Mind Meld, the drawing and all guesses in Draw & Guess, the scale and both markers in Consensio, the photo and both places in Guess my spot, the whole creature or story, and a board replay with every move. Nothing creates a thread until someone sends the first message. Results already on the phone open offline, and messages use the existing send queue. Deleting a Guess my spot round removes its conversation too. All four board games expose their stored past games, including Ludo, Four in a Row and Dots and Boxes, whose history screens were previously unwired.

Decided on 2026-10-24.

- **The game is "Four in a Row", never "Connect Four".** Connect Four is a Hasbro trademark, so no text a user or App Review sees may use it: copy, VoiceOver labels, pushes, the data export, the website and App Store text. The Norwegian name stays "Fire på rad". Internal names keep `connect_four` (`GameKind.connectFour`, catalog keys such as `connectFour.name`, type, file and asset names, the relay channel and stored data), because nobody sees them.

Decided on 2026-10-23.

- **"Not now" on a waiting game.** A full card under "Right now" that is there because the game waits for this person has a round "Not now" button in its top trailing corner. Tapping it moves the card down to the grid, takes the game off the Games tab badge and the app icon badge, and stops the 72-hour reminder for that turn. The game comes back by itself when the partner moves, a new result arrives, or the partner sends a new invite. A card that shows because the partner is in the game has no button, and the Home tab card has none either. The server stores the hide, so it holds on every phone of that person (`games:hide_waiting_game`, `game_hidden_waits`).

Decided on 2026-10-18.

- **Dropped games.** Touch, Air hockey and Battleship with date ideas are out. Touch is too thin to ship. Air hockey needs both phones side by side, because each phone shows only its own half of the table, and Paeonia is for couples who are apart. Battleship with date ideas makes the couple come up with date ideas, which is the hard part they would want help with.
- **Guess my spot uses photos from the library.** There is no camera button. The couple may share their live location on the Home map, which would give away a photo taken right now, so the game is about where you were. Any photo in the camera roll can be sent, with no age rule. Memories are not a source.
- **Guess my spot's spot comes from the photo.** The phone reads the photo's location. When it has none or it is wrong, the sender drops the pin. The sender always sees the spot on a map before sending and can move it, so nothing goes out that they didn't see.
- **Guess my spot plays like Consensio.** The partners take turns, one photo each. It plays async with pushes, and live when both are in.
- **Guess my spot scores on a log scale.** Up to 5000 points within 25 m, down to 0 at 20,000 km, and every 10 times closer adds the same points, because most photos come from near home. (2026-10-27)
- **Guess my spot's screens.** The guess shows a small photo on top, tap to see it full screen, and a map under it that takes most of the screen to drop the pin. The map is Apple's standard map in Paeonia's dark look, with a button for satellite. On the reveal the map zooms out from the guess, a gold line draws to the real spot, the camera lands there and the distance counts up, then the photo comes back with the place name and date. Only where is guessed, not when. In the result, round points sit above the total so large totals stay on one line.
- **Guess my spot keeps a map of our places.** Every round becomes a pin on one shared map, and each pin opens its photo and both spots.
- **Guess my spot strips the photo.** The phone removes the photo's metadata, such as the camera, the time and the location, before uploading. The spot travels on its own and stays hidden until the guess.
- **Guess my spot is "Gjett hvor" in Norwegian.**
- **Guess my spot follows the play style.** "Together" shows one shared total, "against each other" each partner's own points. Only the guesser scores. (2026-10-19)
- **Guess my spot's guessed rounds show on the Memories tab's "Our places" map,** marked as from the game and left out of its countries and cities. The game's own map is "Our guesses". (2026-10-19)
- **Guess my spot keeps the picker open until sending.** A picked photo can be swapped for another as often as the sender likes until the round is sent. A photo with no location the sender can't place is just swapped out, so there is no skip.

Decided on 2026-10-21.

- **Finished drawings, creatures and stories can be shared outside the app.** Draw & Guess (history and result), Odd Creatures (history and reveal) and Story Chain (history and the finished story) open the shared share sheet from a toolbar button (`Shared/Sharing/`). A drawing or creature leaves as a framed card on the plum canvas with a small Paeonia wordmark. A Story Chain story leaves as a typeset card, and also as plain text. The button waits until the result is on screen, so the picture never gives away a reveal. Either partner can share, since the couple made it together.

Decided on 2026-10-14.

- **How to play cards.** Ultimate Tic-Tac-Toe, Dots and Boxes, Mind Meld, Consensio and Guess my spot have three swipeable cards, each with one illustration and one or two sentences. They open by themselves the first time this phone opens the game, and again from "How to play" in the game's toolbar or menu. The other games still teach by playing. The cards are `GameTutorial` and `GameTutorialSheet` in `Features/Games/Shared/Tutorial/`, and the pictures are in the `GameTutorial` asset folder.

Decided on 2026-10-13.

- **Hub with several games.** The hub has two parts, so a game is never far down (decided on 2026-10-20). "Right now" shows a full-width card for each game the partner is in, then each game waiting for this person. Every other game is a small tile in a two-column grid below, headed "More games" (more columns on iPad, one with the largest text sizes). Both the waiting games and the grid put the game either partner played most recently first, so the games the couple plays rise to the top. A game neither partner ever opened comes after the played ones, in catalog order (decided on 2026-10-20). "Played" means the game screen was open: the server keeps one time per couple and game in `game_plays`, which an open screen moves forward every 5 minutes and closing it moves at once. Without a game for "Right now", the grid is all there is and has no heading. A tile is the same frame with the picture and its beat, the name and the status line, and a tap anywhere opens the game. It has no badge, partner chip, button or history link, since every game screen links to its own history. Catalog order is the `GameKind` case order, most popular first: Ludo, Draw & Guess, Four in a Row, Mind Meld, Consensio, Guess my spot, Dots and Boxes, Ultimate Tic-Tac-Toe, Story Chain, Odd Creatures. All cards and tiles share one frame (`GameHubCardFrame`): the shared backdrop with the game's own objects behind the whole card (`docs/games/hub-artwork.md`), the partner-here chip, an optional badge such as the score, the name, a status line, the main button, and optional extras such as "Our drawings". The card glows while the game waits for this person.
- **Home tab with several games.** The Home tab shows one card: the game the partner opened most recently, while they have it open. It is the hub card without hub-only links, and it is the first card, above today's questions, because the partner waiting in a game is the one thing not to miss (decided on 2026-10-18).

- **Finished creations take emoji reactions.** Either partner can put one emoji on a finished Draw & Guess round, Odd Creatures figure or Story Chain story, in the result and in the creation's history (decided on 2026-10-21). Unlike a star, a reaction is not private: the partner sees it, and a first reaction sends them one gentle push that follows the Games setting. It is the app's one reaction model (`reactions:set_reaction`, see `docs/implementation-map.md`, "Reactions"), so Draw & Guess's older love, laugh and wow reaction for the guesser is gone. The other games get none: Mind Meld, Consensio, Guess my spot and the board games are scored or guessed, so there is no finished piece of work to react to.
- **Games don't save to Memories.** A creative game keeps its own history instead, such as the finished drawings of Draw & Guess. Each partner can star rounds in that history, and stars are private: the partner isn't told and a star doesn't change the game. This replaces the opt-in save prompt from 2026-10-11 and the save prompt details from 2026-10-12. Board games keep every finished game with its moves, so the couple can watch it again (decided on 2026-10-15, see "Past games" in `docs/games/board-games.md`). They have no stars. Quick duels keep no history.

Decided on 2026-10-12.

- **Draw & Guess is the first game.** Design in `docs/games/draw-and-guess.md`.
- **Every game is crafted.** A game ships only when it passes the quality bar below. It is better to ship fewer games than to ship thin ones.
- **First-time setup.** The Games tab opens on the hub, so both partners see every game before choosing anything. The first time a partner opens a game, a sheet asks for two couple settings: play style and game language. The partner who opens a game first completes setup. The other partner sees what was picked before their first game and can keep it or change it. The server remembers who has seen the settings (`game_settings.seen_by_user_ids`), so a reinstall or a new phone does not show them again. Then each partner without a drawn mark gets the canvas for their board game mark, and the game opens when that sheet closes. Cancel on the settings step leaves the person on the hub. There is no step where both must agree. Either partner can change a setting later, and the last change wins.
- **Play style.** The couple chooses whether they like to play against each other or together as a team. "Against each other" gives each partner their own score and a winner. "Together" gives one shared score. Each game's design doc says how the game plays in each style. A game where scores make no sense can ignore the setting.
- **Game language.** The couple picks a language they both understand. Word lists, decoy letters and other game content use it, whatever language each partner's app is in. The choices are the app's languages, English and Norwegian Bokmal. When both partners already use the same app language, setup preselects it.
- **No game streaks.** Games never get a streak of their own. A game turn counts toward the couple's existing streak through a new activity kind in `ACTIVITY_KINDS` (`backend/convex/lib/streaks.ts`). Each game's design doc says which action counts.
- **Tab order.** Home, Questions, Games, Memories, You. Games sits in the middle.
- **Tab badge.** The Games tab shows a badge of 1 while any game waits for this person to draw or guess. The tab bar loads the game state at launch, so the badge shows before the tab is opened.
- **Tab bar in a game.** On iPhone the tab bar hides while a game screen is open. On iPad it stays, because the iPad tab bar sits at the top and iPadOS 26 moves the game's content when it hides during the push.
- **One ongoing game per kind.** A couple has at most one active game of each kind.
- **Turn reminder.** When a move has waited 72 hours, the partner whose turn it is gets one reminder. There is never a second one for the same move.
- **Live is not deferred.** When a game's design includes live play, live ships in the game's first version.
- **Invite to play.** Every game with live play has a "Tell [Name] you want to play" button. It shows when the partner doesn't have the game open. Tapping it sends the partner a push, "[Name] wants to play [game] with you", and opening the push goes straight into the game. A partner can send one invite every 15 minutes. Until then the button shows "Sent". Ludo shows it as a button under the board, which keeps its room while hidden, so the board never resizes. The other games have no room for it, so it is a bell at the leading edge of the toolbar. After a send the bell fills, and a banner says when the next invite can go.
- **Partner in a game on Home.** While the partner has a game open, its card from the Games tab also shows on the Home tab, so an invite opens in one tap. Only the game the partner is in shows there. A game that waits for your turn stays on the Games tab. The Games tab shows the one the partner is in first under "Right now", then the games waiting for your turn, except those you put aside with "Not now" (decided on 2026-10-23).
- **Partner opens a game on another tab.** When the partner opens a game while this person is on any tab but Home, a banner at the top says "Robin opened Ludo" with the partner's photo. It stays 7 seconds, longer than other notices, and tapping it opens that game. There is no banner while this person is already in that game or is answering a question. Leaving one of two open games shows nothing. `MainTabView.announcePartnerGame` owns it.
- **Scores grow forever.** Scores never reset. There are no seasons or weekly matches.

Decided on 2026-10-11.

- **Games is the fifth tab.** It becomes a new `MainTab` case. Its position among the tabs is still open.
- **Overflow plan.** If the tab bar ever needs a sixth entry, the You tab becomes a More tab. Memories keeps its own tab.
- **Included in the subscription.** Games are part of the subscription the couple already has. There is no separate purchase and no per-game unlock. Use the same couple entitlement check as other paid features.
- **No forfeits on a timer.** An async game waits as long as it needs to. This follows the forgiving-streak rule in `AGENTS.md`.

## Quality bar

Check every game design against this list before building it.

1. **Fun within 30 seconds.** The first turn teaches the rules by playing. A game whose rules are hard to learn that way also gets illustrated "How to play" cards (see Decisions).
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
| Use for | Continuous streams: finger positions, strokes | Turns, scores, hidden information, history, push |

Convex owns the state of every game. The relay carries only movement that never needs saving. Games built on simultaneous reveal (both act, then both see the result) run on Convex alone.

### Relay changes

- Today every socket for a couple joins one room, capped at `MAX_SOCKETS_PER_ROOM = 4` (Home and the canvas on two phones). Games would hit the cap. Built: the relay ticket has an optional channel claim `ch`, and the Worker routes with ``getByName(`${coupleId}:${channel}`)``, so each game gets its own room. A ticket without a channel still joins the couple's canvas room. The channel is the game kind. The Worker accepts only the channels in `ALLOWED_CHANNELS` (`relay/src/ticket.ts`), which lists every kind, and `games:create_game_live_ticket` issues the game tickets.
- Sockets close after `SESSION_MS` (10 minutes). A live game must reconnect with a fresh ticket and fetch the current state again from Convex or from the phone that owns it.
- The relay reads nothing it forwards. The app defines the message format, as `WidgetDrawing/Live/WidgetLiveMessage.swift` does for drawing.
- Built: each game has its own message type next to the drawing messages, on the same socket. The type conforms to `GameLiveMessage` and names its game, and `GameLiveChannel` sends and receives it (`Features/Games/Live/GameLiveChannel.swift`). On the wire a game message is `{"game": "<game>", "message": {...}}`, and the connection routes anything with a `game` key to the channel. To add live messages to a new game, declare its message type and open a `GameLiveChannel` on a connection made with `GameLiveTicket.provider(for:)`. Build the room with `GameLiveRoom.make(kind, coupleID:role:)`. Messages sent while offline are dropped, so a game sends its whole state each time and sends it again when the partner arrives (`WidgetLiveDrawing.onPartnerArrived`). `DrawAndGuessLiveMessage` is the first one.

### Convex model

- Shared tables, keyed by `kind` where it matters: `game_settings` (the couple's play style and language), `game_invites` (each partner's last invite per game, and when the partner answered it by opening the game), `game_plays` (when either partner last had each game open), `game_hidden_waits` (what each person put aside with "Not now", by kind). Who has which game open lives in the `@convex-dev/presence` component, one room per couple and game (`backend/convex/lib/presence.ts`). `games:get_games_overview` returns all of them for the app.
- Each game has its own tables, named with its kind as a prefix. Draw & Guess came first, so its tables are `games` (one row per couple, without a `status` column because the game never ends), `game_moves` (one row per round), `game_guesses` and `game_used_words`. Follow the snake_case and uuid conventions in `backend/convex/schema.ts`.
- Draw & Guess has one mutation per action (`pick_draw_word`, `submit_drawing`, `submit_guess`, `give_up_round`), each checking access, turn ownership, and round state. Proposal for board games: one `make_move({ game_id, expected_version, move })` mutation. It checks couple access, whose turn it is, and the version, then runs a pure rules function for that `kind`. A stale version fails instead of overwriting.
- A `view_for(state, user_id)` function per kind. Queries return only that projection, so hidden information (unrevealed answers, the drawing under the fold) never reaches the other phone.
- Game data joins relationship end and account deletion cleanup. `deleteCoupleGameRows` in `lib/gameRegistry.ts` deletes the shared rows and calls each game's `deleteCoupleRows`.
- A creative game keeps its own history in its own tables, such as the finished rounds and drawings of Draw & Guess. Stars are favorites, one shared `favorites` table with one row per person and item. Nothing is copied into `memories`.

### Real-time fairness

Reaction games compare reaction times, not arrival order. Each phone measures from the moment its own screen showed the signal. Both phones schedule the signal for a shared future time, with clock offset measured by a ping over the relay.

### Notifications

- Turn notifications go through `pushQueue` and `lib/notificationCopy.ts`.
- Alerts collapse per game kind and couple. Opening a game clears its delivered alerts. Queued invites send only while the same invite is unanswered and less than 15 minutes old.
- Lock-screen text names the game and that it is your turn. It never shows the move, a drawing, or written content.
- After a few days without a move, send at most one gentle reminder, then stay quiet.
- A "Your move" widget fits the existing widget target. It is optional for the first release.

### Localization

All game copy goes through the String Catalog in English and Norwegian Bokmal. Game content such as word lists follows the couple's game language, so every list needs both languages. Any dictionary-based game needs licensed word lists for both.

## Game catalog

Effort is relative: S reuses most existing code, L needs a large new engine or content.

### Real-time (both online)

| Game | Transport | Own history | Effort |
|---|---|---|---|
| Draw & Guess | Relay strokes, Convex round state | Yes, the drawings with stars | S |
| Mind Meld | Convex, relay for presence and typing | Yes, the word trails | S |
| Reaction duel | Relay, Convex for results | No | S |

- **Draw & Guess.** The first game. It plays async, with live watching when both are online. Its full design is in `docs/games/draw-and-guess.md`.
- **Mind Meld.** Built. Both type a word at the same time and the words are revealed together. Each next round, both try to name a word that connects the last two. You win when you say the same word. Live play shows when the partner is here, typing or locked in. Its design is in `docs/games/mind-meld.md`.
- **Reaction duel.** Tap when the flower opens. Uses the fairness rule above.

### Async (one turn, then hours of waiting)

| Game | Hidden information | Own history | Effort |
|---|---|---|---|
| Exquisite corpse | Yes | Yes | M |
| Story chain | No | Yes | S |
| Consensio | Yes, the real spot until the guess | Yes, every revealed round | M |
| Guess my spot | Yes, the location until the guess | Yes, a map of every round | M |
| Four in a Row, Dots and Boxes, Ultimate tic-tac-toe | No | Yes, every finished game to watch again | S each |
| Chess | No | No | L |
| Wordfeud-style word game | Yes, the tile rack | No | L |

- **Exquisite corpse.** Built. Partners take turns drawing the head, body and legs of a figure, and each sees only the bottom 12% of the part before. The whole figure unfolds part by part at the end and goes to "Our creatures". It plays live with a folded paper view and async with pushes. Its full design is in `docs/games/exquisite-corpse.md`.
- **Story Chain.** Built. The partners write one story together, one or two sentences a turn. A writer can dare the partner to use a word in the next line, and the partner who did not write the last line names the story. Live play shows the partner's letters as they are typed. Its design is in `docs/games/story-chain.md`.
- **Consensio.** Built. One partner puts a marker where they honestly stand on a line between two ends, such as how they feel about camping. The other guesses where it went, and the reveal scores how close they came. It plays async with pushes and live with the guess marker moving on the placer's screen. Its design and the decisions are in `docs/games/consensio.md`.
- **Guess my spot.** Built. Send a photo from your library, and the partner drops a pin on a map where they think it was taken. The score is by distance, and the sender's spot stays hidden until the guess. It plays async with pushes and live with the guesser's map view showing on the sender's map, without their pin. Its design is in `docs/games/guess-my-spot.md`, with the decisions from 2026-10-18 above.
- **Board games.** Four in a Row, Dots and Boxes and Ultimate Tic-Tac-Toe share one turn engine (`make_move` with a pure rules function per kind). Each partner's own drawn mark is on every piece, the starter can play for something, and Dots and Boxes uncovers a random photo from Memories. Built. Design in `docs/games/board-games.md`.
- **Ludo.** The fourth board game, on the same engine. Two pawns each race round the classic cross board. The phone rolls the die and the roll is part of the move, so a move can still be made offline. Design in `docs/games/ludo.md`.
- **Chess and word games.** Popular but expensive. Chess needs a rules engine. A word game needs licensed English and Norwegian dictionaries. Deferred.

## Adding a game

The checklist for building a game. All ten kinds are already registered on the backend (`GAME_KINDS` in `lib/validators.ts`), in the relay (`ALLOWED_CHANNELS`) and in Swift (`GameKind`). A kind shows nowhere in the app until its hub model is in `GamesViewModel.games`. Add your lines at the points below and leave other games' lines alone. Draw & Guess is the worked example for every point.

### Names

| kind (backend, relay channel) | Swift prefix | URL path `paeonia://games/<path>` | Folder `ios/PaeoniaApp/Features/Games/<Folder>` | Design doc |
|---|---|---|---|---|
| draw_and_guess | drawAndGuess / DrawAndGuess | draw-and-guess | DrawAndGuess | docs/games/draw-and-guess.md |
| mind_meld | mindMeld / MindMeld | mind-meld | MindMeld | docs/games/mind-meld.md |
| exquisite_corpse | exquisiteCorpse / ExquisiteCorpse | exquisite-corpse | ExquisiteCorpse | docs/games/exquisite-corpse.md |
| story_chain | storyChain / StoryChain | story-chain | StoryChain | docs/games/story-chain.md |
| connect_four | connectFour / ConnectFour | connect-four | BoardGames/ConnectFour | docs/games/board-games.md |
| dots_and_boxes | dotsAndBoxes / DotsAndBoxes | dots-and-boxes | BoardGames/DotsAndBoxes | docs/games/board-games.md |
| ultimate_tic_tac_toe | ultimateTicTacToe / UltimateTicTacToe | ultimate-tic-tac-toe | BoardGames/UltimateTicTacToe | docs/games/board-games.md |
| ludo | ludo / Ludo | ludo | BoardGames/Ludo | docs/games/ludo.md |
| consensio | consensio / Consensio | consensio | Consensio | docs/games/consensio.md |
| guess_my_spot | guessMySpot / GuessMySpot | guess-my-spot | GuessMySpot | docs/games/guess-my-spot.md |

- Backend: module `backend/convex/<camelKind>.ts` (function paths `<camelKind>:<name>`), helpers in `backend/convex/lib/<camelKind>.ts`, tests next to them. Tables start with the kind, such as `mind_meld_rounds`. The board games share `boardGames.ts`, `lib/boardGames.ts`, `board_games` and `board_game_*`.
- Swift: every type, file, `GamesDestination` case, `SyncPendingOperationKind` case and `DeveloperScenario` static member starts with the Swift prefix, such as `MindMeldHubModel` and `mindMeldReveal`. Tests go in `ios/PaeoniaAppTests/Games/<Folder>/`. Board games share `Features/Games/BoardGames/Shared/`.
- String Catalog keys start with the Swift prefix, such as `mindMeldRevealTitle`, so each game's keys sit together. Add English and Norwegian Bokmal for every key. Keys that start with `games` belong to the shared tab.

### Backend

1. Tables in `schema.ts`, in your own block after the Draw & Guess tables. Every table gets a `couple_id` index.
2. Registered functions in your module. Check access with `getCurrentEntitledCoupleId` (`lib/access.ts`) or `requireCoupleAccess`, find the partner with `requirePartnerId`, and read the couple's settings with `requireGameSettings` (these three are in `lib/games.ts`). A turn counts toward the streak through `applyCoupleActivity` with `activity_kind: "game_turn_completed"`.
3. `lib/gameRegistry.ts`: replace your `null` in `GAME_BACKENDS` with your `GameBackend`. `pushStillWanted` and `deleteCoupleRows` (every table of yours) are required. Add `sendDueTurnReminders` if your game has turns (one reminder after `TURN_REMINDER_AFTER_MS`, never a second for the same move) and `onLanguageChanged` if it offers content in the game language. Add `waitingFor` if a game can wait for one partner. It returns one `GameWait` (`{ kind, key }`, in `lib/games.ts`) for each game of yours where it is the user's turn or the user has not seen the newest result, and the turn's key when both are true. The key must change with every new turn and every newer result, such as `turn:<game id>:<turn_started_at>` or `result:<round id>`, because a wait hidden with "Not now" comes back when its key changes. `gamesWaitingFor` counts the waits that are not hidden, for both badges. A game whose play needs both partners online leaves it out. Media you store is deleted by the couple media sweep in `lib/relationshipCleanup.ts`. A game that uploads files adds its `reserved_parent_kind` and `upload_purpose` next to Draw & Guess's `game_move` and `game_drawing_payload`: the literals in `schema.ts`, the reserve check in `media.ts` (`create_pending_media_upload`), `canReadMediaAsset` in `lib/mediaAssets.ts`, and `mediaAssetHasLiveReference` in `lib/mediaOrphans.ts`.
4. Pushes: queue them with `enqueueGamePush` (`lib/games.ts`) as `game_turn_ready`, `game_result`, `game_invite` or `game_turn_reminder`. Before your first push, add your entry to `GAME_PUSH_COPY` in `lib/notificationCopy.ts`. Lock-screen copy names the game and whose turn it is, never the move or written content. When one push kind needs different words at different moments, such as the last line of a story, pass `step` to `enqueueGamePush` with a fixed token you choose (`last_line`, never content) and give it a title and body under `steps` in your copy entry. The deep link is filled in from the kind.
5. Nothing to add for invites, presence, live tickets, settings or "Not now". `send_game_invite`, `set_game_presence`, `create_game_live_ticket`, `hide_waiting_game` and `get_games_overview` in `games.ts` take every kind.
6. Run `npm run typecheck` and `npm test` in `backend/`.

### Relay

Nothing. `ALLOWED_CHANNELS` lists every kind, and your room is `<couple>:<kind>`.

### iOS

1. Data: your gateway protocol and `Live<Prefix>Gateway`, your models, your cache, and your live feed, all in your folder. Register the feed in `Services/Live/LiveFeedRegistry.swift`, and clear your cache in `Storage/Privacy/LocalPrivacyPurgeService.swift` next to `gamesCache.clearAll()`. The feed posts `LocalStoreChanges.post(.games, ...)` after each write, so the tab re-reads. `GamesCache` holds the shared overview plus Draw & Guess's sections, so keep your data in your own cache, kept in a `GamesDocumentStore` like the others (one file per person, read once and kept in memory, written only when it changes). Return `data_epoch: dataEpoch()` from your state query. Your cache's `isOlder(than:)` must return false when the two states have different `dataEpoch` values, so phones take the server's copy after a restore.
2. `Features/Games/Data/GamesDependencies.swift`: add your dependency fields after `now`, each with a default that works offline, and set the live ones in `GamesDependencies.live()`.
3. A hub model that conforms to `GameHubModel` (`Features/Games/Hub/GameHubModel.swift`), such as `DrawAndGuessHubModel`. Its `card` builds a `GameHubCardFrame` with your artwork, status line, action title, and any badge or extras. The artwork follows `docs/games/hub-artwork.md`. Its `screen(for:)` returns your screens. `isYourTurn` puts the card under "Right now", unless the overview's `hidden_kinds` says this person tapped "Not now" on it. The frame draws that button from `GameHubCardContext.hide`, so your card needs no code for it. The Games tab badge comes from the server's `waitingFor` hook for the game (`gamesWaitingFor` in `backend/convex/lib/gameRegistry.ts`), the same count the app icon uses.
4. `Features/Games/Hub/GamesViewModel.swift`: add `let <camelKind>: <Prefix>HubModel`, its line in `init`, and add it to `games`. From then on the game has its hub card (a full card under "Right now" while the partner is in it or it is your turn and you have not tapped "Not now", otherwise a tile in the grid), the Home tab card while the partner is in it, and deep links and pushes that open `.game(.<kind>)`.
5. `GamesDestination` (same file): your extra screens, such as a history, get cases with your prefix. Your main screen is `.game(.<kind>)`.
6. Settings: read play style and language from the overview, `dependencies.cache.document(ownerUserID:).overview?.settings`. Setup is shared, so never ask for them in your game.
7. Presence and invites: your view model owns a `GameScreenLoops` (`Features/Games/Models/GameScreenLoops.swift`). Call `loops.beginHeartbeat()` while the screen is open and the app is active, and `loops.endHeartbeat()` when the screen closes or the app goes to the background. The heartbeat sends `setPresence(.<kind>, isPresent: true)` every `GamePresence.heartbeatInterval`. Presence writes go out one after another, so `false` always lands last, and the `false` runs in a background task. `loops.beginObserving` and `loops.beginTicking` run the reload on local changes and your clock tick. Read whether the partner is here (`partnerPresent`) and your last invite from `overview.presence(for: .<kind>)`, judge the invite with `GameInviteState.make`, and send invites with `dependencies.gateway.sendInvite(.<kind>)`.
8. Live play: a message type that conforms to `GameLiveMessage`, sent through a `GameLiveChannel` on a `WidgetLiveConnection` made with `GameLiveTicket.provider(for: .<kind>)`.
9. Queued writes: `SyncPendingOperationKind` cases in `Services/Sync/SyncTypes.swift`, and your handlers in `Features/Games/Data/GamesPendingOperationRegistry.swift`.
10. Developer scenarios: a new file `App/DeveloperScenarios/DeveloperScenario+<Prefix>.swift`, like `DeveloperScenario+MindMeld.swift`. Each scenario is a `static let` with its id, title, detail, category `.games` and the screen it opens, and one `static let <camelKind>: [DeveloperScenario]` lists them in menu order. Add that list to `allCases` in `DeveloperScenario.swift`. Also add your dependency fields in `DeveloperGamesScenarioFactory.dependencies(for:)` so the hub scenarios show your card.
11. Shared pieces: take the reload gate (`GameReloadGate`), stars (`FavoritesStore`, `FavoriteStarButton`) and drawing pieces such as the canvas and stroke replay from `Features/Games/Shared/` instead of copying Draw & Guess code.
12. Sounds: play a `GameSound` (`Features/Games/Shared/Sound/`) next to each haptic, such as `GameSound.tap.play(volume: 0.7)`. Reuse the shared sounds where they fit. A new sound is a recipe in `ios/Scripts/game-sounds.swift` plus a case in `GameSound`, and running the script writes its files to `Resources/GameSounds`. The sounds are soft and close, wood, felt and paper, with no harsh highs. They mix with the person's music because the app's audio session stays `.ambient`, so a game must never change the session.
13. Turn and partner cues: next to your resolver, derive a `GameAttention` (`Features/Games/Shared/Attention/`) from the state. Its `turn` names the partner's move that made it this person's turn, and stays nil when their own move did. Its `partnerStep` names a partner move that needs them without handing over the turn. Your view model owns a `GameAttentionCue`, feeds it at the end of every `recompute()` while the screen is open, and resets it in `stop()`. The cue plays the shared knock and step haptics and their sounds, so a view never plays its own "your turn" haptic.

### Ownership

- Your game owns its iOS folder, its tests, its backend module and helper file, its tables, and its design doc.
- Do not change Draw & Guess's tables or refactor its code. The one exception is the Exquisite corpse thread, which may move drawing code it reuses (canvas, stroke replay, live stroke messages, stars) into `Features/Games/Shared/` and shared backend helpers, as long as Draw & Guess behaves the same. It has moved the canvas, stroke replay, drawing components, layout, stars and history drawings so far, and a later drawing game reuses them from there (map in `docs/implementation-map.md`).
- Shared files take small additions at the points above. If a shared seam needs a real change, ask the developer first.
- In this file, edit only your own catalog bullet and the "Order" and "Open questions" lines about your game. Everything else goes in your design doc.

### Merging

- Commit on your own branch, signed, at most about three logical commits per game. When you hand back, push the branch and open a ready pull request with `gh`.
- Before you hand back, rebase onto local `main`. Conflicts at the registry points and in `Localizable.xcstrings` are two lists growing: keep both sides, and merge the String Catalog JSON by key so it stays valid. If a conflict is anything more, stop and ask.
- Ask the developer before you fast-forward local `main` to your branch. Whoever merges second rebases again.
- Test your branch on its own local backend with `scripts/local-backend` ([Testing a branch on a local backend](../backend/AGENTS.md#testing-a-branch-on-a-local-backend)). A branch never deploys to `api.paeonia.no`, because a deploy replaces every function there, including other games'. Only local `main` deploys, through `scripts/deploy-backend`. Relay deploys need the developer's OK.

## Order

Draw & Guess comes first. It builds the turn engine, the drawing replay and the history with stars. Exquisite corpse reuses all three from `Features/Games/Shared/` and is built. Mind Meld is the cheapest game that tests a simultaneous reveal on Convex. The board games are built with their Paeonia twist: a drawn mark, a stake and a hidden photo.

## Open questions

- Which game comes after Draw & Guess.
