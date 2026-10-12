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

## Why this game first

- It works across time zones, and it gets better when both partners happen to be online.
- It uses the drawing canvas, which other game apps don't have and Paeonia already does. Saved drawings are `PKDrawing` data (`widget_drawing_revisions.format = "pkdrawing"`), and each PencilKit stroke point keeps its time offset, so a saved drawing can be replayed at the pace it was drawn.
- Live watching reuses the live drawing code in `WidgetDrawing/Live/`: relay presence, the `hello` and snapshot catch-up, and stroke playback at the drawn pace.
- Building it produces the turn engine, the drawing replay, and the save-to-Memories flow. Exquisite corpse needs all three later.

## The turn

The game never ends. A couple has one ongoing Draw & Guess game, and a turn has two halves done in one sitting.

1. **Guess.** Open the game and your partner's drawing starts playing back. Guess by tapping letter tiles. You can guess while the drawing is still playing.
2. **Reveal.** The word locks in, the rest of the drawing finishes at once, and the phone gives a success haptic. The screen shows how long the guess took.
3. **Save prompt.** Either partner can save the drawing to Memories (see below).
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
- Long pauses in the replay are shortened to about one second, so a drawer who stopped to think doesn't make the guesser wait.
- The guesser can hold the replay to fast-forward.

### Guessing

- Guessing uses tiles, not the keyboard. The screen shows one empty slot per letter, with gaps for spaces. Below the slots are the answer's letters mixed with decoy letters, about 12 tiles for a short word.
- Decoys come from the game language, so a Norwegian word can show æ, ø and å tiles.
- When every slot is filled with a wrong word, the slots shake and the letters go back to the tiles.
- Guesses ignore case. Tiles show capital letters.
- Attempts are unlimited. A "Show me" button reveals the answer, and the round counts as missed.
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
- **A correct guess** ends the round right away. The drawer's phone sends the drawing as it is at that moment, and both phones show the reveal together. The roles then swap. The new drawer picks a word while the other partner stays to watch, so two partners who are both online can play back and forth without leaving the screen.
- **The drawer taps Done before a correct guess.** The round continues as a normal round, and the guesser keeps guessing on the finished drawing.
- **Lost connection.** The drawer keeps drawing and the drawing still sends on Done. The guesser's phone reconnects and asks for a fresh snapshot. The relay closes sockets after 10 minutes (`SESSION_MS`), so the same reconnect path runs during long rounds without the players noticing.
- **Invite.** When the partner isn't in the game, either partner can tap "Tell [Name] you want to play" (see `docs/games-plan.md`). The push opens Draw & Guess directly, so the partner lands in the live round.
- **Relay room.** The game needs its own room so it doesn't share the 4-socket cap with Home and the widget canvas. This is the relay channel change in `docs/games-plan.md`, and the first version needs it.

## Scoring

The play style is a couple setting (see `docs/games-plan.md`).

**Together.** One shared score. Each correct guess adds the word's points to the couple's total. A missed round adds nothing and takes nothing away.

Points are 1 for easy, 2 for medium and 3 for hard.

**Against each other.** Each partner has their own score. A correct guess gives the guesser the word's points plus a speed bonus of 1 point when the guess comes while the partner is still drawing, or within 30 seconds of first seeing the finished drawing, as the guesser's own screen showed it. The drawer gets the word's points when the guess is right. Both partners draw and guess equally often, so the difference between the totals comes down to how fast and how well each one plays.

In both styles the scores keep growing and never reset. The server keeps the shared total and both personal totals at all times, so switching play style loses nothing.

## Streak

Draw & Guess counts toward the couple's existing streak through a new game activity kind in `ACTIVITY_KINDS` (`backend/convex/lib/streaks.ts`). Sending a drawing counts, with the round id as the dedupe key. Guessing alone doesn't count, because the turn isn't done until you draw back.

## Save to Memories

After the reveal, both partners can save the drawing to Memories. The guesser sees the prompt at the reveal. In a live round the drawer sees it at the same moment. In an async round the drawer sees it the next time they open the game. If either one says yes, the drawing is saved as a memory with the word as its title. Nothing is saved without a yes, and the game never saves on its own. The prompt rules are in `docs/games-plan.md`.

The phone that says yes renders the drawing to an image, uploads it as ordinary memory media, and asks the server to save the round. The server saves a round at most once. When both partners say yes at the same moment, the second request gets the existing memory back.

## Word lists

