# Draw & Guess

Design for the first game. The backend, the iOS foundation and the game screens are built. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Draw & Guess.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

- Live reactions are !, ?, laughter and a heart. The four buttons sit below the partner status, above the canvas, on both the drawing and guessing screens and the drawer's screen while awaiting a guess. A tap sends one reaction through the live room for the current round. Both phones show it rising from its button, with a small random tilt and sideways drift, until it exits the screen's top edge. The overlay does not take touches. Reduce Motion keeps it still above the button and fades it away. The row appears only while both partners are in the live room on an unfinished round. Reactions expire after 2.8 seconds, are never replayed after reconnecting, and send no push. Finished-round emoji reactions remain separate.

- **Draw & Guess is the first game.**
- **Async and live both ship in the first version.** One partner draws, and the other watches the drawing play back stroke by stroke whenever they open the app. When both have the game open, the guesser watches the drawing happen live. Draw Something (2012) proved the async loop works on phones.
- **Supports both play styles.** The couple's play style decides the scoring. See "Scoring".
- **Words come in the couple's game language.** See `docs/games-plan.md`.
- **No streak of its own.** Turns count toward the couple's existing streak. See "Streak".

- **The speed bonus has tiers.** A correct guess within 15 seconds of first seeing the drawing earns 2 points, within 30 seconds earns 1, and later earns 0.
- **First-try bonus.** The guesser earns 1 point when the correct guess is the round's first attempt and no hint was used.
- **Hints.** The guesser can ask for letter hints. The phone decides which letters a hint shows, and the server only counts them. Any hint sets both bonuses to 0. Hints don't change the word points.
- **Reactions.** Either partner can put one emoji on a finished round, the guesser and the drawer. It works like a reaction on a story, a memory or a drawing (`docs/implementation-map.md`, "Reactions"). The partner gets one gentle push for a first reaction (decided on 2026-10-21; before that only the guesser could react, with love, laugh or wow, and nobody got a push).
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
2. **Reveal.** The word locks in, the rest of the drawing finishes at once, and the phone gives a success haptic. The screen says who got it, how long the guess took and how the points changed, and little else. The time sits in a small capsule under the headline (`DrawAndGuessSolveTime`), counts up from zero as it appears, and has a gold stopwatch when the guess earned the speed bonus. A missed round, or a time over 10 minutes, shows no capsule.
3. **Result.** Either partner can react, and either partner can star the round (see "History and stars").
4. **Draw back.** You pick a word and draw it for your partner.

The very first turn of a new game skips the guess and starts at "Draw back".

### Picking a word

The drawer chooses one of three words: easy, medium, or hard. Harder words score more points. The three choices are fixed when the turn begins, so reopening the game doesn't give new ones. A fourth choice is "Draw your own", where the drawer types any word or short phrase. That is how a couple uses inside jokes ("the dog at your mom's house"). A custom word holds 2 to 20 letters and at most three words separated by single spaces. Letters are A to Z, plus Æ, Ø and Å. A custom word scores like a medium word.

The server picks the three suggested words from the couple's game language, so the guesser can't see them ahead of time. A couple sees each word only once until the list runs out.

The round starts in Convex the moment the drawer picks a word, not when they finish. A partner who opens the game while the drawer is still drawing can start guessing right away.

### Drawing

- Use the existing PencilKit tools from `WidgetDrawing/Canvas`.
- No time limit while drawing.
- The drawer taps Done to send. Done sits right under the canvas, so a stroke that ends low can tap it by accident, and the phone asks "Send your drawing?" first. A correct live guess also ends the drawing (see "Live").

### Replay

