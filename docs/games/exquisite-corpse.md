# Odd Creatures (exquisite corpse)

Design for the second drawing game. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. Draw & Guess (`docs/games/draw-and-guess.md`) sets the bar and owns the drawing canvas, the replay and the history this game reuses. This file covers only what is specific to Exquisite corpse.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-13.

- **The name is "Odd Creatures".** Norwegian "Rare skapninger". The game is known as exquisite corpse, and the code uses the kind `exquisite_corpse` and the Swift prefix `ExquisiteCorpse`.
- **Three parts, and turns alternate.** A figure is a head, a body and legs. The partner who starts a figure draws its head and its legs, and the other partner draws the body. The next figure starts with the other partner. Turns simply alternate forever, so over two figures each partner draws three parts.
- **The strip is 12% of a part.** The next drawer sees the bottom 12% of the part before, 38 pt of the 320 pt square. Nothing else of it.
- **Ideas are optional.** The canvas says "Draw the head". A quiet "Need an idea?" button deals a hand-written idea in the couple's game language. The idea shows as a chip with Shuffle and a remove button. Whatever chip shows when the drawer taps Done is saved with the part, stays hidden from the partner, and becomes the part's caption at the reveal.
- **Live shows folded paper.** While the partner draws live, you see the back of the folded paper with a soft glow where their pen moves behind it. The strokes that reach the strip appear while they are drawn. The hidden part never leaves the drawer's phone before the reveal.
- **The reveal unfolds part by part.** The folded paper opens one fold at a time from the top. Each part replays its strokes at the drawn pace, squeezed to about 2.5 seconds. Then the view zooms out to the whole figure with the petal bloom and a success haptic.
- **Play style doesn't apply.** A figure is always made together, so there are no points in either style. The hub shows how many figures the couple has made.
- **Each sent part counts toward the streak.**
- **Push copy names the part.** "Robin drew the head. Your turn to draw the body."
- **The history is "Our creatures".** Norwegian "Skapningene våre". Finished figures, newest first, with private stars, like "Our drawings". A star is a favorite (`FavoriteKind.corpseFigure`, `docs/implementation-map.md`, Favorites), so it also shows in Search.

## Why this game

- It uses the drawing canvas, the replay and the history with stars that Draw & Guess built (`docs/games-plan.md`, "Order").
- It is the one game where the surprise is shared. Neither partner knows what the figure looks like until the reveal, so both get the payoff.
- It works across time zones: a turn is one part, drawn whenever there's time.

## The figure

- A figure has three parts in this order: head (0), body (1) and legs (2).
- Each part is drawn on the Draw & Guess square, stored at the canonical 320 pt side (`GameCanvas.canonicalSide`). The figure is the three squares stacked with no gap, 320 by 960.
- The partner who starts a figure (the starter) draws the head and the legs. The other partner draws the body.
- The next figure starts with the partner who drew the body. Every turn passes to the other partner, so the person whose turn it is never depends on which part comes next.
- The person who creates the couple's game starts the first figure.
- The game never ends. A couple has one figure in progress at a time, and every finished figure goes to "Our creatures".

## The fold

- **What the next drawer sees.** The strip is the bottom 12% of the part before (`ExquisiteCorpseFold.stripFraction = 0.12`). It shows right above the next drawer's canvas, at the same scale, so a line that ends at the bottom edge of the head continues at the top edge of the body. In the finished figure the parts touch at exactly that edge.
- **What the drawer above is told.** The head and body canvases show a dashed fold line at 88% of their height. Under it, a small label: "[Name] only sees below this line". The legs canvas has no fold line, because nobody draws after it.
- **Drawing from the strip.** The canvas also lies over the strip, so a line can start on the strip and run down into the canvas. Ink drawn on the strip lies above the part's square, so the finished figure and the history cut it off.
- **The legs drawer** sees only the strip of the body. Their own head stays folded away, as on paper.
- **The strip leaves the phone on its own.** When the drawer taps Done, the phone clips the drawing to the strip and uploads it as a separate file, next to the full part. The server lets the partner read the strip at once, and the full part only once the figure is finished. So the hidden part of a drawing never reaches the partner's phone before the reveal, also not through a cache or a crafted request.
- **Clipping.** A stroke that is only above the fold is left out. A stroke that crosses the fold keeps the points below it, plus one point on the fold line where it crosses, so its line starts exactly at the fold. A stroke inside the strip is kept whole. Ink, width and transform are kept. Erased ink is clipped the same way, so the strip never shows erased ink (`PKStroke.mask`, as in the Draw & Guess replay).

## Ideas