- Each language has its own list, written by hand. Norwegian is not a translation of English. It can include Norwegian things like brunost or a fjord.
- Every word must be drawable and must make sense to a 16-year-old.
- A native speaker reads every word before it ships. The check covers slurs, words with a crude second meaning, and words most people don't know. An agent once added "pakkis" to the Norwegian list, a slur for Pakistanis, and only the developer's read caught it.
- Start with about 300 words per language, split across easy, medium and hard.
- Words live in the backend, like the question catalog in `backend/questions/`, so the list can grow without an app update.

## Data

The functions are in `backend/convex/games.ts` and the helpers in `backend/convex/lib/games.ts`. The shared rules are in `docs/games-plan.md`.

- `game_settings`: one row per couple with the play style and the game language. Either partner writes it, and the last write wins. Changing the language replaces the words offered for the open turn.
- `games`: one row per couple with `kind = "draw_and_guess"`, created by `ensure_draw_and_guess_game` (the caller draws first). `state` is `choosing_word`, `drawing`, or `guessing`, and `turn_user_id` is the partner who acts next. The row holds the shared total (`shared_points`), each partner's own total, the three word choices while a word is being chosen, and the start of the turn. `version` goes up with every change.
- `game_moves`: one row per round. It holds the word (or the custom word), the difficulty, the drawing as `pkdrawing` media in the `game-drawings` bucket, the time the guesser first saw the drawing, and the result (`drawing`, `guessing`, `solved`, or `missed`). The round exists from the moment the drawer picks a word. The client creates the round id, so a drawing queued offline can name its round.
- `game_guesses`: every attempt with its timestamp. The query returns the attempts with each round.
- `game_save_responses`: a partner's "Not now" for a round. A yes saves the memory and is recorded on the round (`memory_id`, `saved_by_user_id`).
- `game_used_words`: the words the couple has already been offered, per language and difficulty. A difficulty starts over when all its words were offered.
- `game_presence` and `game_invites`: the open game screen, and the last invite each partner sent.
- The guesser's phone receives the word when the round starts, because it builds the tiles and checks guesses locally for instant feedback. The UI never shows the word before the reveal. Cheating isn't a real risk between partners, so the server doesn't hide the word. The three word choices are different: only the drawer whose turn it is receives them.
- A turn drawn offline is saved on the phone and sent when the phone is back online. The UI tells the drawer: "Saved on this phone. We'll send it when you're online." Picking a word, sending a drawing, a guess, and giving up are safe to retry.
- Scoring: a correct guess adds the word's points to the shared total and to the drawer's total. The guesser's total gets the word's points plus 1 when the phone says the bonus was on screen. When the guess has no claim, `scoreSolve` in `lib/games.ts` decides: 1 when the round is still `drawing`, or when the guess is within 30 seconds of the later of `guesser_first_seen_at` and `drawing_submitted_at`. The server keeps all three totals whatever the play style, so the style only changes what the app shows. The speed bonus follows what the player saw. A correct guess carries `p_speed_bonus` (whether the bonus was still on screen) and `p_solve_ms` (time since the player first saw the drawing), both from the phone's clock. The phone works them out the same way in both play styles. The server uses them when present and falls back to `scoreSolve` only when both are missing. A guess that waited in the offline queue, or that reached the server before `mark_round_seen`, keeps the bonus the screen showed. The server accepts a solve time from 0 ms to 30 days and rejects anything else. Both values are part of the request hash for the guess, so a retry with different values is refused. A wrong guess ignores them. Either partner could send false values, which is acceptable for a two-person game.
- A correct guess ends the round at once, even when the drawer has not sent the drawing yet. The guesser's turn to draw starts, and the drawer's later `submit_drawing` attaches the drawing to the solved round without changing the turn.
- Relationship cleanup deletes every game row of the couple and queues the drawings for deletion. Presence rows go as soon as the relationship ends. A memory saved from a round is an ordinary memory and follows the memory rules.

## Notifications

- "Your turn in Draw & Guess" when a drawing arrives. It is not sent when the round was solved live before the drawing arrived.
- "[Name] guessed your drawing" when the partner gets it right.
- "[Name] wants to play Draw & Guess with you" for an invite. The app allows one invite per partner every 15 minutes.
- One reminder, "Your turn in Draw & Guess", when a turn has waited 72 hours. A move never gets a second one.
- Never show the word or the drawing on the lock screen. The push payload holds only ids and the deep link `paeonia://games/draw-and-guess`.
- Skip the turn and guessed pushes when the partner has the game screen open, because they already see it live. Convex can't see relay presence, so the game screen also keeps a presence row in Convex while it is open, the same way `chatPresence.ts` tracks open chats. The open screen refreshes the row every 30 seconds, and a row older than 60 seconds counts as gone.
- Game pushes follow the "Games" switch in notification settings (`games_enabled`, on by default).

