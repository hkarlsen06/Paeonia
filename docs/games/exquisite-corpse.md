# Odd Creatures (exquisite corpse)

Design for the second drawing game. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. Draw & Guess (`docs/games/draw-and-guess.md`) sets the bar and owns the drawing canvas, the replay and the history this game reuses. This file covers only what is specific to Exquisite corpse.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

- **The name is "Odd Creatures".** Norwegian "Rare skapninger". The game is known as exquisite corpse, and the code uses the kind `exquisite_corpse` and the Swift prefix `ExquisiteCorpse`.
- **Four parts, and each partner draws two.** A figure is a head, a body, legs and feet. The partner who starts a figure draws its head and its legs, and the other partner draws the body and the feet. Every part passes the turn to the other partner except the feet. The feet drawer keeps the turn and starts the next figure with its head. So the roles swap with every figure. (Changed on 2026-11-14. With three parts the starter drew twice as much as the partner.)
- **The strip is 12% of a part.** The next drawer sees the bottom 12% of the part before, 38 pt of the 320 pt square. Nothing else of it.
- **Ideas are optional.** The toolbar says "Draw the head". A centered button with a light bulb and question mark above the canvas deals a hand-written idea in the couple's game language. The idea shows as a chip with Shuffle and a remove button. Whatever chip shows when the drawer taps Done is saved with the part, stays hidden from the partner, and becomes the part's caption at the reveal.
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

- A figure has four parts in this order: head (0), body (1), legs (2) and feet (3).
- Each part is drawn on the Draw & Guess square, stored at the canonical 320 pt side (`GameCanvas.canonicalSide`). The figure is the four squares stacked with no gap, 320 by 1280.
- The partner who starts a figure (the starter) draws the head and the legs. The other partner draws the body and the feet.
- The turn passes to the other partner after the head, the body and the legs. After the feet the feet drawer keeps the turn and draws the next figure's head, so the next figure starts with the partner who drew the feet. The server holds the rule in `progressAfter` (`backend/convex/lib/exquisiteCorpse.ts`). The phone needs it only to say who starts the next figure, in `RemoteExquisiteCorpseFigure.startsNextFigure`.
- The person who creates the couple's game starts the first figure.
- The game never ends. A couple has one figure in progress at a time, and every finished figure goes to "Our creatures".

## The fold

- **What the next drawer sees.** The strip is the bottom 12% of the part before (`ExquisiteCorpseFold.stripFraction = 0.12`). It shows right above the next drawer's canvas, at the same scale, so a line that ends at the bottom edge of the head continues at the top edge of the body. In the finished figure the parts touch at exactly that edge.
- **What the drawer above is told.** The head, body and legs canvases show a dashed fold line at 88% of their height. Under it, a small label: "[Name] only sees below this line". The feet canvas has no fold line, because nobody draws after it.
- **Drawing from the strip.** The canvas also lies over the strip, so a line can start on the strip and run down into the canvas. Ink drawn on the strip lies above the part's square, so the finished figure and the history cut it off.
- **The legs and feet drawers** see only the strip of the part above. Their own earlier part stays folded away, as on paper.
- **The strip leaves the phone on its own.** When the drawer taps Done, the phone clips the drawing to the strip and uploads it as a separate file, next to the full part. The server lets the partner read the strip at once, and the full part only once the figure is finished. So the hidden part of a drawing never reaches the partner's phone before the reveal, also not through a cache or a crafted request.
- **Clipping.** A stroke that is only above the fold is left out. A stroke that crosses the fold keeps the points below it, plus one point on the fold line where it crosses, so its line starts exactly at the fold. A stroke inside the strip is kept whole. Ink, width and transform are kept. Erased ink is clipped the same way, so the strip never shows erased ink (`PKStroke.mask`, as in the Draw & Guess replay).

## Ideas

