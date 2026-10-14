# Draw & Guess

Design for the first game. The backend, the iOS foundation and the game screens are built. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Draw & Guess.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-12.

- **Draw & Guess is the first game.**
- **Async and live both ship in the first version.** One partner draws, and the other watches the drawing play back stroke by stroke whenever they open the app. When both have the game open, the guesser watches the drawing happen live. Draw Something (2012) proved the async loop works on phones.
- **Supports both play styles.** The couple's play style decides the scoring. See "Scoring".
- **Words come in the couple's game language.** See `docs/games-plan.md`.
- **No streak of its own.** Turns count toward the couple's existing streak. See "Streak".

Decided on 2026-10-13.

- **The speed bonus has tiers.** A correct guess within 15 seconds of first seeing the drawing earns 2 points, within 30 seconds earns 1, and later earns 0.
- **First-try bonus.** The guesser earns 1 point when the correct guess is the round's first attempt and no hint was used.
- **Hints.** The guesser can ask for letter hints. The phone decides which letters a hint shows, and the server only counts them. Any hint sets both bonuses to 0. Hints don't change the word points.
- **Reactions.** The guesser can react to a finished round with love, laugh or wow. Nobody gets a push for it.
- **Personal stars.** Each partner can star finished rounds. A star is private, and nobody is told.
- **History replaces save to Memories.** Draw & Guess no longer saves to Memories. The game keeps its own history of finished rounds with their drawings. See "History and stars".
- **The result is marked seen on the server.** Each partner's "I have seen this result" is stored on the round, so a second phone doesn't show the result again.

## Why this game first

- It works across time zones, and it gets better when both partners happen to be online.
- It uses the drawing canvas, which other game apps don't have and Paeonia already does. Saved drawings are `PKDrawing` data (`widget_drawing_revisions.format = "pkdrawing"`), and each PencilKit stroke point keeps its time offset, so a saved drawing can be replayed at the pace it was drawn.
- Live watching reuses the live drawing code in `WidgetDrawing/Live/`: relay presence, the `hello` and snapshot catch-up, and stroke playback at the drawn pace.
- Building it produces the turn engine, the drawing replay, and a history of finished drawings. Exquisite corpse needs all three later.

## The turn

The game never ends. A couple has one ongoing Draw & Guess game, and a turn has two halves done in one sitting.

1. **Guess.** Open the game and your partner's drawing starts playing back. Guess by tapping letter tiles. You can guess while the drawing is still playing.
2. **Reveal.** The word locks in, the rest of the drawing finishes at once, and the phone gives a success haptic. The screen shows how long the guess took.
3. **Result.** The guesser can react, and either partner can star the round (see "History and stars").
4. **Draw back.** You pick a word and draw it for your partner.

The very first turn of a new game skips the guess and starts at "Draw back".

### Picking a word

The drawer chooses one of three words: easy, medium, or hard. Harder words score more points. The three choices are fixed when the turn begins, so reopening the game doesn't give new ones. A fourth choice is "Draw your own", where the drawer types any word or short phrase. That is how a couple uses inside jokes ("the dog at your mom's house"). A custom word holds 2 to 20 letters and at most three words separated by single spaces. Letters are A to Z, plus Æ, Ø and Å. A custom word scores like a medium word.

The server picks the three suggested words from the couple's game language, so the guesser can't see them ahead of time. A couple sees each word only once until the list runs out.

The round starts in Convex the moment the drawer picks a word, not when they finish. A partner who opens the game while the drawer is still drawing can start guessing right away.

### Drawing

- Use the existing PencilKit tools from `WidgetDrawing/Canvas`.
- No time limit while drawing.
- The drawer taps Done to send. A correct live guess also ends the drawing (see "Live").

### Replay

- The replay shows the strokes in the final drawing in the order they were drawn. Erased strokes don't play back.
- The canvas keeps the pixel eraser (`PKEraserTool(.fixedWidthBitmap)`). PencilKit hides erased ink with `PKStroke.mask` and `maskedPathRanges`, and splits a stroke into pieces that share its path and `creationDate`. The replay plays only the visible part of each piece at its original time offsets, and every partial stroke keeps the mask, transform and ink, so erased ink never shows. Live sync sends masked strokes too, because the stroke signature includes the mask.
- Long pauses in the replay are shortened to about one second, so a drawer who stopped to think doesn't make the guesser wait.
- The guesser can hold the replay to fast-forward.

### Guessing

- Guessing uses tiles, not the keyboard. The screen shows one empty slot per letter, with gaps for spaces. Below the slots are the answer's letters mixed with decoy letters, about 12 tiles for a short word.
- Decoys come from the game language, so a Norwegian word can show æ, ø and å tiles.
- When every slot is filled with a wrong word, the slots shake and the letters go back to the tiles.
- Guesses ignore case. Tiles show capital letters.
- Attempts are unlimited. A "Show me" button reveals the answer, and the round counts as missed.
- A quiet "Show a letter" button places a random letter of the answer in its slot and locks that slot. The phone can show at most all letters but one. Any hint takes both bonuses away for the round (see "Scoring").
- Every attempt is saved in Convex with a timestamp. In a live round the drawer sees each wrong guess appear while drawing. In an async round the drawer watches the guesses in order afterward ("They tried CAT, then HAT..."). That is the drawer's payoff for the turn.

## Live

Live runs whenever both partners have the game screen open. Without the partner there, everything works as an async round. Nothing about the round changes except how fast each side sees the other.

- **Presence.** While the game screen is open, the phone joins the game's relay room. The relay's `welcome`, `joined` and `left` messages tell each phone whether the partner is there. Reuse `WidgetLivePresence`. Each phone's `hello` carries a role that says what its screen is doing, so the other phone never guesses. The widget canvas sends `drawing` and `watching`. The game adds three roles that the widget never sends.
  - `drawing`: the drawer of a round that has not ended. The drawer stays `drawing` after Done while waiting for the guess, so the guesser keeps the live canvas.
  - `watching`: watching live, waiting for the drawing, or guessing.
  - `choosing`: on the choose word screen.
  - `result`: on the reveal or the drawer's result screen.
  - `present`: in the game on any other screen.

  When a partner has several sockets in the room, the activity is the first role in that order. `DrawAndGuessPhase.liveRole` maps a phase to a role, and `DrawAndGuessPartnerPresence` maps the partner's role back to the copy (`present` reads as `here`, the heartbeat-only state). The drawer sees "[Name] is watching" only for a partner who is `watching`. A waiting partner sees "[Name] is drawing for you".
- **Strokes.** The drawer's strokes stream over the relay as in `WidgetLiveMessage` and play on the guesser's screen through `WidgetLivePlayback`.
- **Joining late.** A guesser who opens the game mid-drawing asks for a snapshot with `hello`, as `WidgetLiveRoom` does. The strokes so far play back quickly, then live strokes follow. A drawer who has tapped Done has no canvas left to answer, so a guesser who joins then gets no snapshot. The guesser's phone downloads the sent drawing and replays it whenever the live canvas holds no strokes.
- **Guesses.** Guesses go through Convex, because they are saved anyway. The drawer's live query shows them within a few hundred milliseconds.
- **The guess screen.** While guessing, the guesser's phone sends its screen to the room as a `DrawAndGuessLiveMessage`: the letters in the slots, whether a wrong word is showing, and where the replay is (its replay time and speed). It sends the whole screen whenever it changes, and again when the drawer joins or this phone connects to a room the drawer is in. Nothing in it is saved. The drawer's result screen shows it (see "The drawer's result").
- **A correct guess** ends the round right away. The drawer's phone sends the drawing as it is at that moment, and both phones show the reveal together. The roles then swap. The new drawer picks a word while the other partner stays to watch, so two partners who are both online can play back and forth without leaving the screen.
- **The drawer taps Done before a correct guess.** The round continues as a normal round, and the guesser keeps guessing on the finished drawing.
- **Lost connection.** The drawer keeps drawing and the drawing still sends on Done. The guesser's phone reconnects and asks for a fresh snapshot. The relay closes sockets after 10 minutes (`SESSION_MS`), so the same reconnect path runs during long rounds without the players noticing.
- **Invite.** When the partner isn't in the game, either partner can tap "Tell [Name] you want to play" (see `docs/games-plan.md`). The push opens Draw & Guess directly, so the partner lands in the live round.
- **Relay room.** The game needs its own room so it doesn't share the 4-socket cap with Home and the widget canvas. This is the relay channel change in `docs/games-plan.md`, and the first version needs it.

## Scoring

The play style is a couple setting (see `docs/games-plan.md`).

**Together.** One shared score. Each correct guess adds the word's points to the couple's total. A missed round adds nothing and takes nothing away.

Points are 1 for easy, 2 for medium and 3 for hard. A custom word scores 2.

**Against each other.** Each partner has their own score. The drawer gets the word's points when the guess is right. The guesser gets the word's points plus two bonuses.

- **Speed bonus.** 2 points when the guess comes within 15 seconds of first seeing the drawing, 1 point within 30 seconds, and 0 after that. The time is what the guesser's own screen showed. Watching live, the clock starts at the drawer's first stroke, so a drawer who opens the canvas and does something else first does not use it up.
- **First-try bonus.** 1 point when the correct guess is the round's first attempt.
- **Hints.** A hint doesn't change the word's points. Once the guesser uses any hint, the speed bonus and the first-try bonus are both 0 for that round.