## Screens

The screen-by-screen design. It does not change the rules above. Copy keys start with `games.drawAndGuess.` and the tables list only the part after it. "[Name]" is the partner's display name (`WidgetSyncIdentityStore`, falling back to `pairingCelebrationPartnerName`, as `WidgetDrawingView` does). Counts such as points, seconds and tries use String Catalog plural variants. Norwegian is Bokmål. Add every string to the catalog with a translator comment.

### Shell shared by every phase

- One screen, `DrawAndGuessScreen`, opened from the Games tab and from the invite and turn pushes. It shows one phase at a time, picked from the game row, the current round, my role, and relay presence. The wire-up is the view model's job, not the view body's.
- Look. `.paeoniaBackgroundSecondary` background, `.preferredColorScheme(.dark)`, inline title "Draw & Guess" / "Tegn og gjett", dark toolbar, as in `WidgetDrawingView`. The canvas surface is `.paeoniaBackgroundPrimary` with the widget ink palette, so a saved drawing looks like a widget drawing.
- No cards. Only repeated items with meaning get a fill (word rows, tiles, slots, chips): `.paeoniaSurfacePrimary` or `.paeoniaSurfaceSecondary`, `PaeoniaRadius.radius12` for tiles and slots, `radius16` for word rows.
- One square. Drawing and replay use the same square, side = min(width, space left), so strokes never rescale between drawing and watching. Phases never resize it. The two result phases shrink it to 80% once (see Reveal).
- Side from the real rows. On a phone `DrawAndGuessPhaseLayout` measures the rows above and below the square once they exist, and sets the side so the screen fits without scrolling when the width allows it (minimum 200 pt, then it scrolls). A result that is playing freezes the side the guess screen had, and the drawer's result screen takes the side the drawing screen had (`DrawAndGuessSideMemory`), so the square never jumps. At accessibility text sizes the tiles are tall and the screen scrolls.
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
| Saved to Memories | `memorySaved()` |
| Invalid custom word | `validationError()` |
| Wrong word (new) | `gameWrongGuess()`, two soft impacts 60 ms apart, built on the private `impact` helper. A wrong guess is not an error, so it does not use the error notification. |

### 1. Choose a word

Purpose. Make one quick choice and start. The round starts in Convex when the drawer taps Start, so the choice has a confirm step.

Layout, top to bottom.
1. Title "Pick a word to draw" (`PaeoniaTypography.heroTitle`), one line of subtitle in `.paeoniaTextSecondary`.
2. Pending save row, only when the last round's save prompt is still open (see Reveal). It is one compact row with a 48 pt thumbnail, so the prompt has a home after the player leaves the result.
3. Three word rows in a `VStack(spacing: space12)`, easy, medium, hard from top to bottom. A row is `radius16`, `.paeoniaSurfaceSecondary`, minimum 64 pt tall. Left, the word in `PaeoniaTypography.title`. Under it, "Easy, 1 point" in `caption`, `.paeoniaTextSecondary`. Right, difficulty pips: 1, 2 or 3 `camera.macro` flowers in `.paeoniaAccentPrimary`. At accessibility sizes the pips hide, the text stays.
4. "Draw your own" row, same shape, with `square.and.pencil` instead of pips.
5. Pinned bottom: primary "Start drawing", disabled until a row is selected.

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
| `choose.error.character` | Use letters only. Numbers and symbols don't fit in the puzzle. | Bruk bare bokstaver. Tall og tegn passer ikke i gjettingen. |
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

Live indicator. The leading slot follows what the partner's phone says it is doing. A partner who is `watching` shows the avatar (24 pt, accent ring) and "[Name] is watching". A partner on the last result shows "[Name] is looking at the result", and one who is in the game but has not said more shows "[Name] is here", both without the ring. When the partner joins, the avatar scales 1 to 1.12 and back once (`motionDefault`) and `partnerDrawingReceived()` fires. Reduce Motion: no scale, the haptic stays. When the partner is away the slot shows "[Name] will see it later" in `.paeoniaTextTertiary`, so async never feels broken. VoiceOver announces the line whenever it changes to a new one.