- The drawing screen uses "Draw the head" (or body, legs, feet) as its toolbar title. The light bulb and question mark sit centered above the canvas. There is no "Your part" label.
- Tapping it shows an idea chip, such as "a grandma", with a Shuffle button (`shuffle`) and a remove button (`xmark`). Shuffle deals the next idea. Remove clears the chip and brings back the light bulb button.
- The chip that shows when the drawer taps Done is saved with the part. It is hidden from the partner until the figure is finished. At the reveal and in "Our creatures", each part shows its idea under the drawer's name. A part without an idea shows only the name.
- Most ideas are noun phrases that fit any part: "a robot" as the head, the body or the legs. Each part has its own list, because some ideas only work as one part (a spider's legs, a teapot body). The feet list is mostly feet and footwear, such as "duck feet", "roller skates" or "a mermaid's tail fin".
- The server deals the ideas. While it is this person's turn, the game state carries a deck of 12 ideas for the next part in the couple's game language, shuffled with the part as the seed, so reopening the game deals the same deck. Shuffle walks through the deck and starts over at the end. The deck is cached with the state, so ideas work offline.
- A part sent with an idea stores the idea's id and its text. Later edits to the list don't change finished figures.
- When the couple changes the game language, the next deck comes in the new language. A part already sent keeps its idea.
- Each language has its own hand-written list in `backend/convex/lib/exquisiteCorpseIdeas.ts`, about 50 ideas per part. Norwegian is not a translation of English and can use Norwegian things like a troll, an elk or a nisse. Every idea must be drawable and make sense to a 16-year-old. A native speaker reads every idea before it ships, with the same check as the Draw & Guess word lists: no slurs, no crude second meanings, no words most people don't know.

## Drawing

- The Draw & Guess canvas, unchanged: PencilKit with the widget tools, colors, sizes, paint bucket, undo, redo and Clear (`GameDrawingBoard`).
- No time limit. Done sends the part. Done is disabled while the canvas has no strokes.
- The drawer's unsent drawing is saved on the phone as they draw, so leaving the screen or closing the app loses nothing (`GameDrawingStoring`, as Draw & Guess drafts).
- The part is stored at the canonical side, so it looks the same on both phones and in the figure.
- A faint dashed outline of the part sits behind the ink as a guide. It is a round head with a short neck, a body with shoulders, arms and hips, two legs, or two feet that point outward. The outlines meet at the same places on every fold, the neck between the head and the body, the hips between the body and the legs, and the ankles between the legs and the feet, so a line drawn along the guide continues in the next part. The guide is only on the drawer's screen. It is never part of the drawing, so the strip, the live messages, the reveal, the history and the thumbnails never show it. It takes no touches and VoiceOver skips it (`ExquisiteCorpseBodyGuide`, 1.5 pt dashed, dash 6 and 4, `.paeoniaTextTertiary` at 0.45 opacity).

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
- **The live reveal.** When the feet are done live, both phones open the reveal as soon as they have all four parts. Each phone waits for the server to finish the figure and then downloads the parts it lacks, which takes about a second. Until then both show the folded paper with "Opening…" and a slow shimmer.
- **Invite.** The waiting screen has the shared "Tell [Name] you want to play" button while the partner isn't in the game (`docs/games-plan.md`). The push opens Exquisite corpse directly.

## The reveal

Purpose. The best ten seconds of the game. Neither partner has seen the whole figure.

Who sees it when.
- The feet drawer sees the reveal right after Done, once the server has the part. Offline, the phone keeps the part and the folded figure waits for the upload without a save-status line.
- The partner sees it the next time they open the game, or at once when they watch live.
- A figure's reveal shows until this person taps Continue. The server keeps a "reveal seen" time for each partner, so a second phone or a fresh install doesn't show it again. Like Draw & Guess, the latest unseen reveal comes before a new turn.
- Once the unfolding finishes or is skipped, reopening shows the finished creature and its buttons at once. Reduce Motion counts as shown too. The phone keeps this separately from Continue, so watching the reveal does not start the next turn. Leaving during the unfolding does not mark it finished.

Beats, in seconds from the start. The later times assume each part plays for the full 2.5 s. Shorter parts move everything after them earlier.

| Time | What happens |
|---|---|
| 0.00 | The folded paper sits in the middle. The four parts are folded like an accordion with only the paper's back showing. `selection()`. The screen fades in over the first 0.36 s, so the paper rests about half a second before anything moves. |
| 0.80 | The top fold opens (`rotation3DEffect` around its top edge, `meaningfulMoment`). The fold sound starts 0.1 s before the fold lands, so its knock lands with it. One `streakTick` at 0.4 as the fold lands, at 1.16. The head replays its strokes at the drawn pace, squeezed to at most 2.5 s. Under it: the drawer's avatar (24 pt) and "Head by Robin", plus the idea in `.paeoniaTextSecondary` if the part has one. |
| about 4.0 | 0.3 s after the head's replay, the second fold opens below the head, and the view eases down to frame it. The body replays. `streakTick` at 0.55. |
| about 7.1 | The third fold opens and the legs replay. `streakTick` at 0.7. |
| about 10.3 | The fourth fold opens and the feet replay. `streakTick` at 0.85. |
| about 13.6 | The finished feet hold for 0.5 s, then the view zooms out to the whole figure (`celebrationReveal`). 0.3 s into the zoom, as it settles: `answerRevealed()`, a petal bloom from behind the middle of the figure (`GamePetalBloom`, seeded by the figure id) and a soft radial glow centered on it. |
| about 14.5 | The title fades up, "Meet your creature", with "Creature 12" under it. The credits show who drew which parts, with the avatars. The primary button appears. |

- When a fold opens, the caption of the part before fades out in 0.16 s, and the new caption fades in after it with a 6 pt rise, so two names never show on top of each other.

- Each part plays its strokes in drawn order through `GameReplayTimeline` and `GameReplayClock`, with long pauses shortened as in Draw & Guess. A part that took longer than 2.5 s plays faster to fit (`rate = duration / 2.5`). A short part plays at its own pace.
- Holding anywhere on the figure plays at 4x, with a `forward.fill` glyph and `selection()` once.
- A tap on the screen jumps to the settled state, as `PairingCelebrationTimeline.skip` does, without repeating haptics.
- The reveal runs on `ExquisiteCorpseRevealTimeline`, built like `DrawAndGuessRevealTimeline`: a run id, an injected schedule and injected haptics, so tests can run it fast.
- Reduce Motion. No 3D folds, camera moves, bloom or glow. The whole figure shows at once, settled, with `answerRevealed()`. A "Play again" button plays the strokes on request, part by part, without the folds.
- VoiceOver. On the settled state, one announcement: "Your creature is ready. Head by Robin, a grandma. Body by you. Legs by Robin. Feet by you." The figure is one element, "Creature 12, drawn by you and Robin", with the actions "Play again" and "Show the whole figure". The bloom and glow are hidden.
- The figure fits the screen at the end: the side of a part is the smaller of the width and a quarter of the height left for it. While a part plays, the view frames it larger (up to 55% of the height) and the parts above slide up.

Settled state, top to bottom.
1. The figure, centered, with a 2 pt hairline between parts in `.paeoniaTextTertiary` at 0.3 opacity, so the folds stay readable.
2. Title "Meet your creature" (`heroTitle`) and "Creature 12" (`caption`, `.paeoniaTextSecondary`).
3. Credits. One per drawer, the avatar followed by the parts, "Head and legs" for the starter and "Body and feet" for the partner (see "3. Reveal"). Avatars tinted `.paeoniaPartnerOne` for me and `.paeoniaPartnerTwo` for the partner.
4. Pinned bottom: the primary button. "Draw the next head" when the next figure starts with me, which is when I drew the feet, otherwise "Continue". It queues the reveal seen mark and moves on at once.

Star. The shared favorite star (`FavoriteStarButton`, `star`, `star.fill`, `selection()`), next to an "Our creatures" button. The first favorite on a phone shows the banner "Only you can see your favorites." once (`FavoritesStore`).

## Our creatures

The history of finished figures. It follows "Our drawings" in look and behavior (`docs/games/draw-and-guess.md`, "8. Our drawings"), with these differences.

- No records section. The game has no scores.
- The header shows the count: "12 creatures" (`sectionTitle`).
- The grid uses adaptive columns of at least 76 pt, which gives 4 columns on a phone 393 pt wide or wider. A cell is the whole figure as a 1:4 thumbnail on `.paeoniaBackgroundPrimary` (`radius12`), with "Creature 12" and "Oct 12" on two lines under it in `caption`. A `star.fill` badge sits at the top trailing corner when I starred it.
- A page is 30 figures, newest first, with All and Starred. Paging, caching, offline and empty states work as in "Our drawings".
- The detail screen shows the figure with the credits and plays the reveal's unfold without the bloom, once. "Play again" starts it over. The toolbar star toggles my private favorite.
- Entry points: "Our creatures" in the `…` toolbar menu on the game screen, a long press on the hub card or tile, and a quiet link on the hub card once a figure is finished.

VoiceOver. A cell is one element, "Creature 12, by you and Robin, starred". The detail figure reads like the reveal's figure.

## Streak

Sending a part counts toward the couple's streak as `game_turn_completed`, with the part id as the dedupe key. Every turn is one part, so each partner keeps the streak alive by drawing their part.

## Notifications

- Turn: title "Robin drew the head", body "Your turn to draw the body." After the body: "Robin drew the body", "Your turn to draw the legs." After the legs: "Robin drew the legs", "Your turn to draw the feet." Sent when a head, body or legs arrives, and not sent when the partner has the game open. The push carries `step: "body"`, `step: "legs"` or `step: "feet"`, the part that is now the partner's turn, and the copy for each step is in `GAME_PUSH_COPY` (`lib/notificationCopy.ts`).
- Finished: title "Robin finished your creature", body "See the whole creature." Sent to the partner of the feet drawer when the feet arrive, and not sent when the partner has the game open.
- A new figure needs no push of its own. The feet drawer keeps the turn and sees the reveal right after Done. Their partner gets the finished push, and the usual turn push once the next head arrives.
- Reminder: "Your turn in Odd Creatures", once, when a turn has waited 72 hours.
- Invite: the shared "[Name] wants to play Odd Creatures with you".
- The lock screen never shows a drawing or an idea. The payload holds only ids, the step and the deep link `paeonia://games/exquisite-corpse`.
- The drain drops a turn push once the turn has moved on, and a finished push once the recipient has seen the reveal.

| Push | Title (English / Norwegian) | Body (English / Norwegian) |
|---|---|---|
| Turn, head done | %@ drew the head / %@ har tegnet hodet | Your turn to draw the body. / Din tur til å tegne kroppen. |
| Turn, body done | %@ drew the body / %@ har tegnet kroppen | Your turn to draw the legs. / Din tur til å tegne beina. |
| Turn, legs done | %@ drew the legs / %@ har tegnet beina | Your turn to draw the feet. / Din tur til å tegne føttene. |
| Finished | %@ finished your creature / %@ gjorde ferdig skapningen deres | See the whole creature. / Se hele skapningen. |
| Reminder | Your turn in Odd Creatures / Din tur i Rare skapninger | Pick up where you left off. / Fortsett der dere slapp. |
| Invite | %@ wants to play Odd Creatures with you / %@ vil spille Rare skapninger med deg | The shared invite body |

## Decisions made without the developer

Made on 2026-10-14 while the developer was away. Each can change after review.

- **Copy for states the doc didn't cover.** The hub says "Draw one part each without peeking. Then unfold your creature." with "Start playing" before the first figure. Watching the feet live, the paper covers the whole square (the feet leave no strip) and the hint says "You'll both see the whole creature when the feet are done."
- **Generic strings moved to shared keys.** "Choose how you play in the Games tab first." and "We couldn't send your move yet" with its message are `games.needsSetup` and `games.waitingToSync.*`, used by both games with the same text. The clear alert and the drawing loading label moved the same way.
- **Push steps.** The turn push's `step` is the part that is now the partner's turn (`body`, `legs` or `feet`).
- **Ideas.** 50 hand-written ideas per part per language, dealt as a deck of 12 per part. Both lists still need the developer's read (see "Open questions").
- **Reveal details.** The fold flaps swing away from the viewer. "Opening…" sits on the middle fold while the drawings load. A press counts as a hold after 0.2 seconds, and a hold carries over into the next part. The title and credits sit under the figure. There is no "hold to speed up" hint, unlike the Draw & Guess replay.
- **Reactions.** Either partner can put one emoji on a finished figure, on the reveal (under the credits) and on the detail screen in "Our creatures". The emoji of both partners shows on the grid cell. They work like every reaction (`docs/implementation-map.md`, "Reactions"): kind `exquisite_corpse_figure`, one gentle push for a first reaction, no queue. The reveal appears only for a figure the server finished, so the row never meets a refusal. (Decided on 2026-10-21.)
- **Not built.** No records in "Our creatures". The game has no scores, and stars cover finding a figure again.

Made on 2026-11-14 with the change to four parts.

- **The hub while the feet wait on the phone.** It says "Your creature is almost ready" with "Open". The partner no longer starts the next figure, so "Waiting for [Name] to start a new creature" stopped being true for this state.
- **A second first-figure hint.** The body drawer of the first figure also sees "You'll draw the feet after that.", like the head drawer's hint about the legs.
- **Feet ideas.** The feet lists are new. Ideas in the legs lists that were really about feet or shoes (a roller skater, a skier, a diver with flippers, a snowboarder, a skateboarder, a sled, a kick sled) moved to the feet lists, and each legs list got five new leg ideas so it keeps 50.
- **Sizes.** "Our creatures" columns are at least 76 pt, and the shared picture's parts are 200 pt instead of 232 pt, so a four-part creature is not much taller than a three-part one was.

## Open questions

- The idea lists need a native speaker's read before release. Drafts are in `backend/convex/lib/exquisiteCorpseIdeas.ts`.
- The illustrated hub strip (`GameHubExquisiteCorpseStrip`) still shows three panels, a kitten's head, a sweater and duck feet. It needs a four-panel picture with legs, made with the `paeonia-illustrations` skill.