Both partners draw and guess equally often, so the difference between the totals comes down to how fast and how well each one plays.

In both styles the scores keep growing and never reset. The server keeps the shared total and both personal totals at all times, so switching play style loses nothing.

## Streak

Draw & Guess counts toward the couple's existing streak through a new game activity kind in `ACTIVITY_KINDS` (`backend/convex/lib/streaks.ts`). Sending a drawing counts, with the round id as the dedupe key. Guessing alone doesn't count, because the turn isn't done until you draw back.

## History and stars

Draw & Guess does not save to Memories. The game keeps its own history instead, and each partner can star the rounds they want to find again.

- **History.** The history lists the couple's finished rounds (solved or missed) that hold a drawing, newest first. It pages by round number, up to 50 rounds a page. The caller can ask for starred rounds only. Each round shows the word, the difficulty, the points, the solve time, the bonuses, the hints used, the number of attempts, the reaction, and whether each partner starred it. The game state (`current_round`, `recent_rounds`) and a round read by id (`get_draw_and_guess_round`) carry `starred_by_me` too, so a round starred on another phone shows as starred on the result screen. The drawings stay readable through `get_media_signed_url` for as long as the couple's game rows exist.
- **Stars.** Either partner can star or unstar a finished round. A star is private. The partner is not notified. The server returns only the caller's own stars (`starred_by_me`), so a partner's stars never leave the server. Stars are deleted with the rest of the couple's game rows.
- **Reactions.** The guesser can react to a finished round with love, laugh or wow, or clear the reaction. The last choice wins. It is stored on the round and both partners see it. No push goes out.
- **Personal best.** A solve with no hints and a solve time is a personal best when it beat every earlier hint-free solve by the same guesser, and at least one such solve exists. The server decides this when the guess arrives and stores it on the round, so later faster solves don't change older rounds.
- **Records.** For each partner: solves as the guesser, first-try solves, average solve time, fastest solve with its word, and drawings the partner solved. The average covers hint-free solves of 10 minutes or less. The fastest covers every hint-free solve.
- **Result seen.** Each partner marks a finished round's result as seen once. The server keeps the first time for the drawer and for the guesser separately. The app uses it to decide whether to show a finished round's result again.

## Word lists

- Each language has its own list, written by hand. Norwegian is not a translation of English. It can include Norwegian things like brunost or a fjord.
- Every word must be drawable and must make sense to a 16-year-old.
- A native speaker reads every word before it ships. The check covers slurs, words with a crude second meaning, and words most people don't know. An agent once added "pakkis" to the Norwegian list, a slur for Pakistanis, and only the developer's read caught it.
- Start with about 300 words per language, split across easy, medium and hard.
- Words live in the backend, like the question catalog in `backend/questions/`, so the list can grow without an app update.

## Data

The Draw & Guess functions are in `backend/convex/drawAndGuess.ts` and its helpers in `backend/convex/lib/drawAndGuess.ts`. Settings, invites, presence, and the relay ticket are shared by all games in `backend/convex/games.ts` and `backend/convex/lib/games.ts`. `drawAndGuessBackend` in `lib/drawAndGuess.ts` is the game's entry in the registry (`lib/gameRegistry.ts`), which handles push checks, the reminder cron, language changes, and cleanup. The shared rules are in `docs/games-plan.md`.

- `game_settings`: one row per couple with the play style and the game language. Either partner writes it, and the last write wins. Changing the language replaces the words offered for the open turn.
- `games`: one row per couple with `kind = "draw_and_guess"`, created by `ensure_draw_and_guess_game` (the caller draws first). `state` is `choosing_word`, `drawing`, or `guessing`, and `turn_user_id` is the partner who acts next. The row holds the shared total (`shared_points`), each partner's own total, the three word choices while a word is being chosen, and the start of the turn. `version` goes up with every change.
- `game_moves`: one row per round. It holds the word (or the custom word), the difficulty, the drawing as `pkdrawing` media in the `game-drawings` bucket, the time the guesser first saw the drawing, and the result (`drawing`, `guessing`, `solved`, or `missed`). A solved round also holds `solve_ms`, `speed_bonus` (0, 1 or 2), `first_try_bonus` (0 or 1), `hints_used` and `personal_best`. A finished round can hold `guesser_reaction` (`love`, `laugh` or `wow`) and the two result seen times, `drawer_result_seen_at` and `guesser_result_seen_at`. The round exists from the moment the drawer picks a word. The client creates the round id, so a drawing queued offline can name its round.
- `game_guesses`: every attempt with its timestamp. The query returns the newest 200 attempts of each round, oldest first, and the exact number of attempts in `attempt_count`.
- `game_round_stars`: one row per partner and starred round, with the round number so one partner's stars page in order.
- `game_used_words`: the words the couple has already been offered, per language and difficulty. A difficulty starts over when all its words were offered.
- `game_presence` and `game_invites`: the open game screen, and the last invite each partner sent.
- The guesser's phone receives the word when the round starts, because it builds the tiles and checks guesses locally for instant feedback. The UI never shows the word before the reveal. Cheating isn't a real risk between partners, so the server doesn't hide the word. The three word choices are different: only the drawer whose turn it is receives them.
- A turn drawn offline is saved on the phone and sent when the phone is back online. The UI tells the drawer: "Saved on this phone. We'll send it when you're online." Picking a word, sending a drawing, a guess, and giving up are safe to retry.
- Scoring: a correct guess adds the word's points to the shared total and to the drawer's total. The guesser's total gets the word's points plus the speed bonus plus the first-try bonus. The server keeps all three totals whatever the play style, so the style only changes what the app shows.
- The speed bonus follows what the player saw. A correct guess carries `p_speed_bonus` (the tier on screen: 0, 1 or 2), `p_solve_ms` (time since the player first saw the drawing) and `p_hints_used` (how many letters the hints showed), all from the phone's clock and screen. The server refuses a speed bonus outside 0 to 2, a negative or non-numeric solve time, and a hint count that is not a whole number from 0 up. It stores a solve time longer than 30 days as 30 days, so a guess after a long break still counts. The hint count can be at most the word's letters minus 1, not counting spaces, and a larger count on a correct guess is refused. When the claims are missing, `scoreSolve` in `lib/drawAndGuess.ts` decides the speed bonus from `guesser_first_seen_at`: 2 within 15 seconds, 1 within 30 seconds, 0 after that or without a first look. With any hint, the speed bonus and the first-try bonus are 0 whatever the claim says. The server works out the first-try bonus itself: the correct guess is the round's first stored attempt and no hint was used. A guess that waited in the offline queue, or that reached the server before `mark_round_seen`, keeps the bonus the screen showed. All three values are part of the request hash for the guess, so a retry with different values is refused. A wrong guess ignores them. Either partner could send false values, which is acceptable for a two-person game.
- A correct guess ends the round at once, even when the drawer has not sent the drawing yet. The guesser's turn to draw starts, and the drawer's later `submit_drawing` attaches the drawing to the solved round without changing the turn.
- Relationship cleanup deletes every game row of the couple, including stars, and queues the drawings for deletion. Presence rows go as soon as the relationship ends. Account deletion ends the relationship, so it follows the same path.

## Notifications

- "Your turn in Draw & Guess" when a drawing arrives. It is not sent when the round was solved live before the drawing arrived.
- "[Name] guessed your drawing" when the partner gets it right. This is the `game_result` push.
- "[Name] wants to play Draw & Guess with you" for an invite. The app allows one invite per partner every 15 minutes.
- One reminder, "Your turn in Draw & Guess", when a turn has waited 72 hours. A move never gets a second one.
- Never show the word or the drawing on the lock screen. The push payload holds only ids and the deep link `paeonia://games/draw-and-guess`.
- Skip the turn and result pushes when the partner has the game screen open, because they already see it live. Convex can't see relay presence, so the game screen also keeps a presence row in Convex while it is open, the same way `chatPresence.ts` tracks open chats. The open screen refreshes the row every 30 seconds, and a row older than 60 seconds counts as gone.
- Game pushes follow the "Games" switch in notification settings (`games_enabled`, on by default).
- A push waits in the outbox until the drain sends it, and the drain checks it again first. It drops a game push when the recipient can no longer play in the couple, a turn push once the round no longer waits for that guesser, and a reminder once the turn moved on.

## Screens

The screen-by-screen design. It does not change the rules above. Copy keys start with `games.drawAndGuess.` and the tables list only the part after it. "[Name]" is the partner's display name (`WidgetSyncIdentityStore`, falling back to `pairingCelebrationPartnerName`, as `WidgetDrawingView` does). Counts such as points, seconds and tries use String Catalog plural variants. Norwegian is Bokmål. Add every string to the catalog with a translator comment.

### Shell shared by every phase