Wrong guesses while drawing. The newest wrong guess fills the trailing slot as a capsule (`.paeoniaSurfacePrimary`, `caption` semibold, `.paeoniaTextSecondary`, never red). It arrives with `cardReveal` and an 8 pt rise, replaces the previous one, and fades out after 6 seconds, so the row is calm again. No layout shift, because the slot is always laid out. Haptic `partnerDrawingReceived()` only while no stroke is in progress (`onStrokeInProgressChange`). Reduce Motion: fade only. VoiceOver gets a queued, low priority announcement "[Name] tried CAT". Every guess is kept for the drawer's result (phase 6).

Done. `drawingSent()`, then the phase 6 "sent" view. Offline, the drawing is stored on this phone and the sent view shows the offline line below. A draft survives leaving the screen and relaunching, as `WidgetDrawingDraftStore` does.

The partner solves it mid-drawing. The canvas stops taking touches in the same frame, and a stroke in progress is kept. The phone sends the drawing as it is, the tool rows fold away (`stateChange`), and the phase 6 reveal plays. The drawer is never asked anything while it happens.

| Key | English | Norwegian |
|---|---|---|
| `draw.wordLabel` | Draw | Tegn |
| `draw.watching` | [Name] is watching | [Name] ser på |
| `draw.later` | [Name] will see it later | [Name] ser den senere |
| `draw.here` | [Name] is here | [Name] er her |
| `draw.lookingAtResult` | [Name] is looking at the result | [Name] ser på resultatet |
| `draw.tried` | [Name] tried %@ | [Name] prøvde %@ |
| `draw.sendOffline` | Saved on this phone. We'll send it when you're online. | Lagret på telefonen. Vi sender den når du er på nett. |
| `draw.clear.title` | Clear the drawing? | Tømme tegningen? |
| `draw.clear.message` | This removes everything you've drawn so far. | Dette fjerner alt du har tegnet så langt. |
| `draw.clear.action` / `.cancel` | Clear / Keep drawing | Tøm / Fortsett å tegne |

The offline line uses `.paeoniaSyncPending` with `clock`. The Done button reads `common.done`, with the accessibility label "Done, send to [Name]" / "Ferdig, send til [Name]".

### 3. Waiting for the partner to draw

Purpose. Say what is happening, and make the wait feel shared.

Variants, one layout.
- Waiting for the word. The title follows the partner's role. On the result screen: "Waiting for [Name] to continue". On the choose word screen: "[Name] is picking a word". Away or unknown: "Waiting for [Name]", with the later hint and the invite button. The live hint is left out here, because there is no drawing to watch yet.
- Partner drawing, live or not. Title "[Name] is drawing for you".
- The title of the screen is fixed when it opens, so it does not change its words while it fades out into the guess.
- Once the round has started, dim answer slots appear under the title with "5 letters". It is the first hint that something is coming, and it leaks nothing, because the guesser's phone has the word anyway.

Layout, centered in the content, top to bottom.
1. Partner avatar, 96 pt. When the partner is in the room, a soft ring breathes around it (`.paeoniaAccentPrimary` at 0.2 to 0.5 opacity over 2.4 s, repeating). Reduce Motion: a still ring at 0.35.
2. Title (`PaeoniaTypography.title`) and one line of hint.
3. Dim slots (optional, see above).
4. Pinned bottom, only while the partner is not in the game: the invite button.

The invite button is secondary style, "Tell [Name] you want to play". After a send it is disabled and reads "Sent" with `checkmark`. It comes back when `last_invite_at` is 15 minutes old (a `TimelineView` on that date, no polling). It hides while the partner has the game open. A failed send uses the top banner and leaves the button enabled.

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

VoiceOver reads avatar and title as one element. The ring is hidden. The score capsule and a pending save row sit above, in that order.

### 4. Guessing

Purpose. Watch, guess fast, feel clever.