- The replay shows the strokes in the final drawing in the order they were drawn. Erased strokes don't play back.
- The canvas keeps the pixel eraser (`PKEraserTool(.fixedWidthBitmap)`). PencilKit hides erased ink with `PKStroke.mask` and `maskedPathRanges`, and splits a stroke into pieces that share its path and `creationDate`. The replay plays only the visible part of each piece at its original time offsets, and every partial stroke keeps the mask, transform and ink, so erased ink never shows. Live sync sends masked strokes too, because the stroke signature includes the mask.
- Long pauses in the replay are shortened to about one second, so a drawer who stopped to think doesn't make the guesser wait.
- The guesser can hold the replay to fast-forward.

### Guessing

- Guessing uses tiles, not the keyboard. The screen shows one empty slot per letter, with gaps for spaces. Below the slots are the answer's letters mixed with decoy letters, about 12 tiles for a short word. The tiles are in alphabetical order, A to Z and then Æ, Ø and Å, so a letter is quick to find. A QWERTY order would not help, because the grid is 6 tiles wide and does not look like a keyboard.
- Decoys come from the game language, so a Norwegian word can show æ, ø and å tiles.
- When every slot is filled with a wrong word, the slots shake and the letters go back to the tiles.
- Guesses ignore case. Tiles show capital letters.
- Attempts are unlimited. A "Show me" button reveals the answer, and the round counts as missed.
- A quiet "Show a letter" button places a random letter of the answer in its slot and locks that slot. The phone can show at most all letters but one. Any hint takes both bonuses away for the round (see "Scoring").
- "Show me" and "Show a letter" are off while the partner still draws live, because the drawing can still change. They turn on when the drawer taps Done.
- Every attempt is saved in Convex with a timestamp. In a live round the drawer sees each wrong guess appear while drawing. In an async round the drawer watches the guesses in order afterward ("They tried CAT, then HAT..."). That is the drawer's payoff for the turn.

## Live

Live runs whenever both partners have the game screen open. Without the partner there, everything works as an async round. Nothing about the round changes except how fast each side sees the other.

- **Presence.** While the game screen is open, the phone joins the game's relay room. The relay's `welcome`, `joined` and `left` messages tell each phone whether the partner is there. Reuse `WidgetLivePresence`. Each phone's `hello` carries a role that says what its screen is doing, so the other phone never guesses. The widget canvas sends `drawing` and `watching`. The game adds three roles that the widget never sends.
  - `drawing`: the drawer of a round that has not ended. The drawer stays `drawing` after Done while waiting for the guess, so the guesser keeps the live canvas.
  - `watching`: watching live, waiting for the drawing, or guessing.
  - `choosing`: on the choose word screen.
  - `result`: on the reveal or the drawer's result screen.
  - `present`: in the game on any other screen.

  When a partner has several sockets in the game room, only the socket that most recently said hello determines the activity. An old socket left by a dropped connection cannot override the current screen. `DrawAndGuessPhase.liveRole` maps a phase to a role, and `DrawAndGuessPartnerPresence` maps the partner's role back to the copy (`present` reads as `here`, the heartbeat-only state). The drawer sees "[Name] is watching" only for a partner who is `watching`. A waiting partner sees "[Name] is drawing for you".
- **Strokes.** The drawer's strokes stream over the relay as in `WidgetLiveMessage` and play on the guesser's screen through `WidgetLivePlayback`.
- **Joining late.** A guesser who opens the game mid-drawing asks for a snapshot with `hello`, as `WidgetLiveRoom` does. The strokes so far play back quickly, then live strokes follow. A drawer who has tapped Done has no canvas left to answer, so a guesser who joins then gets no snapshot. The guesser's phone downloads the sent drawing and replays it whenever the live canvas holds no strokes.
- **Guesses.** Guesses go through Convex, because they are saved anyway. The drawer's live query shows them within a few hundred milliseconds.
- **The guess screen.** While guessing, the guesser's phone sends its screen to the room as a `DrawAndGuessLiveMessage`: the letters in the slots, which slots a hint filled, whether a wrong word is showing, and where the replay is (its replay time and speed). It sends the whole screen whenever it changes, and again when the drawer joins or this phone connects to a room the drawer is in. Nothing in it is saved. The drawer sees the letters on the drawing screen while still drawing (see "Drawing"), and the letters and the replay on the result screen (see "The drawer's result").
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