- One screen, `DrawAndGuessScreen`, opened from the Games tab and from the invite and turn pushes. It shows one phase at a time, picked from the game row, the current round, my role, and relay presence. The wire-up is the view model's job, not the view body's.
- Look. `.paeoniaBackgroundSecondary` background, `.preferredColorScheme(.dark)`, inline title "Draw & Guess" / "Tegn og gjett", dark toolbar, as in `WidgetDrawingView`. The canvas surface is `.paeoniaBackgroundPrimary` with the widget ink palette, so a saved drawing looks like a widget drawing.
- No cards. Only repeated items with meaning get a fill (word rows, tiles, slots, chips): `.paeoniaSurfacePrimary` or `.paeoniaSurfaceSecondary`, `PaeoniaRadius.radius12` for tiles and slots, `radius16` for word rows.
- One square. Drawing and replay use the same square, side = min(width, space left), so strokes never rescale between drawing and watching. Phases never resize it. The two result phases shrink it to 80% once (see Reveal).
- Side from the real rows. On a phone `GamePhaseLayout` measures the rows above and below the square once they exist, and sets the side so the screen fits without scrolling when the width allows it (minimum 200 pt, then it scrolls). A result that is playing freezes the side the guess screen had, and the drawer's result screen takes the side the drawing screen had (`GameSideMemory`), so the square never jumps. At accessibility text sizes the tiles are tall and the screen scrolls.
- No tab bar. `DrawAndGuessScreen` hides the tab bar (`.toolbar(.hidden, for: .tabBar)`). It comes back on the Games hub.
- Bottom clusters are pinned with `safeAreaInset(edge: .bottom)`, capped with `.paeoniaReadableWidth()`, buttons `PaeoniaSpacing.space12` apart. A text-only action keeps a `compactButtonHeight` hit target.
- Phase change. Cross-fade plus a 12 pt rise over `PaeoniaMotion.meaningfulMoment`. Reduce Motion: cross-fade over `motionFast`, no rise.
- Partner colors. Avatars are `PaeoniaProfilePhotoAvatar`, tinted `.paeoniaPartnerOne` for me and `.paeoniaPartnerTwo` for the partner.
- Gold. `Color.paeoniaInkGold` marks only the speed bonus, the way it marks the streak milestone eyebrow.

**Score display.** It shows on the choose and waiting phases, as a non-tappable capsule (`.paeoniaSurfaceSecondary`, `caption` semibold) in the trailing toolbar. It never shows while drawing or guessing, because nothing there needs it. The reveal shows scores in its own panel.

| Style | Capsule | VoiceOver |
|---|---|---|
| Together | `heart.fill` + "12 points" / "12 poeng" | "Together, 12 points" |
| Against each other | my avatar (22 pt) + 14, partner avatar + 11. No leader marking. | "You 14 points, [Name] 11 points" |

At accessibility Dynamic Type sizes the capsule moves out of the toolbar to the first line of the content.

**Haptics used.** Existing tokens only, plus one new one.

| Moment | Token |
|---|---|
| Pick a row, tool, color, tile | `PaeoniaHaptics.selection()` |
| Done sent | `drawingSent()` |
| Partner joins, guess arrives, missed answer | `partnerDrawingReceived()` (soft) |
| Letter ripple on reveal | `streakTick(intensity:)`, 0.25 rising to 0.85, at most 8 ticks |
| Reveal lands | `answerRevealed()` |
| Score count-up and speed bonus | `streakTick`, then `streakContinued()` for the bonus |
| Show a letter, pick a reaction | `selection()` |
| Reaction arrives on the drawer's result | `partnerDrawingReceived()` |
| Invalid custom word | `validationError()` |
| Wrong word (new) | `gameWrongGuess()`, two soft impacts 60 ms apart, built on the private `impact` helper. A wrong guess is not an error, so it does not use the error notification. |

### 1. Choose a word

Purpose. Make one quick choice and start. The round starts in Convex when the drawer taps Start, so the choice has a confirm step.

Layout, top to bottom.
1. Title "Pick a word to draw" (`PaeoniaTypography.heroTitle`), one line of subtitle in `.paeoniaTextSecondary`.
2. Three word rows in a `VStack(spacing: space12)`, easy, medium, hard from top to bottom. A row is `radius16`, `.paeoniaSurfaceSecondary`, minimum 64 pt tall. Left, the word in `PaeoniaTypography.title`. Under it, "Easy, 1 point" in `caption`, `.paeoniaTextSecondary`. Right, difficulty pips: 1, 2 or 3 `camera.macro` flowers in `.paeoniaAccentPrimary`. At accessibility sizes the pips hide, the text stays.
3. "Draw your own" row, same shape, with `square.and.pencil` instead of pips.
4. Pinned bottom: primary "Start drawing", disabled until a row is selected.

Interactions.
- Tap a row to select it. The row gets a `strokeEmphasis` `.paeoniaAccentPrimary` border and a `checkmark.circle.fill`, with `buttonPress` timing and `selection()`. Tapping another row moves the selection. Nothing is selected at first, so no word is pushed on the player.
- Start commits. Haptic `drawingSent()`. The button shows its loading state until Convex confirms, then the drawing phase opens. The pick is safe to retry.
- Draw your own. Tapping the row collapses the three word rows (`stateChange`) and turns the row into a text field with focus. The system keyboard is used here, never letter tiles. The field has `autocorrectionDisabled`, `submitLabel(.done)`, no autocapitalization, and a trailing "Cancel" text button (`common.cancel`, 44 pt) that brings the three rows back and drops the keyboard. The Start button sits above the keyboard. In landscape on iPhone only the field and Start show.
- Validation runs `DrawAndGuessCustomWord.validate` on every change. The Start button is disabled while the field is empty or a message shows. A letter counter ("7/20", `caption`, `.paeoniaTextTertiary`) counts letters without spaces and turns `.paeoniaErrorText` past 20.
- Failures show as one line under the field with `exclamationmark.circle`, `caption`, `.paeoniaErrorText`. This is field validation, not a transient error, so it stays inline instead of using the top banner. VoiceOver gets each new message as an announcement. Too-short is the exception, because every word starts too short. It shows only after the player taps Done on the keyboard or taps Start, with `validationError()`.

| Key | English | Norwegian |
|---|---|---|
| `choose.title` | Pick a word to draw | Velg et ord å tegne |
| `choose.subtitle` | [Name] will guess it. | [Name] skal gjette det. |
| `choose.subtitleFirst` | [Name] guesses it, then you swap. | [Name] gjetter, så bytter dere. |
| `difficulty.easy` / `.medium` / `.hard` | Easy / Medium / Hard | Lett / Middels / Vanskelig |
| `points` | %lld point / %lld points | %lld poeng |
| `choose.own.title` | Draw your own | Tegn noe eget |
| `choose.own.subtitle` | An inside joke or a place only you two know. 2 points. | En intern vits eller et sted bare dere to kjenner. 2 poeng. |
| `choose.own.placeholder` | Type a word or a short phrase | Skriv et ord eller en kort frase |
| `choose.start` | Start drawing | Begynn å tegne |
| `choose.error.tooShort` | Use at least 2 letters. | Bruk minst 2 bokstaver. |
| `choose.error.tooLong` | That is a bit long. Use 20 letters at most. | Det er litt langt. Bruk høyst 20 bokstaver. |
| `choose.error.tooManyWords` | Use 3 words at most. | Bruk høyst 3 ord. |
| `choose.error.character` | Use only the letters A to Z, Æ, Ø and Å. | Bruk bare bokstavene A til Z, Æ, Ø og Å. |
| `choose.letterCount.a11y` | %1$lld of %2$lld letters | %1$lld av %2$lld bokstaver |

VoiceOver. Rows read "Cat, easy, 1 point", with the `.isSelected` trait on the chosen one. Order is title, rows, Draw your own, Start.

First ever turn. There is no guess. The screen opens straight here with `choose.subtitleFirst`, and the subtitle is the only teaching. The first-time game setup (play style and language) runs before this and belongs to the Games tab.

Offline and empty. The three words come from the game row, so they are cached after the first sync. With the turn mine, the state loaded and no words in it (`choicesUnavailable`), show `PaeoniaEmptyStateView` (`wifi.slash`): "You're offline" / "Du er ikke på nett", "Connect to the internet to get your words." / "Koble til internett for å få ordene dine.", action `common.tryAgain`. "Draw your own" needs no words, but the round still has to start in Convex, so it waits for the network too. The Start button then shows the sent-offline line from phase 2 and queues the pick. The message never shows during the hand-off to drawing. After a pick the phase changes and the view model clears the word list in the same step, while the old screen is still fading out. That screen keeps the words it showed, and the offline message follows `choicesUnavailable`, which is false outside the choose word phase.

### 2. Drawing

Purpose. Draw without friction, and feel the partner there.