Layout, top to bottom.
1. Live row, one fixed line. Leading, "[Name] is drawing for you" while live, or "[Name] drew this for you" in async (avatar 24 pt). Trailing, the speed bonus label in "Against each other" only (see below).
2. Square replay (`DrawAndGuessReplayTimeline` driven by `DrawAndGuessReplayClock`). A 2 pt progress line runs along its bottom edge in `.paeoniaAccentPrimary` at 0.6 opacity.
3. Answer slots, centered, one group per word. A group never splits unless one word is wider than the screen. Slot width = (available width minus 4 pt gaps) / letters, clamped to 24 to 44 pt, height 48 pt. An empty slot is `.paeoniaSurfaceSecondary` with a 2 pt underline in `.paeoniaTextTertiary`. A filled slot is `.paeoniaSurfacePrimary` with the letter in `PaeoniaTypography.title`. Hit areas run the full 48 pt height and reach into the gaps.
4. Tile grid, 6 columns and 2 or 3 rows, tile = (width minus 5 gaps of `space8`) / 6, capped at 56 pt, square, `radius12`, `.paeoniaSurfacePrimary`, letter in `PaeoniaTypography.title`. A used tile becomes an empty `.paeoniaSurfaceSecondary` cell, so the grid never reflows.
5. Pinned bottom: the grid and slots sit here, in thumb reach, and below them a quiet "Show me" button (`PaeoniaQuietButtonStyle`, 44 pt).

Interactions.
- Replay plays at the drawn pace from the first moment the screen shows the drawing. Press and hold anywhere on the replay for 4x (`DrawAndGuessReplayClock.fastForwardRate`). Release returns to 1x. While held, a `forward.fill` glyph shows at the bottom trailing corner of the canvas in `.paeoniaAccentPrimary`, and `selection()` fires once at press. Holding must not block the tiles, which are outside the replay.
- Discovery. On the first replay a player ever watches, a "Hold to speed up" capsule shows over the bottom of the canvas for 3 seconds, then fades. A local flag stops it showing again. After that only the glyph shows during a hold.
- Guessing while it plays is allowed and expected. Tapping a tile moves it into the first empty slot (a 0.16 s spring flight, `matchedGeometryEffect`) with `selection()`. Reduce Motion: the tile swaps with a `motionFast` cross-fade.
- Tapping a filled slot sends its tile back to its own cell, with `selection()`. Later tiles stay where they are, as `DrawAndGuessSlots.remove(at:)` does.
- A full, wrong word. The slots shake sideways 8 pt, three swings in `motionSlow`, and their outline turns `.paeoniaWarning` for 0.4 s. `gameWrongGuess()` fires. Then the tiles fly back, last letter first, 30 ms apart. Reduce Motion: no shake. The outline holds in `.paeoniaWarning` for 0.6 s and the tiles cross-fade back. The attempt goes to Convex without any wait.
- A full, correct word goes to the reveal (phase 5).
- Show me. A centered alert. The default action does not use the destructive role, because nothing is lost.
- A guess typed while offline is checked on the phone, so feedback is instant. See the reveal for what a queued win shows.

The speed timer. Only "Against each other" gets one, because only that style has a bonus. It is not a countdown number. The trailing slot of the live row shows "Speed bonus +1" in `.paeoniaInkGold` (`bolt.fill`), and a 3 pt line under the replay drains from full to empty over 30 seconds in the same gold. When time is up, both fade (`motionSlow`) with no sound and no haptic, and nothing in the screen turns red or pushes. In a live round the label stays full while the partner draws, because any guess before Done earns the bonus. The 30 seconds count from the later of the server's `guesser_first_seen_at` and `drawing_submitted_at`, so reopening the app resumes the right remaining time. Under Reduce Motion the line is replaced by the label alone, which disappears at 30 seconds. "Together" has no timer and never mentions speed.

| Key | English | Norwegian |
|---|---|---|
| `guess.drawnBy` | [Name] drew this for you | [Name] tegnet dette til deg |
| `guess.speedBonus` | Speed bonus +1 | Fartsbonus +1 |
| `guess.speedBonus.a11y` | Guess within 30 seconds for 1 extra point. | Gjett innen 30 sekunder for ett ekstra poeng. |
| `guess.holdHint` | Hold to speed up | Hold for å spole fremover |
| `guess.showMe` | Show me | Vis meg |
| `guess.showMe.title` | Show the answer? | Vise svaret? |
| `guess.showMe.message` | This round won't give any points. You can still save the drawing. | Denne runden gir ingen poeng. Du kan fortsatt lagre tegningen. |
| `guess.showMe.cancel` | Keep guessing | Fortsett å gjette |