- **History.** The history lists the couple's finished rounds (solved or missed) that hold a drawing, newest first. It pages by round number, up to 50 rounds a page. The caller can ask for starred rounds only. Each round shows the word, the difficulty, the points, the solve time, the bonuses, the hints used, the number of attempts and the reactions. The phone knows which rounds are starred from `FavoritesStore`, so a round starred on another phone shows as starred on the result screen. The drawings stay readable through `get_media_signed_url` for as long as the couple's game rows exist.
- **Stars.** Either partner can star or unstar a finished round. A star is a private favorite (kind `game_round`, `favorites:set_favorite`). The partner is not notified and can't read it. Favorites are deleted with the rest of the couple's content.
- **Reactions.** Either partner reacts to a finished round with `reactions:set_reaction` (kind `draw_and_guess_round`), or takes the reaction back. Each person has one, and the last choice wins. It is stored in `reactions`, not on the round, and `get_reactions` brings it to both phones. The server refuses it on a round that is not solved or missed, or has no drawing. A first reaction sends the partner one push ("[Name] reacted ❤️ to your round of Draw & Guess"), which follows the Games notification setting.
- **Personal best.** A solve with no hints and a solve time is a personal best when it beat every earlier hint-free solve by the same guesser, and at least one such solve exists. The server decides this when the guess arrives and stores it on the round, so later faster solves don't change older rounds.
- **Records.** For each partner: solves as the guesser, first-try solves, average solve time, fastest solve with its word, and drawings the partner solved. The average covers hint-free solves of 10 minutes or less. The fastest covers every hint-free solve.
- **Sharing.** The result screen and the history share or save the drawing as a picture, with the word and "Drawn by Robin · Draw & Guess" under it. The picture leaves the app, so it uses the drawer's own name, never "you" or a nickname this phone gave the partner (`GamePlayer.sharedName`). Without that name it says only "Draw & Guess".
- **Result seen.** Each partner marks a finished round's result as seen once. The server keeps the first time for the drawer and for the guesser separately. The app uses it to decide whether to show a finished round's result again.

## Word lists

- Each language has its own list, written by hand. Norwegian is not a translation of English. It can include Norwegian things like brunost or a fjord.
- Every word must be drawable and must make sense to a 16-year-old.
- A native speaker reads every word before it ships. The check covers slurs, words with a crude second meaning, and words most people don't know. An agent once added "pakkis" to the Norwegian list, a slur for Pakistanis, and only the developer's read caught it.
- Start with about 300 words per language, split across easy, medium and hard.
- Words live in the backend, like the question catalog in `backend/questions/`, so the list can grow without an app update.

## Notifications

- "Your turn in Draw & Guess" when a drawing arrives. It is not sent when the round was solved live before the drawing arrived.
- "[Name] guessed your drawing" when the partner gets it right. This is the `game_result` push.
- "[Name] wants to play Draw & Guess with you" for an invite. The app allows one invite per partner every 15 minutes.
- One reminder, "Your turn in Draw & Guess", when a turn has waited 72 hours. A move never gets a second one.
- Never show the word or the drawing on the lock screen. The push payload holds only ids and the deep link `paeonia://games/draw-and-guess`.
- Skip the turn and result pushes when the partner has the game screen open, because they already see it live. Convex can't see relay presence, so the game screen also sends a heartbeat to the presence component while it is open. The open screen sends one every 30 seconds, and the component marks the screen closed 60 seconds after the last one.
- Game pushes follow the "Games" switch in notification settings (`games_enabled`, on by default).
- A push waits in the outbox until the drain sends it, and the drain checks it again first. It drops a game push when the recipient can no longer play in the couple, a turn push once the round no longer waits for that guesser, and a reminder once the turn moved on.

## Open questions

- Accessibility. Tiles must work with VoiceOver. The drawing has no text version until the reveal.