Layout, top to bottom (the widget canvas layout with two added lines).
1. Word line, one fixed line. Eyebrow "Draw" (`caption` bold, uppercase, tracking 1.4, `.paeoniaTextTertiary`) and the word in `PaeoniaTypography.title`, `minimumScaleFactor(0.6)`. At accessibility sizes it may use two lines, and the screen scrolls.
2. Live row, one fixed line (24 pt minimum, the `WidgetDrawingCanvasHeader` pattern). Leading, the presence. Trailing, the newest wrong guess.
3. Square canvas (`PencilKitCanvasView`, the widget view model's tool and drawing state).
4. `WidgetDrawingToolControlsView`, `WidgetDrawingColorControlsView`, `WidgetDrawingSizeControlsView`, unchanged, including the pen-double-tap modifier.
5. Pinned bottom: primary "Done", disabled while the canvas has no strokes.
Toolbar trailing: "Clear" with a centered alert (not the widget's copy, which talks about widgets).

Live indicator. The leading slot follows what the partner's phone says it is doing. A partner who is `watching` shows the avatar (24 pt, accent ring) and "[Name] is watching". A partner still on the result of the last round shows "[Name] is still looking at the last round", and one who is in the game but has not said more shows "[Name] is here", both without the ring. When the partner joins, the avatar scales 1 to 1.12 and back once (`motionDefault`) and `partnerDrawingReceived()` fires. Reduce Motion: no scale, the haptic stays. When the partner is away the slot shows "[Name] will see it later" in `.paeoniaTextTertiary`, so async never feels broken. VoiceOver announces the line whenever it changes to a new one.

Wrong guesses while drawing. The newest wrong guess fills the trailing slot as a capsule (`.paeoniaSurfacePrimary`, `caption` semibold, `.paeoniaTextSecondary`, never red). It arrives with `cardReveal` and an 8 pt rise, replaces the previous one, and fades out after 6 seconds, so the row is calm again. No layout shift, because the slot is always laid out. Haptic `partnerDrawingReceived()` only while no stroke is in progress (`onStrokeInProgressChange`). Reduce Motion: fade only. VoiceOver gets a queued, low priority announcement "[Name] tried CAT". Every guess is kept for the drawer's result (phase 6).

Done. `drawingSent()`, then the phase 6 "sent" view. Offline, the drawing is stored on this phone and the sent view shows the offline line below. A draft survives leaving the screen and relaunching, as `WidgetDrawingDraftStore` does.

The partner solves it mid-drawing. The canvas stops taking touches in the same frame, and a stroke in progress is kept. The phone sends the drawing as it is, the tool rows fold away (`stateChange`), and the phase 6 reveal plays. The drawer is never asked anything while it happens.

| Key | English | Norwegian |
|---|---|---|
| `draw.wordLabel` | Draw | Tegn |
| `draw.watching` | [Name] is watching | [Name] ser på |
| `draw.later` | [Name] will see it later | [Name] ser den senere |
| `draw.here` | [Name] is here | [Name] er her |
| `draw.lookingAtResult` | [Name] is still looking at the last round | [Name] ser fortsatt på forrige runde |
| `draw.tried` | [Name] tried %@ | [Name] prøvde %@ |
| `draw.sendOffline` | Saved on this phone. We'll send it when you're online. | Lagret på telefonen. Vi sender den når du er på nett. |
| `games.drawing.clear.title` | Clear the drawing? | Tømme tegningen? |
| `games.drawing.clear.message` | This removes everything you've drawn so far. | Dette fjerner alt du har tegnet så langt. |
| `games.drawing.clear.action` / `.cancel` | Clear / Keep drawing | Tøm / Fortsett å tegne |

The offline line uses `.paeoniaSyncPending` with `clock`. The Done button reads `common.done`, with the accessibility label "Done, send to [Name]" / "Ferdig, send til [Name]".

### 3. Waiting for the partner to draw

Purpose. Say what is happening, and make the wait feel shared.

Variants, one layout.
- Waiting for the word. The title follows the partner's role. On the result screen: "Waiting for [Name] to continue". On the choose word screen: "[Name] is picking a word". Away or unknown: "Waiting for [Name]", with the later hint and the invite button. The live hint is left out here, because there is no drawing to watch yet.
- Partner drawing, live or not. Title "[Name] is drawing for you".
- The title of the screen is fixed when it opens, so it does not change its words while it fades out into the guess.
- Reaction to my drawing. The drawer can tap Continue before the guesser reacts. While this screen waits for the partner's next word, the reaction to the round I just drew shows under the title in the same capsule as on the drawer's result. The drawing is not on this screen, so the line names the word: "[Name] loved the UMBRELLA drawing". The word goes in front of "drawing" ("PARAPLY-tegningen" in Norwegian), so verbs, plurals, any gender and custom phrases all read right. When it arrives while the screen is open, it rises in with `cardReveal` and `partnerDrawingReceived()`, and VoiceOver reads the line. Reduce Motion: fade only. Once the partner picks a word, the reaction stays in "Our drawings".
- Once the round has started, dim answer slots appear under the title with "5 letters". It is the first hint that something is coming, and it leaks nothing, because the guesser's phone has the word anyway.

Layout, centered in the content, top to bottom.
1. Partner avatar, 96 pt. When the partner is in the room, a soft ring breathes around it (`.paeoniaAccentPrimary` at 0.2 to 0.5 opacity over 2.4 s, repeating). Reduce Motion: a still ring at 0.35.
2. Title (`PaeoniaTypography.title`) and one line of hint.
3. Dim slots (optional, see above).
4. Pinned bottom, only while the partner is not in the game: the invite button.

The invite button is secondary style, "Tell [Name] you want to play". After a send it is disabled and reads "Sent" with `checkmark`, with a caption under it, "You can send another at [time]". It comes back when `last_invite_at` is 15 minutes old, on the view model's next 15 second tick. Do not use `TimelineView(.explicit([until]))` for this. Its first render gets `context.date == until`, so the button would never read "Sent". It hides while the partner has the game open. A failed send uses the top banner and leaves the button enabled.

The switch to guessing happens at the first stroke (live) or when the drawing arrives (async). The avatar fades out as the canvas rises in with `cardReveal`. Reduce Motion: cross-fade.

| Key | English | Norwegian |
|---|---|---|
| `wait.choosing` | [Name] is picking a word | [Name] velger et ord |
| `wait.drawing` | [Name] is drawing for you | [Name] tegner for deg |
| `wait.generic` | Waiting for [Name] | Venter på [Name] |
| `wait.continue` | Waiting for [Name] to continue | Venter på at [Name] skal fortsette |
| `wait.hintLive` | You'll watch it happen. | Du ser det skje. |
| `wait.hintLater` | The drawing will show up here. We'll tell you when it's ready. | Tegningen dukker opp her. Vi sier fra når den er klar. |
| `wait.letters` | %lld letters | %lld bokstaver |
| `wait.invite` | Tell [Name] you want to play | Si til [Name] at du vil spille |
| `wait.inviteSent` | Sent | Sendt |
| `invite.sentUntil` | You can send another at [time] | Du kan sende en ny kl. [time] |
| `wait.reaction.love` | %1$@ loved the %2$@ drawing | %1$@ elsket %2$@-tegningen |
| `wait.reaction.laugh` | %1$@ thought the %2$@ drawing was funny | %1$@ syntes %2$@-tegningen var morsom |
| `wait.reaction.wow` | %1$@ said wow to the %2$@ drawing | %1$@ sa wow til %2$@-tegningen |

VoiceOver reads avatar and title as one element. The ring is hidden. The score capsule sits above.

### 4. Guessing

Purpose. Watch, guess fast, feel clever.

Layout, top to bottom.
1. Live row, one fixed line. Leading, "[Name] is drawing for you" while live, "[Name] is watching you guess" with the accent ring while the drawer is in the game after Done (their result screen shows this screen), or "[Name] drew this for you" otherwise (avatar 24 pt). Trailing, the speed bonus label in "Against each other" only, until the first hint (see below).
2. Square replay (`GameReplayTimeline` driven by `GameReplayClock`). A 2 pt progress line runs along its bottom edge in `.paeoniaAccentPrimary` at 0.6 opacity.
3. Language line, only when the word's language differs from the app's: `globe` and "The word is in English" in `caption`, `.paeoniaTextSecondary`, centered above the slots. It follows the couple's game language, as the decoy tiles do. A custom word gets no line, because the drawer could type it in any language. It fades out with the live row on the reveal.
4. Answer slots, centered, one group per word. A group never splits unless one word is wider than the screen at the smallest slot. Then it splits into even pieces on separate lines (`DrawAndGuessSlotSizing`). Slots are 28 to 44 pt wide, the widest that adds no line, and 48 pt tall. An empty slot is `.paeoniaSurfaceSecondary` with a 2 pt underline in `.paeoniaTextTertiary`. A filled slot is `.paeoniaSurfacePrimary` with the letter in `PaeoniaTypography.title`. A slot a hint filled has a `strokeEmphasis` outline in `.paeoniaAccentPrimary` and takes no taps. Hit areas run the full 48 pt height and reach into the gaps.
5. Tile grid, 6 columns and 2 or 3 rows, tile = (width minus 5 gaps of `space8`) / 6, capped at 56 pt, square, `radius12`, `.paeoniaSurfacePrimary`, letter in `PaeoniaTypography.title`. A used tile becomes an empty `.paeoniaSurfaceSecondary` cell, so the grid never reflows.
6. Pinned bottom: the grid and slots sit here, in thumb reach, and below them two quiet buttons side by side (`PaeoniaQuietButtonStyle`, 44 pt): "Show a letter" and "Show me". At accessibility text sizes they stack.

Interactions.
- Replay plays at the drawn pace from the first moment the screen shows the drawing. Press and hold anywhere on the replay for 4x (`GameReplayClock.fastForwardRate`). Release returns to 1x. While held, a `forward.fill` glyph shows at the bottom trailing corner of the canvas in `.paeoniaAccentPrimary`, and `selection()` fires once at press. Holding must not block the tiles, which are outside the replay.
- Discovery. On the first replay a player ever watches, a "Hold to speed up" capsule shows over the bottom of the canvas for 3 seconds, then fades. A local flag stops it showing again. After that only the glyph shows during a hold.
- Guessing while it plays is allowed and expected. Tapping a tile moves it into the first empty slot (a 0.16 s spring flight, `matchedGeometryEffect`) with `selection()`. Reduce Motion: the tile swaps with a `motionFast` cross-fade.
- Tapping a filled slot sends its tile back to its own cell, with `selection()`. Later tiles stay where they are, as `DrawAndGuessSlots.remove(at:)` does.
- A full, wrong word. The slots shake sideways 8 pt, three swings in `motionSlow`, and their outline turns `.paeoniaWarning` for 0.4 s. `gameWrongGuess()` fires. Then the tiles fly back, last letter first, 30 ms apart. Reduce Motion: no shake. The outline holds in `.paeoniaWarning` for 0.6 s and the tiles cross-fade back. The attempt goes to Convex without any wait.
- A full, correct word goes to the reveal (phase 5).
- Show me. A centered alert. The default action does not use the destructive role, because nothing is lost.
- Show a letter. Each tap places a random letter of the answer in its slot with `selection()`. It never picks a space, a hinted letter, or a letter the player already has right. The pick is seeded by the round and the hint count (`DrawAndGuessSlots.nextHintIndex(seed:)`), so it is the same on every run. A tile that sits in that slot goes back to the grid first, and the hint uses a tile with that letter from the grid. When every tile with that letter is in a slot, the hint takes one from a slot where it is wrong, never one the player has right. A hinted slot is locked: tapping it does nothing, clearing the slots and a wrong word leave it, and VoiceOver reads it as a hint. The button is disabled once the hints show all letters but one. In "Against each other", the first hint of a round asks first with a centered alert ("Show a letter?", "You won't get the speed bonus or the first try bonus this round."). "Together" has no bonuses, so it has no alert. The default action is "Show a letter" and the cancel action is "Keep guessing". The hinted slots survive leaving the screen and relaunching, and the next visit shows no alert again. The drawer sees the hinted letters fill in like any other letter, without a mark.
- A guess typed while offline is checked on the phone, so feedback is instant. See the reveal for what a queued win shows.

The speed timer. Only "Against each other" gets one, because only that style has a bonus. It is not a countdown number. The trailing slot of the live row shows "Speed bonus +2" in `.paeoniaInkGold` (`bolt.fill`) for the first 15 seconds, then "Speed bonus +1" until 30 seconds. A 3 pt line under the replay drains from full to empty over 30 seconds in the same gold, with a small notch above the line at the 15 second point. The line reaches the notch when the label drops from +2 to +1, and the notch goes away then. When the 30 seconds are over, the label and the line fade (`motionSlow`) with no sound and no haptic, and nothing in the screen turns red or pushes. The 30 seconds count from the server's `guesser_first_seen_at`, so reopening the app resumes the right remaining time. A live watcher's first look is the first stroke of the drawer's that reaches their phone, so the line drains while the partner draws and does not restart when they tap Done. Before that first stroke the label shows "+2" and the line stays full. Under Reduce Motion the line and the notch are replaced by the label alone, which still steps from +2 to +1 and disappears at 30 seconds. After the first hint the label and the line are gone, because any hint takes the bonus away. The tier on screen when the correct guess is made (2, 1 or 0) goes to the server as `p_speed_bonus`. "Together" has no timer and never mentions speed.

| Key | English | Norwegian |
|---|---|---|
| `guess.drawnBy` | [Name] drew this for you | [Name] tegnet dette til deg |
| `guess.watchingYou` | [Name] is watching you guess | [Name] ser at du gjetter |
| `guess.speedBonus` | Speed bonus +%lld (2 for 15 seconds, then 1) | Fartsbonus +%lld |
| `guess.speedBonusFast.a11y` | Guess within 15 seconds for 2 extra points. | Gjett innen 15 sekunder for to ekstra poeng. |
| `guess.speedBonus.a11y` | Guess within 30 seconds for 1 extra point. | Gjett innen 30 sekunder for ett ekstra poeng. |
| `guess.holdHint` | Hold to speed up | Hold for å spole fremover |
| `guess.wordLanguage.english` | The word is in English | Ordet er på engelsk |
| `guess.wordLanguage.norwegian` | The word is in Norwegian | Ordet er på norsk |
| `guess.showMe` | Show me | Vis meg |
| `guess.showMe.title` | Show the answer? | Vise svaret? |
| `guess.showMe.message` | This round won't give any points. You'll still see the word and the drawing. | Denne runden gir ingen poeng. Du får fortsatt se ordet og tegningen. |
| `guess.showMe.cancel` | Keep guessing | Fortsett å gjette |
| `hint` | Show a letter | Vis en bokstav |
| `hint.confirm.title` | Show a letter? | Vise en bokstav? |
| `hint.confirm.message` | You won't get the speed bonus or the first try bonus this round. | Du får ikke fartsbonusen eller bonusen for første forsøk denne runden. |
| `guess.hintPlaced` | Hint. %1$@ in letter %2$lld | Hint. %1$@ i bokstav %2$lld |
| `slotHint` | Letter %1$lld, %2$@, hint | Bokstav %1$lld, %2$@, hint |
| `hints` | %lld hint / %lld hints | %lld hint |

VoiceOver. The game is visual, and the drawing has no text version before the reveal. So the replay is one element, "Drawing by [Name], playing", with the hint "It can't be described before you guess." / "Den kan ikke beskrives før du har gjettet." Custom actions on it are "Play faster" (toggles 4x) and "Show the whole drawing" (calls the clock's `finish`). The answer is one group, "Answer, two words, 3 and 5 letters", containing one element per letter slot ("Letter 2, A. Double tap to remove" or "Letter 2, empty"). Tiles come next in row order, and a rotor named "Empty letters" jumps between empty slots. Placing a tile announces "A in letter 2", and a hint announces "Hint. A in letter 2". A hinted slot reads "Letter 2, A, hint" and has no remove hint. A wrong word announces "Not it. Try again."

Dynamic Type. Tile and slot letters cap at `.accessibility1` because the grid keeps 6 columns, and tiles grow with the size up to 64 pt. The screen scrolls above the pinned tiles. The live row wraps to two lines, and the speed label moves under it.

Empty and error states. If the drawing file cannot load, show `PaeoniaEmptyStateView` "Can't load the drawing" / "Kan ikke laste tegningen", "Check your connection and try again." / "Sjekk nettverket og prøv igjen.", with `common.tryAgain`. When the relay drops, nothing changes on screen except the live row, which falls back to the async wording. A reconnect resumes silently.

### 5. Reveal (guesser)

Purpose. The best 2 seconds of the game. A correct word should feel like the other person lighting up.

Beats, in seconds after the last tile lands.

| Time | What happens |
|---|---|
| 0.00 | Input locks. The replay clock calls `finish`, and the strokes still missing fade in over `motionFast`. `selection()` fires. |
| 0.10 to 0.60 | The slots light up left to right. Each letter scales 1 to 1.18 to 1 and its fill turns `.paeoniaSuccess`. Stagger is 45 ms, compressed so a long phrase still ends by 0.60. `streakTick` rises with each letter. |
| 0.70 | `answerRevealed()`. A petal bloom bursts from the slot row, about 40 particles in `.paeoniaAccentPrimary`, `.paeoniaAccentSecondary` and `.paeoniaMemory`, over 0.9 s, drawn in a `TimelineView` + `Canvas` seeded by the round id, modeled on `PairingCelebrationParticleField` and lighter than it. A radial glow behind the canvas (`PaeoniaGlowBackground` style) rises from 0.16 to 0.30 and back. |
| 0.70 to 1.10 | The tile grid collapses (`meaningfulMoment`). The canvas eases to 80% width. |
| 1.10 | Title "Got it!" and the solve time fade up (`celebrationReveal`). The primary button appears. |
| 1.40 | Two avatars (44 pt) with a `PaeoniaHeartDivider` between them appear, and the score panel starts (below). |
| 1.90 | "Speed bonus +2" (or +1) lands in gold with `streakContinued()`, if the guess earned it. |
| 2.20 | "First try +1" lands with `streakContinued()`, if the guess earned it. It has its own beat after the speed bonus. |
| 2.50 | The reaction row rises in (`cardReveal`). |

Everything is tappable from 1.10 s. A tap on the screen jumps to the settled state, as `PairingCelebrationTimeline.skip` does, without repeating haptics. Build a `DrawAndGuessRevealTimeline` like that timeline, with a run id, an injected schedule and injected haptics, so tests can run it fast. Reduce Motion: no ripple, bloom, glow or count-up. The settled state shows at once, with only `answerRevealed()`.

Drawing still loading. When the final drawing is not on the phone yet, such as on a reveal opened after a relaunch, the square keeps its size and shows a small `ProgressView` in `.paeoniaAccentPrimary`, centered, with the VoiceOver label "Loading the drawing" / "Laster inn tegningen". The spinner waits 0.3 s before it shows, so a fast download never flashes it. The drawing then fades in (`meaningfulMoment`, opacity only, so Reduce Motion gets the same). A failed download shows "Can't load the drawing" with Try again in the same square. The drawer's result uses the same view (`DrawAndGuessRevealDrawing`). The Debug scenario `draw-reveal-loading` shows it.

Solve time. "You solved it in 24 seconds" (`Duration.UnitsFormatStyle`, seconds and minutes). It uses the server's `solve_ms`. Past 10 minutes the line is dropped, because the time then says more about the day than the guess. When the server confirms `personal_best`, a second line in `.paeoniaAccentPrimary` says "Your fastest solve yet". The phone never guesses this one, so it shows only after the server answered.

Score panel.
- Together. The couple total counts up from the old to the new total in 0.6 s, big, in `PaeoniaTypography.countdownNumber`, with "points together" under it and "+2" in `.paeoniaAccentPrimary` beside it. Both avatars sit above. One `streakTick` per point added.
- Against each other. The two avatars are the two columns, each with a total below. A "+3" pops on mine and a "+2" on theirs, and the totals count up. Under my column, if I am the guesser, up to three quiet lines: "The word +2", "Speed bonus +2" (gold, only when above 0) and "First try +1" (only when earned). Under theirs, "For the drawing +2". No winner banner and no comparison text. The numbers do that.
- Queued win (offline). The panel counts the word's points plus the bonuses the phone promised: the speed bonus tier the screen showed, and the first-try bonus when no wrong word came before and no hint was used. It adds the line "Your score updates when you're online." when the move is held on the phone. The server takes the speed bonus as sent, works out the first-try bonus itself, and its numbers replace the phone's when they arrive. A line that arrives late shows without a second celebration.

Reactions. Under the panel (and under the "Not this time" text on a missed round), the guesser sees a caption "Tell [Name] what you think" and three buttons: love (`heart.fill`, "Love"), laugh (`face.smiling`, "Haha") and wow (`hands.clap.fill`, "Wow"). The symbols are `.paeoniaAccentPrimary`. Tapping a button selects it (accent outline, `selection()`). Tapping the selected one clears it. The choice shows on the phone at once and goes out when the phone is online. The last choice wins. The drawer's phone shows it on their result screen (phase 6). The row arrives at 2.50 s, or at once after a tap on the screen. At accessibility text sizes the buttons stack. VoiceOver reads each as a button with the `.isSelected` trait on the chosen one.

Star. Once the result's buttons appear, a star button shows in the trailing toolbar (`star`, `star.fill` when starred, `.paeoniaAccentPrimary`). It toggles my private star with `selection()`, and its label reads "Star" or "Starred" with the selected trait while starred. It sits next to the "Our drawings" button, which every Draw & Guess screen has. The first time a person stars a drawing, a quiet banner says "Only you can see your stars." with a `star.fill` glyph, so a private star never looks like it tells the partner. It shows once per phone (`games.drawAndGuess.starHintShown`). The star works on a solved and a missed round. It uses the same `GameStars` object as "Our drawings".

Hand-off. The primary button is "Your turn to draw", pinned at the bottom and always the primary action. It crosses to phase 1 over `pairedScreenTransition` and keeps no state. There is no forced answer, no second confirm, and no auto-advance, because the player may want to look at the drawing a bit longer. In a live pair the drawer's phone is already on its own result screen, so the two phones move on independently.

| Key | English | Norwegian |
|---|---|---|
| `reveal.title` | Got it! | Riktig! |
| `reveal.solveTime` | You solved it in %@ | Du løste den på %@ |
| `reveal.pointsTogether` | points together | poeng sammen |
| `reveal.you` | You | Du |
| `reveal.line.word` / `reveal.line.speed` / `reveal.line.firstTry` / `reveal.line.drawing` | The word +%lld / Speed bonus +%lld / First try +%lld / For the drawing +%lld | Ordet +%lld / Fartsbonus +%lld / Første forsøk +%lld / For tegningen +%lld |
| `reveal.personalBest` | Your fastest solve yet | Din raskeste løsning så langt |
| `reveal.offlineScore` | Your score updates when you're online. | Poengene oppdateres når du er på nett. |
| `reaction.prompt` | Tell [Name] what you think | Si til [Name] hva du synes |
| `reaction.love` / `reaction.laugh` / `reaction.wow` | Love / Haha / Wow | Elsker / Haha / Wow |
| `handoff.draw` | Your turn to draw | Din tur til å tegne |

VoiceOver. On the word landing, post one announcement, "Correct. It was CAT. 2 points." Then focus moves to the title. The bloom and glow are hidden. The count-up exposes only the final value. Dynamic Type. The avatar columns stack vertically at accessibility sizes, and the screen scrolls with the button pinned.

### 6. The drawer's result

Purpose. The drawer's payoff. It should feel like watching the other person think.

Right after Done, if the round is not solved, the drawer sees the same square (80%, static, showing the full drawing) with:
1. Status line. "Sent to [Name]". Under it, one of three lines. "[Name] is looking at it" while the partner is on the guess screen (role `watching`, with the avatar ring and the same joined pulse as phase 2). "[Name] has seen it" once the server has `guesser_first_seen_at` for the round and the partner has left the guess screen. "[Name] hasn't seen it yet" when the guesser has never seen the drawing, also while the partner is somewhere else in the game. Whether the partner has the drawing is separate from whether it has left this phone. While it still waits to leave, the line says "hasn't seen it yet" unless the server has `guesser_first_seen_at` or the partner watches live, which means they asked for and got this phone's whole canvas in the live room since either phone last joined (`DrawAndGuessSentStatus`).
2. The partner's letters, only while the partner is on the guess screen and their phone has sent it. "[Name] is guessing" in `caption`, then their answer slots, read only, filling and emptying as they place tiles. A wrong word gets the same shake and outline as on their screen. While they replay the drawing, the square plays it at the point their replay is, at their speed. A partner who watched live sees the whole drawing, and so does the square. When the partner leaves the guess screen, the letters go and the square shows the whole drawing again.
3. Guess area. With no guesses, "No guesses yet. We'll tell you when [Name] guesses it." As guesses arrive, each wrong word is a chip (`.paeoniaSurfacePrimary`, `caption` semibold, wrapping, in order), appearing with `cardReveal` and `partnerDrawingReceived()`. The row reads "[Name] tried" in front.
4. Pinned bottom: nothing, until the round ends. The drawer may leave with back.

Async open. When the drawer opens the game after a round ended, the chips play back in order, 0.5 s apart, compressed so the sequence takes 3 seconds at most, each with a soft `partnerDrawingReceived()`. Tapping the screen finishes the sequence. This is the screen the doc calls the drawer's payoff, so it never appears all at once the first time. Reduce Motion: all chips at once.

Solved. The correct word joins the chip row last, in `.paeoniaSuccess`, with the same letter ripple, `answerRevealed()` and a half-size bloom as phase 5. Title "[Name] got it!". Under it one sentence, "[Name] got it in 24 seconds, on the first try." or "[Name] got it in 24 seconds and 3 tries.", without the time when it is missing or past 10 minutes. When the guesser used hints, the sentence names them instead of the tries: "[Name] got it in 24 seconds with 2 hints." When the server says it was the guesser's fastest solve so far, a second line in `.paeoniaAccentPrimary` says "[Name]'s fastest solve yet". The panel for points is phase 5's, with my column showing "For the drawing +2". Under the panel, the guesser's reaction shows when there is one, as a capsule with its symbol in `.paeoniaAccentPrimary` and a short line: "[Name] loved it", "[Name] laughed" or "[Name] said wow". If the reaction is already there when the screen opens, it comes in with the result at 2.50 s. If it arrives while the drawer looks at the result, it rises in (`cardReveal` with a small scale, opacity only under Reduce Motion) and fires `partnerDrawingReceived()`. VoiceOver reads the capsule as one line. The primary button "Continue" (to phase 3) follows. If the solve happens while the drawer is still drawing, the sequence is the same, and the sent drawing is the final frame.

Star. The drawer's result has the same toolbar star as phase 5. It shows only once the round has ended, never while the round is still open after Done.

Unseen results. The drawer may not open the game until the partner has already solved and drawn back, so the current round is then a new one. The game shows the latest finished round's result first when this person has not moved past it, with "Continue" leading to the new round. A result counts as seen when the server has the drawer's `drawer_result_seen_at` for it, or a "result seen" mark for it waits on this phone. A fresh install and a second phone therefore never show an old result again.

Missed, from the drawer's side. Title "[Name] asked for the answer", then the chips of the tries, then "No points this round." The tone stays flat and kind, with no "gave up" wording. A reaction to a missed round shows the same way as on a solved one.

| Key | English | Norwegian |
|---|---|---|
| `result.sent` | Sent to [Name] | Sendt til [Name] |
| `result.notSeen` | [Name] hasn't seen it yet | [Name] har ikke sett den ennå |
| `result.looking` | [Name] is looking at it | [Name] ser på den nå |
| `result.guessing` | [Name] is guessing | [Name] gjetter |
| `result.seen` | [Name] has seen it | [Name] har sett den |
| `result.tried` | [Name] tried | [Name] prøvde |
| `result.noTries` | No guesses yet. We'll tell you when [Name] guesses it. | Ingen gjetninger ennå. Vi sier fra når [Name] gjetter riktig. |
| `result.gotIt` | [Name] got it! | [Name] gjettet riktig! |
| `result.solvedTimedFirstTry` / `result.solvedTimedTries` | [Name] got it in %@, on the first try. / [Name] got it in %@ and %lld tries. | [Name] klarte det på %@, på første forsøk. / [Name] klarte det på %@ og %lld forsøk. |
| `result.solvedFirstTry` / `result.solvedTries` | [Name] got it on the first try. / [Name] got it in %lld tries. | [Name] klarte det på første forsøk. / [Name] klarte det på %lld forsøk. |
| `result.solvedTimedHints` / `result.solvedHints` | [Name] got it in %@ with 2 hints. / [Name] got it with 2 hints. | [Name] klarte det på %@ med 2 hint. / [Name] klarte det med 2 hint. |
| `result.personalBest` | [Name]'s fastest solve yet | [Name] sin raskeste løsning så langt |
| `result.reaction.love` / `.laugh` / `.wow` | [Name] loved it / [Name] laughed / [Name] said wow | [Name] elsket den / [Name] lo / [Name] sa wow |
| `result.missed` | [Name] asked for the answer | [Name] ba om å få se svaret |
| `result.noPoints` | No points this round. | Ingen poeng denne runden. |
| `handoff.continue` | Continue | Fortsett |
| `handoff.watch` | Watch [Name] draw | Se [Name] tegne |
| `handoff.seeDrawing` | See what [Name] drew | Se hva [Name] tegnet |

Watch the partner draw. When this phone is on the drawer's result and the server's current round is a newer round in state `drawing` with the partner as drawer, the bottom button changes from "Continue" to "Watch [Name] draw", with a pulsing dot in front (still under Reduce Motion). It gives one `partnerDrawingReceived()` haptic and a VoiceOver announcement ("[Name] is drawing for you") when it appears. Tapping it does what Continue does, which also marks the result as seen, and lands in the live watching phase when the partner is drawing live. When the partner has already sent that round (state `guessing`), the button reads "See what [Name] drew" instead, with the same haptic and a VoiceOver announcement of the button text, and no pulsing dot because nothing is happening live. The view model exposes both as `partnerNextRound`.

VoiceOver reads the guesses as one sentence, "[Name] tried CAT, then HAT, then DOG", built with `ListFormatStyle`-style joining, and the chips are hidden from the rotor.

### 7. Missed round (guesser)

Purpose. A soft landing. No guilt, no lost points.

After the Show me alert is confirmed, the slots fill with the answer left to right (still `.paeoniaTextPrimary` on `.paeoniaSurfacePrimary`, not green) over 0.5 s, with a single `partnerDrawingReceived()` and no bloom. The replay finishes, the canvas eases to 80%, and the panel shows:
- Title "Not this time".
- Line "No points this round. Ready to draw one back?"
- The reaction row (phase 5), shown at 1.10 s. A missed round can still get a reaction.
- Primary "Your turn to draw".

There is no score panel, in both styles, because nothing changed. The play style needs no other handling.

| Key | English | Norwegian |
|---|---|---|
| `missed.title` | Not this time | Ikke denne gangen |
| `missed.line` | No points this round. Ready to draw one back? | Ingen poeng denne runden. Klar for å tegne en tilbake? |

### 8. Our drawings

Purpose. Find a drawing again. Every finished round that holds a drawing is here, solved or missed, newest first. Draw & Guess no longer saves to Memories, so this is where drawings live.

Entry points.
- A `square.grid.2x2` button in the trailing toolbar of `DrawAndGuessScreen`, labelled "Our drawings".
- A quiet link on the Games hub's Draw & Guess card, under the main button. It shows once the cached game state holds a finished round with a drawing. The card on the Us tab has no link.

Look. The screen follows the shell above: `.paeoniaBackgroundSecondary`, dark toolbar, inline title, no cards. Only the drawing cells get a fill (`.paeoniaSurfaceSecondary`, `radius16`). Icons are plum and text is white. Nothing is red, because nothing here is destructive.

Layout, top to bottom, all in one scroll view.
1. Records. The heading "Records" (`sectionTitle`), a header row with my avatar and "You" next to the partner's avatar and name, then three rows. Each row has a caption label and one value per partner in `PaeoniaTypography.title`. The rows are solves on the first try, the average solve time, and the fastest solve (time, with the word under it in `caption`). A partner with no value for a row reads "Not yet" in `.paeoniaTextTertiary`. Times use `Duration.UnitsFormatStyle` in abbreviated form ("24 sec"). The section shows in both play styles. At accessibility text sizes the header row goes away, the columns stack, and each value carries its owner's name. Each row is one VoiceOver element, "Fastest solve, You: 9 sec, Cat. Robin: 12 sec, Umbrella."
2. A segmented picker, "All" and "Starred". It shows my stars only.
3. The grid. `LazyVGrid` with adaptive columns of at least 160 pt, which gives 2 columns on a phone and more on an iPad. A cell has a square picture on `.paeoniaBackgroundPrimary` (`radius12`), the word (`bodyEmphasis`, up to two lines), and "by Robin · Oct 12" or "by you · Oct 12" in `caption`. A filled `star.fill` badge sits at the top trailing corner when I starred the drawing, and a small badge with the guesser's reaction sits at the bottom trailing corner. A missed round looks the same as a solved one.

Pictures. `GameDrawingThumbnails` renders a `PKDrawing` to a 240 pt square at 2x off the main actor and keeps the result in memory (an `NSCache` limited to 48 MB). The drawing comes from the phone when it has it, and otherwise through `GameDrawingTransferring`, the path the game already uses. A downloaded drawing stays on the phone with the partner's other drawings, so the screen shows what it showed before while offline. A privacy purge empties the memory cache together with the files.

Loading and paging.
- The screen shows the cached first page of "All" and the cached records at once, then reads the server. The cache holds the first page and the records (`GamesHistoryCache`). A failed read keeps what is on screen and says nothing.
- A page is 30 rounds. The cell near the end of the list (the last 6) loads the next page with `next_before_round_number`. A failed page shows "We couldn't load older drawings." and Try again.
- Returning from a drawing and pulling down both read the first page again. A list that was scrolled past its first page keeps its older rounds.
- The "Starred" list is built from the starred pages and the loaded "All" rounds, filtered by what the star store says. A drawing leaves the list the moment I unstar it, and joins it the moment I star it from "All". Offline, it falls back to the cached "All" rounds.

Empty states, with `PaeoniaEmptyStateView`.
- No drawings yet (the first round has not finished): `square.grid.2x2`, "No drawings yet".
- "Starred" with no stars: `star`, "No starred drawings".
- Offline with nothing cached: the usual `wifi.slash` state ("You're offline", `choose.offline.title`) with Try again.

The detail screen. A cell pushes it. It shows, top to bottom, the square drawing, a "Play again" button with a small hint, the word (`heroTitle`), "Drawn by Robin · Oct 12", one result line, the reaction if there is one, and a caption "Only you can see your stars."
- The drawing plays back once at the drawn pace through `GameReplayTimeline` and `GameReplayClock`, on the same `GameReplaySurface` the guess screen uses. Holding anywhere on it plays at 4x, with a `forward.fill` glyph and a `selection()` haptic. "Play again" starts it over. With Reduce Motion the finished drawing shows at once and "Play again" plays it on request.
- The result line reuses the drawer's result copy with the guesser's name ("You" when I guessed): "Robin got it in 24 seconds, on the first try.", "Robin got it in 24 seconds and 3 tries.", or "Robin asked for the answer". The time is left out past 10 minutes.
- The toolbar star button (`star` and `star.fill`) toggles my star with `selection()`. Its label reads "Star" or "Starred", and it has the selected trait while starred.
- A drawing that can't load shows the "Can't load the drawing" state with Try again, in the square.

Stars. `GameStars` is the one place that knows my stars. The star of a round shows at once, is kept on the phone as a queued `setGameRoundStar` write, and is sent when the phone is online. The last write of a round wins, and the server sets the value it is given, so a retry changes nothing. The value shown is the server's value with the queued writes on top. The server's value comes from the game state for its rounds (`starred_by_me`) and from the cached history pages and star writes for older ones. A star write's answer also updates the cached game state. It keys by round id, so a round that just ended and is not in the history list yet can be starred. The result screens use the same object through `DrawAndGuessViewModel.stars`: `stars.isStarred(roundID)` and `stars.toggle(roundID:)` or `stars.setStarred(_:roundID:)`.

VoiceOver. A cell is one element, "Cat, drawn by Robin, starred" or "Cat, drawn by you". The badges are hidden. The drawing on the detail screen is one element, "Drawing of Cat, drawn by Robin", with the actions "Play again" and "Show the whole drawing". Everything scales with Dynamic Type.

| Key | English | Norwegian |
|---|---|---|
| `history.title` | Our drawings | Tegningene våre |
| `history.records.title` | Records | Rekorder |
| `history.records.firstTry` | Solved on the first try | Løst på første forsøk |
| `history.records.average` | Average time | Gjennomsnittstid |
| `history.records.fastest` | Fastest solve | Raskeste løsning |
| `history.records.none` | Not yet | Ikke ennå |
| `history.records.spoken` | %1$@: %2$@ | %1$@: %2$@ |
| `history.records.fastestSpoken` | %1$@, %2$@ | %1$@, %2$@ |
| `history.filter.all` | All | Alle |
| `history.filter.starred` | Starred | Stjernemerket |
| `history.filter.label` | Show | Vis |
| `history.who.you` | you | deg |
| `history.cell.caption` | by %1$@ · %2$@ | av %1$@ · %2$@ |
| `history.cell.a11y` | %1$@, drawn by %2$@ | %1$@, tegnet av %2$@ |
| `history.cell.starred.a11y` | %1$@, drawn by %2$@, starred | %1$@, tegnet av %2$@, stjernemerket |
| `history.empty.title` | No drawings yet | Ingen tegninger ennå |
| `history.empty.message` | Your drawings will show up here after your first round. | Tegningene deres dukker opp her etter første runde. |
| `history.emptyStarred.title` | No starred drawings | Ingen stjernemerkede tegninger |
| `history.emptyStarred.message` | Tap the star on a drawing you like, and it shows up here. | Trykk på stjernen på en tegning du liker, så dukker den opp her. |
| `history.offline.message` | Connect to the internet to see your drawings. | Koble til internett for å se tegningene deres. |
| `history.loadMore.failed` | We couldn't load older drawings. | Vi kunne ikke laste eldre tegninger. |
| `history.detail.drawnBy` | Drawn by %1$@ · %2$@ | Tegnet av %1$@ · %2$@ |
| `history.detail.replay` | Play again | Spill av igjen |
| `history.detail.holdHint` | Hold the drawing to speed it up. | Hold på tegningen for å spole fremover. |
| `history.detail.drawing.a11y` | Drawing of %1$@, drawn by %2$@ | Tegning av %1$@, tegnet av %2$@ |
| `games.star.button` | Star | Stjernemerk |
| `games.star.buttonStarred` | Starred | Stjernemerket |
| `games.star.privacy` | Only you can see your stars. | Bare du ser stjernene dine. |

The detail screen also reuses `result.solvedTimedFirstTry`, `result.solvedTimedTries`, `result.solvedFirstTry`, `result.solvedTries`, `result.missed`, `reveal.you`, `games.drawing.loading`, `guess.replay.skip`, `notice.drawingUnavailable` and `choose.offline.title`.

### Wide layouts and Dynamic Type

- Wide means 700 pt or more wide and wider than tall, measured with `onGeometryChange`, not the device idiom. It applies to iPad landscape, iPad Split View, and iPhone landscape.
- Wide layout. Two columns. Left, the square (up to 640 pt), centered vertically. Right, a column up to 420 pt with everything else of the phase, and the pinned bottom cluster at the bottom of that column. On iPhone landscape the right column scrolls.
- Narrow layouts (including iPad portrait) use one column inside `.paeoniaReadableWidth()`. The square is capped at 640 pt, like the widget canvas, so strokes keep their weight.
- Choose, waiting and missed are text-led and use `.paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)` in every size.
- At accessibility Dynamic Type sizes every phase becomes a scroll view with the primary button pinned. The canvas keeps its square. Pips, ring and avatars in the reveal rearrange, never disappear.

## iOS

Code map in `docs/implementation-map.md`. Decisions the sections above leave open:

- **Local first.** Picking a word, sending the drawing, a guess, "Show me", a reaction and moving past a result go into the pending operations before anything is sent. The screen applies those queued moves on top of the server's state, so a correct guess shows the reveal at once, a reaction shows the moment it is tapped, and a drawing sent offline shows "Saved on this phone. We'll send it when you're online." The server's points, bonuses and solve time replace the local values when they arrive. The speed bonus tier, the solve time and the hint count are the ones the phone sent with the guess. The first-try bonus on a queued win is the phone's prediction: no earlier wrong word in the round and no hint. Creating the couple's game and changing settings need a connection.
- **Order.** A drawing waits for the word pick of its round, and a pick waits for this person's earlier guesses and give up. A guess or give up waits for the earlier guesses of the same round, so a wrong guess is never refused after the correct one ended the round. A reaction and a result seen mark wait for this person's guesses and give up of their round, because the server takes them only on a finished round, and a reaction also waits for an earlier reaction of the same round, so the last one made is the last one sent. A refused word or drawing stops retrying and shows a notice. The server can also answer a move with an error the phone has no rule for, such as a bare "Server Error". After the server refuses that move three times, the phone drops it, keeps the round open, and shows "Your move wasn't sent". Only those refusals count, kept per move in the Games cache. Offline failures, sign-in problems, waiting behind an earlier move, and "active entitled game access is required" never count and never drop a move. A correct guess that is dropped empties the answer slots, so the person can guess again. A reaction and a result seen mark are not counted this way. Only a refusal a retry can never fix drops them, without a notice, and any other error keeps them in the queue. The server deletes an upload that nothing used within a week. When a phone stayed offline that long after uploading a drawing, the phone queues the drawing again with a new upload. When the server takes a move, the phone reads the server's state before the move leaves the queue, so the screen never falls back to the state from before the move while the live feed catches up. When that read fails, the move stays in the queue, and the next try replays it and reads again. That try comes after 2 seconds, then 4, 8 and at most 15, instead of the usual minute, so "Saved on this phone" goes away within seconds once the network works. Offline, the replay itself fails and waits the usual time. The server answers a replay from its record of the operation. The Games cache never takes a server state that is behind the one it holds, such as a live feed update sent before a move the phone already read back. It tells by what the server only moves forward: the game's version, a round's drawing, first look and result seen times, its attempts, and whether it ended. A one-shot read that is ahead of the kept state by the same measure is kept, even when a live update arrived while the read ran. While a move waits and the last try failed for a reason other than being offline, the waiting screen says "We couldn't send your move yet" and has a "Try again" button. Deploy the backend before shipping an app build that sends new fields, because an old server answers them with that bare error. A refused drawing goes back on the canvas. When the word is refused, the drawing already made for it is not sent. It is kept and appears on the canvas of the drawer's next round, after they pick another word.
- **One drawing size.** The drawer scales the drawing to a 320 point square before sending, and the guesser scales it to their own canvas. The live room uses the same size.
- **Result seen.** A finished round's result counts as seen for this person when the round's `drawer_result_seen_at` (or `guesser_result_seen_at`, for the guesser) is set on the server, or when a "result seen" mark for it waits in the pending operations on this phone. The phone keeps no list of seen rounds of its own. "Continue" on the reveal queues `mark_round_result_seen` and the screen moves on at once, without waiting for the network. The queued mark waits for this person's guess or give up of that round. The handler reads the server's state before the mark leaves the queue, so the result never comes back in between. A fresh install or a second phone reads the seen time from the server and does not show an old result again. The guesser draws next, so "Your turn to draw" shows when the guesser leaves the reveal.
- **Reactions.** Tapping a reaction queues `set_round_reaction` with the choice, or with nothing when the tap clears it. The round on screen carries the last queued reaction, so the row updates at once. The server keeps the last write, so a retry is safe. The drawer gets the reaction through the live feed. A reaction can change in both directions, so the cache does not use it to judge how old a state is.
- **Hints.** The view model's `showLetter()` places the next hint on a copy of the slots and assigns it once. Hinted slots are marked in `DrawAndGuessSlots` (`isHint`), so `place`, `remove` and `clear` skip them. The hinted slot indexes of a round are kept in the Games cache (`GamesLocalDocument.hints`, the latest 20 rounds) and in the view model. The tiles of a round are built together with the restored hints, so leaving the screen or relaunching shows the same letters. The hint count goes to the server as `p_hints_used` with the correct guess. The first hint ends the speed bonus on screen at once.
- **Built screens.** The screens follow the design above with these differences. The answer slots sit under the square in the scrolling content (pinned with the tiles only at accessibility text sizes), so the reveal does not move them. The "Missed" result uses the same layout as the solved reveal instead of the focused width. When the partner solves the round while the drawer is still drawing, the drawer's screen cross-fades to the result instead of folding the tools away. The Draw & Guess canvas shares the widget tool controls through `WidgetDrawingToolControlling` instead of the widget view model.
- **Live to async.** A guesser who watched the drawing live keeps the live canvas when the drawer taps Done, until the drawer leaves the live room. The live canvas counts only when a snapshot of the drawer's whole canvas arrived since either phone last joined the room, because a canvas from before a lost connection can miss strokes. Otherwise the sent drawing is downloaded and replayed. The guesser asks for that snapshot whenever a socket joins and whenever the partner starts drawing. A guesser who did not watch gets the replay. A guesser who solves the round live keeps the live canvas as it was at that moment, on the phone in the Games drawings, so a relaunch before the drawer's drawing arrives still shows it on the reveal. The phone keeps one such snapshot per person, deletes it once the drawer's drawing is downloaded, and clears it with the partner's downloaded drawings on sign-out and in a privacy purge. The speed bonus clock starts when the guesser first sees the drawing, live or replayed. Live, that is the first stroke on the canvas, not an empty canvas. A drawing that finishes downloading while the app is in the background starts its replay and tells the server it was seen only when the screen is back.
- **Our drawings.** The history reads `get_draw_and_guess_history` and `get_draw_and_guess_records` through `GamesGateway` and keeps the first page, the records and the person's stars in the Games cache (`GamesLocalDocument.drawings`). `DrawAndGuessHistoryViewModel` owns the lists and the filters, `DrawAndGuessHistoryDetailViewModel` owns one replay, and `GameStars` owns the stars. A star is a queued `setGameRoundStar` write. It waits for this person's guess or give up of the round and for an earlier star of the same round, then calls `set_round_star`. The handler saves the server's answer in the cache before the write leaves the queue, so the star never flips back in between. A refusal that a retry can't fix drops the write without a notice, and the star then shows the server's value.
- **Role.** The open screen announces the role from the Live section through the relay `hello` and changes it with the phase (`syncLiveRole`).
- **Presence.** The open screen sends `set_game_presence` true on appear and every 30 seconds, and false on disappear and in the background. The hub and the game treat a heartbeat under 60 seconds old as "here", and check again every 15 seconds.
- **Setup.** The couple's game language is preselected from the first supported language of the phone, because the app cannot see the partner's language. The partner who did not choose sees "Here's what [Name] picked" once, tracked on the phone.
- **Drafts.** The drawer's unsent drawing is saved on the phone as they draw, so closing the app loses nothing. When the round ends while the drawer is away from the canvas, the next time the game opens it sends the saved draft. When the partner guesses during a stroke, the drawing is sent after that stroke ends. A drawing queued before a restart goes back on the canvas if the server refuses it.

## Open questions

- Accessibility. Tiles must work with VoiceOver. The drawing has no text version until the reveal.
