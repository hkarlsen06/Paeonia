# Draw & Guess

Design for the first game. Nothing is built yet. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Draw & Guess.

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

The drawer chooses one of three words: easy, medium, or hard. Harder words score more points. A fourth choice is "Draw your own", where the drawer types any word or short phrase. That is how a couple uses inside jokes ("the dog at your mom's house").

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
- Attempts are unlimited. A "Show me" button reveals the answer, and the round counts as missed.
- Every attempt is saved in Convex with a timestamp. In a live round the drawer sees each wrong guess appear while drawing. In an async round the drawer watches the guesses in order afterward ("They tried CAT, then HAT..."). That is the drawer's payoff for the turn.

## Live

Live runs whenever both partners have the game screen open. Without the partner there, everything works as an async round. Nothing about the round changes except how fast each side sees the other.

- **Presence.** While the game screen is open, the phone joins the game's relay room. The relay's `welcome`, `joined` and `left` messages tell each phone whether the partner is there. Reuse `WidgetLivePresence`. The drawer sees "[Name] is watching". A waiting partner sees "[Name] is drawing for you".
- **Strokes.** The drawer's strokes stream over the relay as in `WidgetLiveMessage` and play on the guesser's screen through `WidgetLivePlayback`.
- **Joining late.** A guesser who opens the game mid-drawing asks for a snapshot with `hello`, as `WidgetLiveRoom` does. The strokes so far play back quickly, then live strokes follow.
- **Guesses.** Guesses go through Convex, because they are saved anyway. The drawer's live query shows them within a few hundred milliseconds.
- **A correct guess** ends the round right away. The drawer's phone sends the drawing as it is at that moment, and both phones show the reveal together. The roles then swap. The new drawer picks a word while the other partner stays to watch, so two partners who are both online can play back and forth without leaving the screen.
- **The drawer taps Done before a correct guess.** The round continues as a normal round, and the guesser keeps guessing on the finished drawing.
- **Lost connection.** The drawer keeps drawing and the drawing still sends on Done. The guesser's phone reconnects and asks for a fresh snapshot. The relay closes sockets after 10 minutes (`SESSION_MS`), so the same reconnect path runs during long rounds without the players noticing.
- **Invite.** When the partner isn't in the game, either partner can tap "Tell [Name] you want to play" (see `docs/games-plan.md`). The push opens Draw & Guess directly, so the partner lands in the live round.
- **Relay room.** The game needs its own room so it doesn't share the 4-socket cap with Home and the widget canvas. This is the relay channel change in `docs/games-plan.md`, and the first version needs it.

## Scoring

The play style is a couple setting (see `docs/games-plan.md`).

**Together.** One shared score. Each correct guess adds the word's points to the couple's total. A missed round adds nothing and takes nothing away.

**Against each other.** Each partner has their own score. A correct guess gives the guesser the word's points plus a speed bonus. The drawer gets the word's points when the guess is right. Both partners draw and guess equally often, so the difference between the totals comes down to how fast and how well each one plays.

In both styles the scores keep growing and never reset.

## Streak

Draw & Guess counts toward the couple's existing streak through a new game activity kind in `ACTIVITY_KINDS` (`backend/convex/lib/streaks.ts`). Proposal: sending a drawing counts, with the round id as the dedupe key. Guessing alone doesn't count, because the turn isn't done until you draw back.

## Save to Memories

After the reveal, both partners can save the drawing to Memories. The guesser sees the prompt at the reveal. In a live round the drawer sees it at the same moment. In an async round the drawer sees it the next time they open the game. If either one says yes, the drawing is saved as a memory with the word as its title. Nothing is saved without a yes, and the game never saves on its own.

## Word lists

- Each language has its own list, written by hand. Norwegian is not a translation of English. It can include Norwegian things like brunost or a fjord.
- Every word must be drawable and must make sense to a 16-year-old.
- Start with about 300 words per language, split across easy, medium and hard.
- Words live in the backend, like the question catalog in `backend/questions/`, so the list can grow without an app update.

## Data

This builds on the shared model in `docs/games-plan.md`.

- One `games` row per couple with `kind = "draw_and_guess"`.
- One `game_moves` row per round. It holds the word (or the custom word), the difficulty, the drawing as `pkdrawing` media, the guess attempts with timestamps, and the result.
- The guesser's phone receives the word when the round starts, because it builds the tiles and checks guesses locally for instant feedback. The UI never shows the word before the reveal. Cheating isn't a real risk between partners, so the server doesn't hide the word.
- A turn drawn offline is saved on the phone and sent when the phone is back online. The UI tells the drawer: "Saved on this phone. We'll send it when you're online."
- Used words are tracked per couple, so suggestions don't repeat.

## Notifications

- "Your turn in Draw & Guess" when a drawing arrives.
- "[Name] guessed your drawing" when the partner gets it right.
- Never show the word or the drawing on the lock screen.
- Skip both pushes when the partner has the game screen open, because they already see it live. Convex can't see relay presence, so the game screen also keeps a presence row in Convex while it is open, the same way `chatPresence.ts` tracks open chats.

## Open questions

- Point values for each difficulty, and how big the speed bonus is in "Against each other".
- How long a custom word can be, and which characters it allows.
- How a pixel eraser affects replay. It splits strokes, so check that the pieces keep their timing.
- Which media bucket stores game drawings.
- Accessibility. Tiles must work with VoiceOver. The drawing has no text version until the reveal.