- The drawing screen shows "Draw the head" (or body, legs) and, under it, a quiet "Need an idea?" button.
- Tapping it shows an idea chip, such as "a grandma", with a Shuffle button (`shuffle`) and a remove button (`xmark`). Shuffle deals the next idea. Remove clears the chip and brings back "Need an idea?".
- The chip that shows when the drawer taps Done is saved with the part. It is hidden from the partner until the figure is finished. At the reveal and in "Our creatures", each part shows its idea under the drawer's name. A part without an idea shows only the name.
- Ideas are noun phrases that fit any part: "a robot" as the head, the body or the legs. Each part has its own list, because some ideas only work as one part (a spider's legs, a teapot body).
- The server deals the ideas. While it is this person's turn, the game state carries a deck of 12 ideas for the next part in the couple's game language, shuffled with the part as the seed, so reopening the game deals the same deck. Shuffle walks through the deck and starts over at the end. The deck is cached with the state, so ideas work offline.
- A part sent with an idea stores the idea's id and its text. Later edits to the list don't change finished figures.
- When the couple changes the game language, the next deck comes in the new language. A part already sent keeps its idea.
- Each language has its own hand-written list in `backend/convex/lib/exquisiteCorpseIdeas.ts`, about 50 ideas per part. Norwegian is not a translation of English and can use Norwegian things like a troll, an elk or a nisse. Every idea must be drawable and make sense to a 16-year-old. A native speaker reads every idea before it ships, with the same check as the Draw & Guess word lists: no slurs, no crude second meanings, no words most people don't know.

## Drawing

- The Draw & Guess canvas, unchanged: PencilKit with the widget tools, colors, sizes, paint bucket, undo, redo and Clear (`GameDrawingBoard`).
- No time limit. Done sends the part. Done is disabled while the canvas has no strokes.
- The drawer's unsent drawing is saved on the phone as they draw, so leaving the screen or closing the app loses nothing (`GameDrawingStoring`, as Draw & Guess drafts).
- The part is stored at the canonical side, so it looks the same on both phones and in the figure.

## Live

Live runs whenever both partners have the game screen open. Without the partner there, everything works async. Nothing about the game changes except how fast each side sees the other.

- **Presence.** The game screen joins the game's relay room (`ch: "exquisite_corpse"`). Each phone's `hello` carries a role, as in Draw & Guess:
  - `drawing`: on the drawing screen for this person's part.
  - `watching`: on the waiting screen while the partner's part is open.
  - `result`: on the reveal.
  - `present`: in the game on any other screen.
- **The folded paper.** While the partner is `drawing`, the waiting screen becomes the watch screen: the partner's square, with the top 88% covered by the back of the folded paper and the strip open below it.
  - A soft glow (`.paeoniaAccentPrimary`, about 56 pt, heavily blurred) moves behind the paper where the partner's pen is, and is cut off at the fold, so it never shows over the strip. It follows coarse positions, about 8 a second, rounded to a 20 by 20 grid, so it shows where they draw and never what.
  - The strip shows the partner's strokes that reach it while they are drawn. The drawer's phone builds the stroke from the touches, because PencilKit hands it over only when the pen lifts, and sends the strip about 12 times a second while the stroke is in it.
  - The line above reads "[Name] is drawing the head" with the avatar ring.
- **Messages.** `ExquisiteCorpseLiveMessage` on the game's `GameLiveChannel`, sent beside the presence messages on the same socket:
  - `pen(partID, x, y)` while a finger or pencil is down, and `pen(partID, nil, nil)` when it lifts.
  - `strip(partID, drawing)`: the whole strip so far, clipped on the drawer's phone, as `pkdrawing` base64 at the canonical side. Sent after every change to the drawing, while a stroke is drawn across the strip, and again when the partner arrives (`onPartnerArrived`).
  - `done(partID)`: the drawer tapped Done.
  
  Every message carries the part id, so a message from an earlier part is ignored. The strip message is the whole state, so a lost message never leaves the watcher with missing strokes. No stroke of the drawing above the fold is ever sent.
- **The drawer's canvas is not streamed.** The game does not attach its canvas to `WidgetLiveDrawing`, so the relay's own `live` and `ops` stroke messages never carry the hidden part. The game uses `WidgetLiveDrawing` for presence and roles only.
- **Done, live.** The drawer's phone sends `done`. The watcher's line changes to "[Name] finished the head" and the paper gives one soft pulse, without a haptic. When the part reaches the server, the watcher's turn starts: the folded paper lifts away (`meaningfulMoment`), and the strip slides from the bottom of the watched square to the top of the new canvas (`matchedGeometryEffect`). As the strip settles, the fold sound marks the turn coming to you. The shared turn cue taps the phone when the server hands over the turn, whichever screen shows. The new canvas shows the live strip until the strip file has loaded, then the file. The two are the same drawing.
- **Lost connection.** The watcher falls back to the async waiting screen. A reconnect gets the whole strip again. The drawer keeps drawing and Done still sends.
- **The live reveal.** When the legs are done live, both phones open the reveal as soon as they have all three parts. Each phone waits for the server to finish the figure and then downloads the parts it lacks, which takes about a second. Until then both show the folded paper with "Opening…" and a slow shimmer.
- **Invite.** The waiting screen has the shared "Tell [Name] you want to play" button while the partner isn't in the game (`docs/games-plan.md`). The push opens Exquisite corpse directly.

## The reveal

Purpose. The best ten seconds of the game. Neither partner has seen the whole figure.

Who sees it when.
- The legs drawer sees the reveal right after Done, once the server has the part. Offline, the phone keeps the part and shows "Saved on this phone. You'll both see the whole figure when it's sent."
- The partner sees it the next time they open the game, or at once when they watch live.
- A figure's reveal shows until this person taps Continue. The server keeps a "reveal seen" time for each partner, so a second phone or a fresh install doesn't show it again. Like Draw & Guess, the latest unseen reveal comes before a new turn.

Beats, in seconds from the start. The later times assume each part plays for the full 2.5 s. Shorter parts move everything after them earlier.

| Time | What happens |
|---|---|
| 0.00 | The folded paper sits in the middle. The three parts are folded like an accordion with only the paper's back showing. `selection()`. The screen fades in over the first 0.36 s, so the paper rests about half a second before anything moves. |
| 0.80 | The top fold opens (`rotation3DEffect` around its top edge, `meaningfulMoment`). The fold sound starts 0.1 s before the fold lands, so its knock lands with it. One `streakTick` at 0.4 as the fold lands, at 1.16. The head replays its strokes at the drawn pace, squeezed to at most 2.5 s. Under it: the drawer's avatar (24 pt) and "Head by Robin", plus the idea in `.paeoniaTextSecondary` if the part has one. |
| about 4.0 | 0.3 s after the head's replay, the second fold opens below the head, and the view eases down to frame it. The body replays. `streakTick` at 0.6. |
| about 7.1 | The third fold opens and the legs replay. `streakTick` at 0.85. |
| about 10.5 | The finished legs hold for 0.5 s, then the view zooms out to the whole figure (`celebrationReveal`). 0.3 s into the zoom, as it settles: `answerRevealed()`, a petal bloom from behind the middle of the figure (`GamePetalBloom`, seeded by the figure id) and a soft radial glow centered on it. |
| about 11.4 | The title fades up, "Meet your creature", with "Creature 12" under it. The credits row shows the three parts with the avatars. The primary button appears. |

- When a fold opens, the caption of the part before fades out in 0.16 s, and the new caption fades in after it with a 6 pt rise, so two names never show on top of each other.

- Each part plays its strokes in drawn order through `GameReplayTimeline` and `GameReplayClock`, with long pauses shortened as in Draw & Guess. A part that took longer than 2.5 s plays faster to fit (`rate = duration / 2.5`). A short part plays at its own pace.
- Holding anywhere on the figure plays at 4x, with a `forward.fill` glyph and `selection()` once.
- A tap on the screen jumps to the settled state, as `PairingCelebrationTimeline.skip` does, without repeating haptics.
- The reveal runs on `ExquisiteCorpseRevealTimeline`, built like `DrawAndGuessRevealTimeline`: a run id, an injected schedule and injected haptics, so tests can run it fast.
- Reduce Motion. No 3D folds, camera moves, bloom or glow. The whole figure shows at once, settled, with `answerRevealed()`. A "Play again" button plays the strokes on request, part by part, without the folds.
- VoiceOver. On the settled state, one announcement: "Your creature is ready. Head by Robin, a grandma. Body by you. Legs by Robin." The figure is one element, "Creature 12, drawn by you and Robin", with the actions "Play again" and "Show the whole figure". The bloom and glow are hidden.
- The figure fits the screen at the end: the side of a part is the smaller of the width and a third of the height left for it. While a part plays, the view frames it larger (up to 55% of the height) and the parts above slide up.

Settled state, top to bottom.
1. The figure, centered, with a 2 pt hairline between parts in `.paeoniaTextTertiary` at 0.3 opacity, so the folds stay readable.
2. Title "Meet your creature" (`heroTitle`) and "Creature 12" (`caption`, `.paeoniaTextSecondary`).
3. Credits: three short rows, "Head by Robin · a grandma", "Body by you", "Legs by Robin · frog legs". Avatars tinted `.paeoniaPartnerOne` for me and `.paeoniaPartnerTwo` for the partner.
4. Pinned bottom: the primary button. "Draw the next head" when the next figure starts with me, otherwise "Continue". It queues the reveal seen mark and moves on at once.

Star. The shared favorite star (`FavoriteStarButton`, `star`, `star.fill`, `selection()`), next to an "Our creatures" button. The first favorite on a phone shows the banner "Only you can see your favorites." once (`FavoritesStore`).

## Our creatures

The history of finished figures. It follows "Our drawings" in look and behavior (`docs/games/draw-and-guess.md`, "8. Our drawings"), with these differences.

- No records section. The game has no scores.
- The header shows the count: "12 creatures" (`sectionTitle`).
- The grid uses adaptive columns of at least 104 pt, which gives 3 columns on a phone. A cell is the whole figure as a 1:3 thumbnail on `.paeoniaBackgroundPrimary` (`radius12`), with "Creature 12 · Oct 12" under it in `caption`. A `star.fill` badge sits at the top trailing corner when I starred it.
- A page is 30 figures, newest first, with All and Starred. Paging, caching, offline and empty states work as in "Our drawings".
- The detail screen shows the figure with the credits and plays the reveal's unfold without the bloom, once. "Play again" starts it over. The toolbar star toggles my private favorite.
- Entry points: "Our creatures" in the `…` toolbar menu on the game screen, a long press on the hub card or tile, and a quiet link on the hub card once a figure is finished.

VoiceOver. A cell is one element, "Creature 12, by you and Robin, starred". The detail figure reads like the reveal's figure.

## Streak

Sending a part counts toward the couple's streak as `game_turn_completed`, with the part id as the dedupe key. Every turn is one part, so each partner keeps the streak alive by drawing their part.

## Notifications

- Turn: title "Robin drew the head", body "Your turn to draw the body." After the body: "Robin drew the body", "Your turn to draw the legs." Sent when a head or body arrives, and not sent when the partner has the game open. The push carries `step: "body"` or `step: "legs"`, the part that is now the partner's turn, and the copy for each step is in `GAME_PUSH_COPY` (`lib/notificationCopy.ts`).
- Finished: title "Robin finished your creature", body "See the whole creature." Sent when the legs arrive, and not sent when the partner has the game open.
- A new figure needs no push of its own. The partner who draws the next head gets the finished push for the last figure, and that opens the reveal and then their turn.
- Reminder: "Your turn in Odd Creatures", once, when a turn has waited 72 hours.
- Invite: the shared "[Name] wants to play Odd Creatures with you".
- The lock screen never shows a drawing or an idea. The payload holds only ids, the step and the deep link `paeonia://games/exquisite-corpse`.
- The drain drops a turn push once the turn has moved on, and a finished push once the recipient has seen the reveal.

| Push | Title (English / Norwegian) | Body (English / Norwegian) |
|---|---|---|
| Turn, head done | %@ drew the head / %@ har tegnet hodet | Your turn to draw the body. / Din tur til å tegne kroppen. |
| Turn, body done | %@ drew the body / %@ har tegnet kroppen | Your turn to draw the legs. / Din tur til å tegne beina. |
| Finished | %@ finished your creature / %@ gjorde ferdig skapningen deres | See the whole creature. / Se hele skapningen. |
| Reminder | Your turn in Odd Creatures / Din tur i Rare skapninger | Pick up where you left off. / Fortsett der dere slapp. |
| Invite | %@ wants to play Odd Creatures with you / %@ vil spille Rare skapninger med deg | The shared invite body |

## Data

The functions are in `backend/convex/exquisiteCorpse.ts`, the pure rules in `backend/convex/lib/exquisiteCorpse.ts` and the ideas in `backend/convex/lib/exquisiteCorpseIdeas.ts`.

- `exquisite_corpse_games`: one row per couple, created by `ensure_exquisite_corpse_game` (the caller starts). It holds `turn_user_id`, `turn_started_at`, `turn_reminder_sent_at`, the current figure (`figure_id`, null between figures), `figure_number` (of the current or next figure), `part_index` (0, 1 or 2, the next part), `figures_finished`, and `version`, which goes up with every change.
- `exquisite_corpse_figures`: one row per figure. `id`, `couple_id`, `game_id`, `number`, `starter_user_id`, `created_at`, `finished_at`, and the two reveal seen times, `starter_reveal_seen_at` and `partner_reveal_seen_at`. The row exists from the moment the head arrives. The client creates the figure id, so a head queued offline can name its figure.
- `exquisite_corpse_parts`: one row per part. `id` (made by the client), `couple_id`, `game_id`, `figure_id`, `figure_number`, `part_index`, `drawer_user_id`, `drawing_media_asset_id`, `strip_media_asset_id` (head and body only), `idea_id` and `idea_text` (optional), `created_at`.
- A star is a row in the shared `favorites` table (kind `corpse_figure`), with the figure number as `ordinal` so one partner's stars page in order. The game has no star table of its own.
- Settings and invites are the shared `game_settings` and `game_invites`, and presence is the shared presence component room.
- `get_exquisite_corpse` returns the caller's view: the game, the current figure, the latest 10 finished figures, and the idea deck when it is the caller's turn. A part's `drawing_media_asset_id` and its idea are null unless the caller drew it or the figure is finished. The strip id is always there. Queries read no clock.
- `submit_exquisite_corpse_part` takes the figure id, the part id, the part index, both media ids and the optional idea id, with the client operation args. It checks couple access, that it is the caller's turn, that the index is the next part, and that the figure id is the current figure (or a new one, for a head). It checks both uploads the way Draw & Guess checks a drawing: owner, couple, parent kind `exquisite_corpse_part`, parent id, purpose, finalized. The strip is required for the head and body and refused for the legs. An unknown idea id is refused. The part is saved, the turn passes, the push goes out, and the streak activity is recorded. The legs finish the figure. The request hash covers all arguments, so a retry is safe and a changed retry is refused.
- `mark_exquisite_corpse_reveal_seen` sets the caller's reveal seen time on a finished figure. The first write wins.
- Stars use `favorites:set_favorite`, which saves only a finished figure and sets the value it is given, so a retry changes nothing.
- `get_exquisite_corpse_history` pages finished figures by number, up to 50 a page, optionally starred only (the caller's favorites).
- `get_exquisite_corpse_figure` returns one finished figure by id, or null. Search and the saved list use it to open a creature that is not in a loaded page.
- Media. A part's two files are `pkdrawing` uploads with `reserved_parent_kind = "exquisite_corpse_part"` and the part id as parent, purposes `exquisite_corpse_drawing` and `exquisite_corpse_strip`. The reservation needs the couple's game. `get_media_signed_url` lets a couple member read a strip, and the full drawing only when they drew it or the figure is finished. The orphan sweep counts both ids on a part as live references.
- Relationship cleanup deletes every row of the couple's game, and queues the drawings for deletion with the couple's other media. Account deletion ends the relationship, so it follows the same path.

## Screens

The screen-by-screen design. Copy keys start with `exquisiteCorpse.` and the tables list only the part after it. "[Name]" is the partner's display name, as in Draw & Guess. Counts use String Catalog plural variants. Norwegian is Bokmål. Every string gets a translator comment.

### Shell

- One screen, `ExquisiteCorpseScreen`, opened from the Games tab and from the pushes. It shows one phase at a time, picked by `ExquisiteCorpseResolver` from the game, the current figure, this phone's queued moves and relay presence.
- The Draw & Guess shell: `.paeoniaBackgroundSecondary`, `.preferredColorScheme(.dark)`, inline title "Odd Creatures" / "Rare skapninger", dark toolbar, no tab bar, bottom clusters pinned with `paeoniaBottomBar` inside `.paeoniaReadableWidth()`, phase changes as a cross-fade with a 12 pt rise over `meaningfulMoment` (Reduce Motion: cross-fade over `motionFast`). The canvas surface is `.paeoniaBackgroundPrimary` with the widget ink palette.
- The square is sized like the Draw & Guess square, counting the strip above it as part of its height, so the strip and canvas together fit without scrolling.
- Partner colors, avatars and haptics follow Draw & Guess.
- The paper back (the fold) is `.paeoniaSurfaceSecondary` with a soft vertical gradient to `.paeoniaSurfacePrimary` and a 1 pt highlight along the fold edge, so it reads as paper folded toward the viewer.

Haptics.

| Moment | Token |
|---|---|
| Pick a tool, color, idea, shuffle | `selection()` |
| Done sent | `drawingSent()` |
| Partner joins | `partnerDrawingReceived()` |
| The partner's part reaches the server and it is your turn | `gameYourTurn()` (`GameAttentionCue`) |
| Each fold lands in the reveal | `streakTick(intensity:)`, 0.4, 0.6, 0.85 |
| The whole figure shows | `answerRevealed()` |

### 1. Drawing

Purpose. Draw your part, and connect to the lines you were given.

Layout, top to bottom.
1. Part line, one fixed line. Eyebrow "Your part" (`caption` bold, uppercase, tracking 1.4, `.paeoniaTextTertiary`) and "Draw the head" in `PaeoniaTypography.title`.
2. Idea row, one fixed line (44 pt). "Need an idea?" as a quiet text button with `lightbulb`, or the idea chip: `.paeoniaSurfacePrimary` capsule, `caption` semibold idea text, a `shuffle` button and an `xmark` button (each 44 pt hit area). The chip comes in with `cardReveal` and a 6 pt rise. Shuffle swaps the text with a quick cross-fade and `selection()`.
3. Live row, one fixed line: the presence, as in Draw & Guess ("[Name] is waiting for your part" with the ring while the partner watches, "[Name] is here", or "[Name] will see it later").
4. Body and legs: the strip, full canvas width and 12% of its height, drawn from the part above. It sits on the same surface as the canvas, with a 1 pt dashed line along its bottom edge where the canvas starts. VoiceOver: "The bottom of [Name]'s part. Connect your drawing to its lines."
5. The square canvas. Head and body: the dashed fold line at 88% (`.paeoniaTextTertiary`, 1.5 pt, dash 6 and 4) and, just under it at the trailing edge, "[Name] only sees below this line" in `caption2`, `.paeoniaTextTertiary`. Both are drawn over the canvas and take no touches.
6. Tool rows, unchanged from Draw & Guess.
7. Pinned bottom: primary "Done", disabled while the canvas is empty. Accessibility label "Done, send to [Name]".

Toolbar trailing: the `…` menu with "Our creatures", and "Clear", with the Draw & Guess clear alert.

First figure. The first head of a new game shows one extra line under the part line in `.paeoniaTextSecondary`: "[Name] draws the body next, and only sees the bottom of yours." That line is the only teaching.

Done. `drawingSent()`, then the waiting screen with "Sent to [Name]". Offline, the part is stored on this phone and the waiting screen shows "Saved on this phone. We'll send it when you're online."

| Key | English | Norwegian |
|---|---|---|
| `name` | Odd Creatures | Rare skapninger |
| `draw.eyebrow` | Your part | Din del |
| `draw.head` / `draw.body` / `draw.legs` | Draw the head / Draw the body / Draw the legs | Tegn hodet / Tegn kroppen / Tegn beina |
| `draw.firstHint` | [Name] draws the body next, and only sees the bottom of yours. | [Name] tegner kroppen etterpå, og ser bare bunnen av din. |
| `draw.foldLabel` | [Name] only sees below this line | [Name] ser bare det under denne streken |
| `draw.strip.a11y` | The bottom of [Name]'s part. Connect your drawing to its lines. | Bunnen av delen til [Name]. Koble tegningen din til strekene. |
| `idea.ask` | Need an idea? | Trenger du en idé? |
| `idea.shuffle` | Another idea | En annen idé |
| `idea.remove` | Remove the idea | Fjern ideen |
| `idea.a11y` | Idea: %@ | Idé: %@ |
| `draw.watching` | [Name] is waiting for your part | [Name] venter på delen din |
| `draw.here` | [Name] is here | [Name] er her |
| `draw.later` | [Name] will see it later | [Name] ser den senere |
| `draw.done.a11y` | Done, send to [Name] | Ferdig, send til [Name] |

### 2. Waiting and watching

Purpose. Say whose turn it is, and when the partner draws live, let you feel it.

Async, the partner isn't drawing here.
1. Partner avatar, 96 pt, with the shared green presence ring while the partner is in the game.
2. Title: "[Name] is drawing the body" when the partner's role is `drawing`, otherwise "Waiting for [Name] to draw the body". After a figure is finished and the partner starts the next: "Waiting for [Name] to start a new creature".
3. Hint: "We'll tell you when it's your turn." In the first figure, the head drawer also sees "You'll draw the legs after that."
4. A small folded paper (72 by 216 pt) showing which parts are done: done parts as paper backs, the open part with a soft shimmer, the next part as an empty outline.
5. Toolbar: the invite bell at the leading edge of the toolbar while the partner isn't in the game.

Live, the partner is drawing: the watch screen.
1. Live row: avatar with the ring and "[Name] is drawing the head".
2. The folded paper at the size of the square, with the pen glow and the strip (see "Live").
3. Hint under it: "You'll connect to the lines below the fold."
4. When the partner taps Done: "[Name] finished the head", one pulse, then the hand-off into the drawing screen.

| Key | English | Norwegian |
|---|---|---|
| `wait.drawingNow.head` / `.body` / `.legs` | [Name] is drawing the head / body / legs | [Name] tegner hodet / kroppen / beina |
| `wait.waiting.head` / `.body` / `.legs` | Waiting for [Name] to draw the head / body / legs | Venter på at [Name] skal tegne hodet / kroppen / beina |
| `wait.newCreature` | Waiting for [Name] to start a new creature | Venter på at [Name] skal starte en ny skapning |
| `wait.hint` | We'll tell you when it's your turn. | Vi sier fra når det er din tur. |
| `wait.hintLegsNext` | You'll draw the legs after that. | Du tegner beina etter det. |
| `wait.hintLive` | You'll connect to the lines below the fold. | Du kobler deg på strekene under brettekanten. |
| `wait.finished.head` / `.body` | [Name] finished the head / body | [Name] er ferdig med hodet / kroppen |
| `wait.sent` | Sent to [Name] | Sendt til [Name] |
| `wait.opening` | Opening… | Åpner … |

The invite bell uses the shared invite copy and behavior from Draw & Guess (`docs/games/draw-and-guess.md`, phase 3).

### 3. Reveal

See "The reveal" for the beats.

| Key | English | Norwegian |
|---|---|---|
| `reveal.title` | Meet your creature | Møt skapningen deres |
| `reveal.number` | Creature %lld | Skapning %lld |
| `reveal.credit.head` / `.body` / `.legs` | Head by %@ / Body by %@ / Legs by %@ | Hode av %@ / Kropp av %@ / Bein av %@ |
| `reveal.you` | you | deg |
| `reveal.ready.a11y` | Your creature is ready. %@ | Skapningen deres er klar. %@ |
| `reveal.figure.a11y` | Creature %1$lld, drawn by you and %2$@ | Skapning %1$lld, tegnet av deg og %2$@ |
| `reveal.replay` | Play again | Spill av igjen |
| `reveal.showAll` | Show the whole figure | Vis hele figuren |
| `reveal.nextHead` | Draw the next head | Tegn neste hode |
| `reveal.continue` | Continue | Fortsett |
| `reveal.offline` | Saved on this phone. You'll both see the whole figure when it's sent. | Lagret på telefonen. Dere ser hele figuren når den er sendt. |
| `reveal.loading` | Opening… | Åpner … |

### 4. Our creatures

| Key | English | Norwegian |
|---|---|---|
| `history.title` | Our creatures | Skapningene våre |
| `history.count` | %lld creature / %lld creatures | %lld skapning / %lld skapninger |
| `history.cell.caption` | Creature %1$lld · %2$@ | Skapning %1$lld · %2$@ |
| `history.cell.a11y` | Creature %1$lld, by you and %2$@ | Skapning %1$lld, av deg og %2$@ |
| `history.cell.starred.a11y` | Creature %1$lld, by you and %2$@, starred | Skapning %1$lld, av deg og %2$@, stjernemerket |
| `history.empty.title` | No creatures yet | Ingen skapninger ennå |
| `history.empty.message` | Your creatures show up here when the legs are done. | Skapningene deres dukker opp her når beina er tegnet. |
| `history.emptyStarred.title` | No starred creatures | Ingen stjernemerkede skapninger |
| `history.emptyStarred.message` | Tap the star on a creature you like, and it shows up here. | Trykk på stjernen på en skapning du liker, så dukker den opp her. |
| `history.offline.message` | Connect to the internet to see your creatures. | Koble til internett for å se skapningene deres. |
| `history.loadMore.failed` | We couldn't load older creatures. | Vi kunne ikke laste eldre skapninger. |

The star strings are the shared favorite keys (`favorites.star`, `favorites.starred`, `favorites.privacyHint`). The filter strings reuse the Draw & Guess keys (`history.filter.*`) once they move to shared game keys.

### Hub card

The shared card frame from the foundation, with its own artwork: a strip of light paper in three parts with a dashed crease at each fold, and a pink and a blue crayon beside it, one for each partner. On first appear the parts swing open from the top one by one, and the crayon whose turn it is wiggles as its part opens. The parts show a lavender kitten's head, a blue sweater with a heart, and duck feet, drawn as outlined stickers. The raised paw, the hem and the legs cross the folds. Then a glow comes up behind the creature, it hops, waves and blinks, and two hearts pop up. It plays once, and starts finished under Reduce Motion.

| Status | English | Norwegian |
|---|---|---|
| My turn, head / body / legs | Your turn: draw the head / body / legs | Din tur: tegn hodet / kroppen / beina |
| Partner's turn | [Name] is drawing the head / body / legs | [Name] tegner hodet / kroppen / beina |
| Unseen reveal | Your creature is ready | Skapningen deres er klar |
| My legs are saved on the phone | Waiting for [Name] to start a new creature (the waiting screen's title) | Venter på at [Name] skal starte en ny skapning |
| Not started | Draw one part each without peeking. Then unfold your creature. | Tegn hver deres del uten å kikke. Brett så ut skapningen. |
| Action, my turn | Draw | Tegn |
| Action, reveal | See it | Se den |
| Action, not started | Start playing | Begynn å spille |
| Action, otherwise | Open | Åpne |
| Count chip | %lld creatures | %lld skapninger |
| History link | Our creatures | Skapningene våre |

### Wide layouts and Dynamic Type

As Draw & Guess. Wide layouts put the strip and canvas on the left and everything else in the right column. The reveal puts the figure on the left and the title, credits and button on the right. At accessibility sizes every phase scrolls with the button pinned, and the credits stack.

## iOS

Code map in `docs/implementation-map.md`. Decisions the sections above leave open:

- **Local first.** Sending a part, the reveal seen mark and a favorite go into the pending operations before anything is sent. The screen applies those queued moves on top of the server's state, so a sent part moves the turn on at once and shows "Saved on this phone" while it waits.
- **Sending a part.** One pending operation holds the canonical drawing, the strip, the idea, and the client operations for both uploads and the submit, made up front so a retry replays the same requests. The handler uploads the drawing and the strip, then calls `submit_exquisite_corpse_part`. A refused part goes back on the canvas with a notice. An upload the server deleted after a week is renewed with a new upload, as Draw & Guess does. The refusal counting and the backoff after an accepted move follow Draw & Guess.
- **Order.** A reveal seen mark waits for this person's part of that figure. A favorite waits for an earlier favorite write of the same figure and for this person's queued part of it (`ExquisiteCorpseFavoriteGate`).
- **One drawing size.** Parts and strips are stored at the canonical 320 pt side. The strip file holds the clipped strokes in the part's own coordinates (y from 281.6 to 320).
- **Hidden parts.** The phone never asks for a full part it may not read. The state says which ids it may read.
- **Drafts.** The unsent drawing and the idea chip are saved per figure and part, so a relaunch shows the same canvas and idea.
- **Role.** The open screen announces its role through the relay `hello` and changes it with the phase.
- **Presence and invite.** As Draw & Guess: `set_game_presence` every 30 seconds while the screen is open, the server counts the screen as closed 60 seconds after the last heartbeat, and one invite per 15 minutes.
- **Ids.** A figure's id and each part's id are name-based UUIDs (`ExquisiteCorpseIDs`) made from the game, the figure number, the part and the drawer. Both phones work them out alone, so a draft, its queued send and the watcher's live messages name the same part, and a draft keeps its id across launches with nothing stored.
- **The drawing surface.** On the body and legs, the strip and the canvas share one rounded surface (`ExquisiteCorpseDrawingSurface`), so the corner rounding never cuts ink where the strip meets the canvas. It repeats the few lines of `PencilKitCanvasView` wiring from `GameDrawingCanvas`, so change both together. The canvas view reaches over the strip (`overscanTop`). PencilKit draws no ink above its content's y 0, so `OverscanCanvasView` holds the drawing moved down by the strip's height, and its `drawing` and `drawingLocation(of:)` move it back for every caller.
- **The relay never sees the canvas.** The game uses `WidgetLiveDrawing` for presence and roles only. Its `currentDrawing` answers an empty drawing, and the canvas is never attached, so no relay stroke message can carry the hidden part. A drawer whose part waits in the queue keeps the `drawing` role, and a watcher who got `done` keeps the folded paper, until the server moves the turn.
- **Refusals and other phones.** A part the server refuses with a bad argument (22023) is dropped at once and goes back on the canvas with a notice. A refused idea also clears the chip, so the restored canvas can be sent again. A duplicate (23505) means another send took the part, such as the same turn sent from this person's other phone, so it comes back the same way. A canvas the turn leaves without a send from this phone is kept as its draft. An empty canvas takes the oldest draft of this person's earlier parts in the latest 50 figures, found by their part ids, so no drawing is ever out of reach, also after a relaunch or a privacy purge that keeps drafts. A favorite waits for a queued part of the same figure, because the server takes one only on a finished figure.
- **Shared code.** The canvas, the replay, the square, the layout, the bloom, the avatars, the favorite star, the thumbnails and the upload are shared with Draw & Guess in `Features/Games/Shared/` (map in `docs/implementation-map.md`).

## Decisions made without the developer

Made on 2026-10-14 while the developer was away. Each can change after review.

- **Copy for states the doc didn't cover.** The hub says "Draw one part each without peeking. Then unfold your creature." with "Start playing" before the first figure, and the waiting screen's "Waiting for [Name] to start a new creature" while this person's legs wait to be sent. Watching the legs live, the paper covers the whole square (the legs leave no strip) and the hint says "You'll both see the whole creature when the legs are done."
- **Generic strings moved to shared keys.** "Choose how you play in the Games tab first." and "We couldn't send your move yet" with its message are `games.needsSetup` and `games.waitingToSync.*`, used by both games with the same text. The clear alert and the drawing loading label moved the same way.
- **Push steps.** The turn push's `step` is the part that is now the partner's turn (`body` or `legs`).
- **Ideas.** 50 hand-written ideas per part per language, dealt as a deck of 12 per part. Both lists still need the developer's read (see "Open questions").
- **Reveal details.** The fold flaps swing away from the viewer. "Opening…" sits on the middle fold while the drawings load. A press counts as a hold after 0.2 seconds, and a hold carries over into the next part. The title and credits sit under the figure. There is no "hold to speed up" hint, unlike the Draw & Guess replay.
- **Reactions.** Either partner can put one emoji on a finished figure, on the reveal (under the credits) and on the detail screen in "Our creatures". The emoji of both partners shows on the grid cell. They work like every reaction (`docs/implementation-map.md`, "Reactions"): kind `exquisite_corpse_figure`, one gentle push for a first reaction, no queue. The reveal appears only for a figure the server finished, so the row never meets a refusal. (Decided on 2026-10-21.)
- **Not built.** No records in "Our creatures". The game has no scores, and stars cover finding a figure again.

## Open questions

- The idea lists need a native speaker's read before release. Drafts are in `backend/convex/lib/exquisiteCorpseIdeas.ts`.
