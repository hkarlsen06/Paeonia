# Games plan

Decisions and rules for the Games tab. Each game has its own doc in `docs/games/` that owns its rules, scoring and content. This file owns what all games share. When a games decision changes, update the matching section in the same change.

## Decisions

### Scope and product

- **Included in the subscription.** No per-game unlock. Games use the couple entitlement check.
- **Every game is crafted.** Ship fewer games rather than thin ones. [Quality bar](#quality-bar) applies before building.
- **No game streaks.** A game turn counts toward the couple's existing streak through an activity kind in `ACTIVITY_KINDS` (`backend/convex/lib/streaks.ts`). Each game doc says which action counts.
- **No forfeits on a timer.** An async game waits as long as it needs, following the forgiving-streak rule in `AGENTS.md`. A turn reminder goes out once, after 72 hours, never twice for the same move.
- **Scores grow forever.** No seasons or weekly resets.
- **One active game per kind per couple.**
- **Live is not deferred.** When a game's design includes live play, live ships in its first version.
- **Games don't save to Memories.** A creative game keeps its own history, and each partner can privately star rounds (the partner is not told). Board games keep every finished game with its moves.
- **Finished creations take emoji reactions.** Unlike a star, a reaction is visible to the partner, and a first reaction sends one gentle push that follows the Games setting.
- **Finished drawings, creatures and stories can be shared outside the app** from a toolbar button.
- **Dropped games.** Touch is too thin to ship. Air hockey needs both phones side by side, and Paeonia is for couples who are apart. Battleship with date ideas is out.
- **"Four in a Row", never "Connect Four".** Connect Four is a Hasbro trademark. No user-visible text, VoiceOver label, push, data export, website or App Store text may use it. The Norwegian name stays "Fire på rad". The internal kind `connect_four` stays. `scripts/check-repo-rules.mjs` fails a commit or CI run that adds it.

### Setup and settings

- The Games tab opens on the hub so both partners see every game first. The first game a partner opens asks for two couple settings, play style and game language. The other partner sees the choice before their first game and can keep or change it.
- **Play style.** "Against each other" gives each partner a score and a winner. "Together" gives one shared score. Each game doc says how it plays in each style.
- **Game language.** The couple picks one language both understand (English or Norwegian Bokmal). Word lists and decoy letters use it regardless of each partner's app language.
- Games and their histories hide the tab bar on iPhone to keep the play area available.

### Hub, presence and notices

- The hub has "Right now" (full cards for the game the partner is in, then games waiting for this person) and a "More games" grid. A "Not now" button on a waiting card moves it to the grid and takes it off the tab badge.
- The Us tab shows one card, the game the partner opened most recently while they have it open, above today's questions, because the partner waiting in a game is the one thing not to miss.
- The Games tab badge counts turns, unseen results and open invites waiting for this person, except "Not now" items and those already there when the hub last showed. Opening the hub clears the badge without hiding a game.
- Every game with live play has a "Tell [Name] you want to play" button, shown when the partner doesn't have the game open. It sends one push, at most once every 15 minutes.
- When the partner opens a game, their avatar (`Features/Presence/`) opens with Call, Message and Join for 5 seconds on any screen, so joining is one tap (2026-11-15). Its toolbar offers Join while the partner is in a game this person does not have open. This replaced the partner-opened-game banner on 2026-11-15, and like the avatar it shows only while both partners share their presence. The partner's open game also shows as a Lock Screen Live Activity that names the game and whose turn it is, never a move.
- Presence is one steady green ring only while the partner has that game open. It pulses once on arrival.
- Game notices use the shared bottom glass banner, kept above action bars and composers.

### Game chat

- One ongoing chat per game type, available before, during and after play, opened from a toolbar button over the game rather than switching to Chats.
- On an upright iPhone it is a panel over the lower screen with the game still visible above, opened by a swipe up (except where the game needs the swipe, such as a canvas or map). A tap on the game, the close button, a swipe right or a drag down closes it. On iPad and a phone on its side it is a sheet.
- The app shows the swipe up instead of explaining it, at most once a day.
- Game chats show a miniature of the current visible game content, never a hidden answer.

### Queued moves and replays

- Queued moves show no local-save or offline reassurance line. Failed sends on a working connection keep their warning and retry action.
- Result buttons name the partner's next action, such as "Continue · Robin is waiting".

### Guess my spot

- Photos come from the library only, with no camera button. The couple may share live location on the Home map, which would give away a photo taken right now, so the game is about where you were.
- The spot comes from the photo's location. Without one, or when it is wrong, the sender drops the pin and always sees the spot on a map before sending.
- The phone strips the photo's metadata before upload. The spot travels separately and stays hidden until the guess.
- Scoring is logarithmic: up to 5000 points within 25 m, 0 at 20,000 km, with equal points per 10 times closer, because most photos come from near home.
- Turn-taking, one photo each, async with pushes and live when both are in, like Consensio. The Norwegian name is "Gjett hvor".
- Every round becomes a pin on one shared map ("Our guesses"). Guessed rounds also show on the Memories "Our places" map, marked as from the game and left out of its countries and cities.

## Quality bar

Check every game against this before building it.

1. **Fun within 30 seconds.** The first turn teaches the rules by playing. A game hard to learn that way also gets illustrated "How to play" cards.
2. **Works apart.** Partners are often in different time zones, so every game works async. A game with live play also works when only one partner is online.
3. **Only in Paeonia.** GamePigeon already offers classic board games in iMessage. A game earns its place with the drawing canvas, the couple's shared context, or Memories.
4. **A designed reveal.** The moment a partner sees the other's move gets the most attention to timing, haptics and animation.
5. **Hand-written content.** Word lists and prompts are written by hand per language, never translated filler.
6. **Ends gently.** No abandoned games, no guilt, no punishment for slow replies.

## Architecture rules

- **Convex owns the state of every game.** The relay (`relay/`, a Worker with one Durable Object per couple, 30 to 80 ms phone to phone, stores nothing) carries only continuous movement that never needs saving, such as strokes and finger positions. Turns, scores, hidden information, history and push go through Convex (100 to 300 ms). Simultaneous-reveal games run on Convex alone.
- **Hidden information never reaches the other phone.** Each kind returns a per-user projection of its state, never the whole row.
- **Relay sockets close after 10 minutes.** A live game reconnects with a fresh ticket and refetches state from Convex.
- **Reaction games compare reaction times, not arrival order.** Each phone measures from when its own screen showed the signal, scheduled at a shared future time with clock offset from a relay ping.
- **Game data joins relationship end and account deletion cleanup** through `deleteCoupleGameRows` in `lib/gameRegistry.ts`.
- **Pushes.** Lock-screen text names the game and that it is your turn, never the move, a drawing or written content. While the app is open, game pushes show no system banner or sound. Alerts collapse per game kind and couple.
- **Localization.** All game copy goes through the String Catalog in English and Norwegian Bokmal. Word lists exist in both languages. A dictionary-based game needs licensed lists for both.

## Catalog

All shipped games have their own doc in `docs/games/`. The relay channel and backend kind names are in `GAME_KINDS` (`backend/convex/lib/validators.ts`).

| Game | Own doc |
|---|---|
| Draw & Guess, the first game | `draw-and-guess.md` |
| Mind Meld | `mind-meld.md` |
| Exquisite corpse | `exquisite-corpse.md` |
| Story Chain | `story-chain.md` |
| Four in a Row, Dots and Boxes, Ultimate Tic-Tac-Toe | `board-games.md` |
| Ludo | `ludo.md` |
| Consensio | `consensio.md` |
| Guess my spot | `guess-my-spot.md` |
| Piccante | `piccante.md` |

The hub picture standard is `hub-artwork.md`.

Not built: Reaction duel (tap when the flower opens, using the fairness rule above). Deferred as expensive: chess (needs a rules engine) and a Wordfeud-style word game (needs licensed English and Norwegian dictionaries).

## Adding a game

All kinds are registered on the backend (`GAME_KINDS`), the relay (`ALLOWED_CHANNELS`) and Swift (`GameKind`), and `scripts/check-repo-rules.mjs` checks that the three lists match. A kind shows in the app only once its hub model is in `GamesViewModel.games`. Draw & Guess is the worked example for every point. Add your lines at these points and leave other games' lines alone.

- **Naming.** Backend module `backend/convex/<camelKind>.ts` with helpers in `lib/<camelKind>.ts`. Tables start with the kind. Swift types, files, `GamesDestination` and `SyncPendingOperationKind` cases, and `DeveloperScenario` members start with the Swift prefix. String Catalog keys start with the Swift prefix. Deep link `paeonia://games/<kebab-kind>`.
- **Backend.** Tables in `schema.ts` with a `couple_id` index. Check access with `getCurrentEntitledCoupleId` or `requireCoupleAccess` (`lib/access.ts`). Replace your `null` in `GAME_BACKENDS` (`lib/gameRegistry.ts`) with a `GameBackend`. Queue pushes with `enqueueGamePush` and add your entry to `GAME_PUSH_COPY` in `lib/notificationCopy.ts` first. Invites, presence, live tickets, settings and "Not now" need nothing, because `games.ts` takes every kind.
- **Relay.** Nothing.
- **iOS.** Follow the Draw & Guess pattern for the gateway, cache, live feed, `GameHubModel`, `GamesDependencies`, `GamesPendingOperationRegistry`, `GameScreenLoops` heartbeat, `GameLiveChannel`, `GameAttention`, `GameChatScreen` and developer scenarios. Read play style and language from the overview and never ask for them in your game. Reuse `Features/Games/Shared/` (reload gate, stars, canvas, stroke replay) instead of copying code. Play a `GameSound` next to each haptic, following [the audio standard](game-audio.md). Clear your cache in `LocalPrivacyPurgeService`.
- **Checks.** `npm run typecheck` and `npm test` in `backend/`. Test on a local backend (`scripts/local-backend`). A branch never deploys to `api.paeonia.no`, because a deploy replaces every function there, including other games'.
- **Ownership.** A game owns its iOS folder, tests, backend module, tables and design doc. Do not change Draw & Guess's tables or code except to move code you reuse into `Features/Games/Shared/` while Draw & Guess behaves the same. Shared files take small additions at the points above. Ask the developer before a real change to a shared seam.
- **Merging.** Conflicts at the registry points and in `Localizable.xcstrings` are two lists growing. Keep both sides and merge the String Catalog by key. Anything more, stop and ask.

## Accessibility rules

- With iOS Differentiate Without Color, Increase Contrast or Paeonia's High contrast switch on, board pieces add an owner symbol (circle for player one, diamond for player two) beside the mark and in player headers. Ludo cap textures never show it.
- Both drawing games lock canvas edits, shape controls, undo, redo, fill and clear while the captured drawing is queued, so edits made after capture are never silently dropped. A failed queue unlocks the same drawing.
- Neither drawing game expires the artist's turn, and Draw & Guess guessing has no deadline. "Against each other" awards an optional speed bonus for 15 or 30 seconds from the first received live stroke or replay-ready clue, including time reading a description, with no pause. "Together" has no speed bonus. Whether competitive reading time is usable is untested.
- Shape composition, geometry readouts and authored descriptions do not make freehand drawing recognizable to blind players. The task and device gate is in [the accessibility report](accessibility-report.md).
- More > Accessibility controls optional visible tools (extra controls, media descriptions). They default to off and show even while assistive technology is active.

## Open questions

- Which game comes after the current catalog.