VoiceOver. The game is visual, and the drawing has no text version before the reveal. So the replay is one element, "Drawing by [Name], playing", with the hint "It can't be described before you guess." / "Den kan ikke beskrives før du har gjettet." Custom actions on it are "Play faster" (toggles 4x) and "Show the whole drawing" (calls the clock's `finish`). The answer is one group, "Answer, two words, 3 and 5 letters", containing one element per letter slot ("Letter 2, A. Double tap to remove" or "Letter 2, empty"). Tiles come next in row order, and a rotor named "Empty letters" jumps between empty slots. Placing a tile announces "A in letter 2". A wrong word announces "Not it. Try again."

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
| 1.90 | "Speed bonus +1" lands in gold with `streakContinued()`, if the guess earned it. |
| 2.20 | The save row rises in (`cardReveal`). |

Everything is tappable from 1.10 s. A tap on the screen jumps to the settled state, as `PairingCelebrationTimeline.skip` does, without repeating haptics. Build a `DrawAndGuessRevealTimeline` like that timeline, with a run id, an injected schedule and injected haptics, so tests can run it fast. Reduce Motion: no ripple, bloom, glow or count-up. The settled state shows at once, with only `answerRevealed()`.

Solve time. "You solved it in 24 seconds" (`Duration.UnitsFormatStyle`, seconds and minutes). It uses the server's `solve_ms`. Past 10 minutes the line is dropped, because the time then says more about the day than the guess.

Score panel.
- Together. The couple total counts up from the old to the new total in 0.6 s, big, in `PaeoniaTypography.countdownNumber`, with "points together" under it and "+2" in `.paeoniaAccentPrimary` beside it. Both avatars sit above. One `streakTick` per point added.
- Against each other. The two avatars are the two columns, each with a total below. A "+3" pops on mine and a "+2" on theirs, and the totals count up. Under my column, if I am the guesser, two quiet lines "The word +2" and "Speed bonus +1" (gold). Under theirs, "For the drawing +2". No winner banner and no comparison text. The numbers do that.
- Queued win (offline). The panel shows the word's points without a bonus and the line "Your score updates when you're online." The server adds the bonus the phone claimed when the guess arrives, so a queued guess keeps it, and the bonus line appears once the result is confirmed.

Save to Memories. The row is one full-width secondary button, "Save drawing to Memories", with no question above it. Saving shows the button's loading state while the phone renders and uploads the image, then the whole row becomes `checkmark.circle.fill` "Saved to Memories" (`memorySaved()`). If the partner saved first, the row opens already in the saved state with "[Name] saved this to Memories". Offline, the row shows the `draw.sendOffline` line and keeps trying. Continue at the bottom means no. It records "not now" for me only.

If the player leaves the result some other way, such as closing the app, the save option moves to the pending save row at the top of the choose and waiting screens (compact: thumbnail, "Save CAT to Memories?", the same single button) until the next round starts.

Hand-off. The primary button is "Your turn to draw", pinned at the bottom and always the primary action. It crosses to phase 1 over `pairedScreenTransition` and keeps no state. There is no forced answer, no second confirm, and no auto-advance, because the player may want to look at the drawing a bit longer. In a live pair the drawer's phone is already on its own result screen, so the two phones move on independently.

| Key | English | Norwegian |
|---|---|---|
| `reveal.title` | Got it! | Riktig! |
| `reveal.solveTime` | You solved it in %@ | Du løste den på %@ |
| `reveal.pointsTogether` | points together | poeng sammen |
| `reveal.you` | You | Du |
| `reveal.word` / `reveal.speed` / `reveal.drawing` | The word / Speed bonus / For the drawing | Ordet / Fartsbonus / For tegningen |
| `reveal.offlineScore` | Your score updates when you're online. | Poengene oppdateres når du er på nett. |
| `save.save` | Save drawing to Memories | Lagre tegningen i Minner |
| `save.saved` | Saved to Memories | Lagret i Minner |
| `save.savedBy` | [Name] saved this to Memories | [Name] lagret dette i Minner |
| `save.pendingRow` | Save %@ to Memories? | Lagre %@ i Minner? |
| `handoff.draw` | Your turn to draw | Din tur til å tegne |

VoiceOver. On the word landing, post one announcement, "Correct. It was CAT. 2 points." Then focus moves to the title. The bloom and glow are hidden. The count-up exposes only the final value. Dynamic Type. The avatar columns stack vertically at accessibility sizes, and the screen scrolls with the button pinned.

### 6. The drawer's result

Purpose. The drawer's payoff. It should feel like watching the other person think.

Right after Done, if the round is not solved, the drawer sees the same square (80%, static, showing the full drawing) with:
1. Status line. "Sent to [Name]". Under it, one of three lines. "[Name] is looking at it" while the partner is on the guess screen (role `watching`, with the avatar ring and the same joined pulse as phase 2). "[Name] has seen it" once the server has `guesser_first_seen_at` for the round and the partner has left the guess screen. "[Name] hasn't seen it yet" when the guesser has never seen the drawing, also while the partner is somewhere else in the game (`DrawAndGuessSentStatus`).
2. Guess area. With no guesses, "No guesses yet. We'll tell you when [Name] tries." As guesses arrive, each wrong word is a chip (`.paeoniaSurfacePrimary`, `caption` semibold, wrapping, in order), appearing with `cardReveal` and `partnerDrawingReceived()`. The row reads "[Name] tried" in front.
3. Pinned bottom: nothing, until the round ends. The drawer may leave with back.

Async open. When the drawer opens the game after a round ended, the chips play back in order, 0.5 s apart, compressed so the sequence takes 3 seconds at most, each with a soft `partnerDrawingReceived()`. Tapping the screen finishes the sequence. This is the screen the doc calls the drawer's payoff, so it never appears all at once the first time. Reduce Motion: all chips at once.

Solved. The correct word joins the chip row last, in `.paeoniaSuccess`, with the same letter ripple, `answerRevealed()` and a half-size bloom as phase 5. Title "[Name] got it!". Under it one sentence, "[Name] got it in 24 seconds, on the first try." or "[Name] got it in 24 seconds and 3 tries.", without the time when it is missing or past 10 minutes. The panel for points is phase 5's, with my column showing "For the drawing +2". The save row and the primary button "Continue" (to phase 3) follow. If the solve happens while the drawer is still drawing, the sequence is the same, and the sent drawing is the final frame.

Unseen results. The drawer may not open the game until the partner has already solved and drawn back, so the current round is then a new one. The game shows the latest finished round's result first when this phone has not shown it, with "Continue" leading to the new round. A local flag per round id (a small store like `StreakMilestoneStore`) tracks it.

Missed, from the drawer's side. Title "[Name] asked for the answer", then the chips of the tries, then "No points this round." The tone stays flat and kind, with no "gave up" wording.

| Key | English | Norwegian |
|---|---|---|
| `result.sent` | Sent to [Name] | Sendt til [Name] |
| `result.notSeen` | [Name] hasn't seen it yet | [Name] har ikke sett den ennå |
| `result.looking` | [Name] is looking at it | [Name] ser på den nå |
| `result.seen` | [Name] has seen it | [Name] har sett den |
| `result.tried` | [Name] tried | [Name] prøvde |
| `result.noTries` | No guesses yet. We'll tell you when [Name] tries. | Ingen gjetninger ennå. Vi sier fra når [Name] prøver. |
| `result.gotIt` | [Name] got it! | [Name] fikk den! |
| `result.solvedTimedFirstTry` / `result.solvedTimedTries` | [Name] got it in %@, on the first try. / [Name] got it in %@ and %lld tries. | [Name] klarte det på %@, på første forsøk. / [Name] klarte det på %@ og %lld forsøk. |
| `result.solvedFirstTry` / `result.solvedTries` | [Name] got it on the first try. / [Name] got it in %lld tries. | [Name] klarte det på første forsøk. / [Name] klarte det på %lld forsøk. |
| `result.missed` | [Name] asked for the answer | [Name] ba om å få se svaret |
| `result.noPoints` | No points this round. | Ingen poeng denne runden. |
| `handoff.continue` | Continue | Fortsett |
| `handoff.watch` | Watch [Name] draw | Se [Name] tegne |

Watch the partner draw. When this phone is on the drawer's result and the server's current round is a newer round in state `drawing` with the partner as drawer, the bottom button changes from "Continue" to "Watch [Name] draw", with a pulsing dot in front (still under Reduce Motion). It gives one `partnerDrawingReceived()` haptic and a VoiceOver announcement ("[Name] is drawing for you") when it appears. Tapping it does what Continue does, which also counts as not saving, and lands in the live watching phase when the partner is drawing live. The save button stays above it. The view model exposes this as `partnerStartedDrawing`.

VoiceOver reads the guesses as one sentence, "[Name] tried CAT, then HAT, then DOG", built with `ListFormatStyle`-style joining, and the chips are hidden from the rotor.

### 7. Missed round (guesser)

Purpose. A soft landing. No guilt, no lost points.

After the Show me alert is confirmed, the slots fill with the answer left to right (still `.paeoniaTextPrimary` on `.paeoniaSurfacePrimary`, not green) over 0.5 s, with a single `partnerDrawingReceived()` and no bloom. The replay finishes, the canvas eases to 80%, and the panel shows:
- Title "Not this time".
- Line "No points this round. Ready to draw one back?"
- The save row (the drawing and word are still a good memory).
- Primary "Your turn to draw".

There is no score panel, in both styles, because nothing changed. The play style needs no other handling.

| Key | English | Norwegian |
|---|---|---|
| `missed.title` | Not this time | Ikke denne gangen |
| `missed.line` | No points this round. Ready to draw one back? | Ingen poeng denne runden. Klar for å tegne en tilbake? |

### Wide layouts and Dynamic Type

- Wide means 700 pt or more wide and wider than tall, measured with `onGeometryChange`, not the device idiom. It applies to iPad landscape, iPad Split View, and iPhone landscape.
- Wide layout. Two columns. Left, the square (up to 640 pt), centered vertically. Right, a column up to 420 pt with everything else of the phase, and the pinned bottom cluster at the bottom of that column. On iPhone landscape the right column scrolls.
- Narrow layouts (including iPad portrait) use one column inside `.paeoniaReadableWidth()`. The square is capped at 640 pt, like the widget canvas, so strokes keep their weight.
- Choose, waiting and missed are text-led and use `.paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)` in every size.
- At accessibility Dynamic Type sizes every phase becomes a scroll view with the primary button pinned. The canvas keeps its square. Pips, ring and avatars in the reveal rearrange, never disappear.

### Rules questions this design raises

- The unseen result gate is local to the phone (a second device would show the result again).

## iOS

Code map in `docs/implementation-map.md`. Decisions the sections above leave open:

- **Local first.** Picking a word, sending the drawing, a guess, "Show me" and saving to Memories go into the pending operations before anything is sent. The screen applies those queued moves on top of the server's state, so a correct guess shows the reveal at once and a drawing sent offline shows "Saved on this phone. We'll send it when you're online." The server's points, speed bonus and solve time replace the local values when they arrive. The speed bonus and solve time are the ones the phone sent with the guess. Creating the couple's game and changing settings need a connection.
- **Order.** A drawing waits for the word pick of its round, and a pick waits for this person's earlier guesses and give up. A guess or give up waits for the earlier guesses of the same round, so a wrong guess is never refused after the correct one ended the round. A refused word or drawing stops retrying and shows a notice. A refused drawing goes back on the canvas. When the word is refused, the drawing already made for it is not sent. It is kept and appears on the canvas of the drawer's next round, after they pick another word.
- **One drawing size.** The drawer scales the drawing to a 320 point square before sending, and the guesser scales it to their own canvas. The live room uses the same size.
- **Reveal.** Each person moves past a round's reveal once, and the phone remembers it. "Continue" with the save question still open keeps it open, and the choose and waiting screens show it as the pending save row until the next round starts. The guesser draws next, so "Your turn to draw" shows when the guesser leaves the reveal.
- **Built screens.** The screens follow the design above with these differences. The answer slots sit under the square in the scrolling content (pinned with the tiles only at accessibility text sizes), so the reveal does not move them. The "Missed" result uses the same layout as the solved reveal instead of the focused width. When the partner solves the round while the drawer is still drawing, the drawer's screen cross-fades to the result instead of folding the tools away. The pending save row covers the round that just ended, and is gone once the next round starts. The Draw & Guess canvas shares the widget tool controls through `WidgetDrawingToolControlling` instead of the widget view model.
- **Live to async.** A guesser who watched the drawing live keeps the live canvas when the drawer taps Done, until the drawer leaves the live room. Then the sent drawing is downloaded and replayed. A guesser who did not watch gets the replay. The speed bonus clock starts when the guesser first sees the drawing, live or replayed.
- **Role.** The open screen announces the role from the Live section through the relay `hello` and changes it with the phase (`syncLiveRole`).
- **Presence.** The open screen sends `set_game_presence` true on appear and every 30 seconds, and false on disappear and in the background. The hub and the game treat a heartbeat under 60 seconds old as "here", and check again every 15 seconds.
- **Setup.** The couple's game language is preselected from the first supported language of the phone, because the app cannot see the partner's language. The partner who did not choose sees "Here's what [Name] picked" once, tracked on the phone.
- **Drafts.** The drawer's unsent drawing is saved on the phone as they draw, so closing the app loses nothing.

## Open questions

- How a pixel eraser affects replay. It splits strokes, so check that the pieces keep their timing.
- Accessibility. Tiles must work with VoiceOver. The drawing has no text version until the reveal.
