# Consensio

Design for the ninth game. One partner puts a marker where they honestly stand on a line between two ends, such as how they feel about camping. The other partner guesses where it went, from how well they know them. The reveal shows both markers on the line and scores how close the guess came. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Consensio.

The name is Consensio in both languages, Latin for harmony or shared agreement.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided by the developer on 2026-10-18.

- **The idea.** A partner gets a topic and a line between two ends, places their own marker where they honestly stand, and the other partner guesses where it is. The placer picks the spot. The reveal of the real spot is the high point of every round.
- **Name.** Consensio, in both languages. It is Latin for harmony, accord or shared agreement.
- **Async first.** The guesser may answer hours later in another time zone.
- **Paeonia's own game.** The rules of the party game it comes from can be reused, nothing else. The game never uses that game's name, its dial, its colors or its cards. It has no dial at all. Every topic and pair of ends is written by hand in English and in Norwegian Bokmål. Neither list is a translation of the other, and no topic is taken from a published card set.
- **Always together.** Consensio ignores the play style setting and keeps one shared score. In "against each other" only the guesser could score, so the placer's best move would be to put the marker where the partner won't look. Nobody can check an honest answer. Together, both want the guess to land, so honesty is the winning move. Each partner's record as a guesser still shows in "What we know", without a winner.
- **Points by distance.** 5, 4, 3, 2, 1 or 0, one point less for every 4 percent the guess is off (see "Scoring").
- **The Draw & Guess loop.** A turn is "guess, see the reveal, then place yours". The partner who opens the game first starts by placing.
- **It never ends.** One ongoing game per couple, and the score grows forever.
- **Live play ships in the first version.** The placer watches the partner's guess marker move along the line. The relay carries only the guess, never the real spot. The placer could coach out loud on a call. That is fine, because both win together.
- **The marker is each partner's drawn mark**, the one they drew for the board games, on the head of a small pin. Without a drawn mark the pin shows the first letter of the name.
- **Topics.** The placer picks one of three topics from the couple's game language, or writes their own subject and two ends. Only the picked topic counts as used. 150 topics per language, kept in the backend.
- **History.** "What we know" keeps every revealed round, newest first, with each partner's spot-ons and average distance at the top. No stars.
- **The clue mode is not part of this game.** A way to play where one partner gives a clue for a hidden spot may come later, only if the developer asks for it.

Agreed with the developer on 2026-10-18, first proposed by the agent:

- **The real spot stays on the server until the guess.** The guesser's phone never holds it, so the reveal needs one answer from the server. An offline guess is kept on the phone and plays its reveal when the phone is back online.
- **The marker starts in the middle.** It stands on the line from the start, so it is clear what to drag. A marker that only appeared on the first touch left people unsure what to do. The developer chose this on 2026-10-18, knowing a default spot can pull answers toward the middle.
- **A placed marker is final.** Once locked, it can't move.
- **How to play cards.** Three cards, because "put it where you stand, your partner guesses" is not obvious from the first screen.
- **Placing counts toward the streak.** Guessing alone does not, because the turn isn't done until you place yours.
- **The ends keep the order they were written in.** Lists mix which side is the "yes" side, so neither side reads as the right answer.
- **Catalog order.** Right after Mind Meld, the other game about thinking alike.
- **One push for a guess and a placement.** The result push waits 5 minutes. A placement inside that window sends one push that covers both.

## Why this game

- It works across time zones. A turn takes under a minute, and the reveal waits as long as it needs to.
- It is about the couple. Every round answers how well one knows the other, and every reveal teaches one small thing. Quality bar item 3 asks for a game that uses what only Paeonia has, and the couple's knowledge of each other is the clearest case.
- The rules fit in one sentence, so the first turn teaches by playing.

## The round

A couple has one ongoing Consensio game. A round has a placer and a guesser.

1. **Pick a topic.** The placer sees three topics, each with its two ends, and a fourth row, "Write your own". Picking one and tapping "Start" opens the line.
2. **Place.** The placer drags the marker to where they honestly stand and taps "Lock it in". The round goes to the partner.
3. **Guess.** The guesser sees the same topic and ends, and the line without the placer's marker. They touch the line where they think the partner is and tap "Lock in my guess".
4. **Reveal.** The real spot appears next to the guess, and the points land.
5. **Your turn to place.** The guesser picks a topic and places their own marker. That is the next round.

The very first turn of a new game skips the guess and starts at "Pick a topic".

### Who acts

- The game's `turn_user_id` is the partner who acts next. While a round waits for a guess, it is the guesser. After the guess, it stays the same person, now as the next placer.
- The partner who isn't acting sees the waiting screen. While the other partner picks and places, it says "[Name] is picking a topic" (see "Waiting").
- A partner can see an unseen reveal at any time, whoever's turn it is.
- Both partners opening a new game at once is safe. `ensure_consensio_game` returns the game that already exists, so the second partner lands on the waiting screen.

### The line

- Positions are whole numbers from 0 (the left end) to 100 (the right end). The phone never shows a number on the line. Distances show as a percent of the line (see "Reveal").
- The marker starts in the middle. A drag anywhere on the line moves it by as far as the finger moves, so it never jumps to the finger. Lifting the finger leaves it there.
- For VoiceOver and Switch Control the line is one adjustable element, and swiping moves the marker from the middle.

### Topics

- A topic has a subject and two ends, written for each language. For example, "Camping", from "Never again" to "Book it now".
- The subject is a thing, a habit or a small situation, never a question in the first person. The screen asks the question in Paeonia's voice: "Where are you on this?" for the placer and "Where is [Name] on this?" for the guesser. So no topic can sound as if the partner wrote it, which `docs/couple-question-guidelines.md` requires.
- The three choices are fixed when they are made. The server makes the next placer's three choices when a round opens for a guess, so the guesser has them on the phone before they guess. A guess and the next placement can then both be made offline. The server picks them from the couple's game language, among topics not yet used. Only the topic that gets placed counts as used. When fewer than three are left, the language starts over.
- A language change replaces the three choices. A placement queued with an older choice still works, because the server takes any topic id in its catalogs and stores the subject and ends on the round. A later edit to the catalog never changes an old round.
- To write your own, the placer gives a subject of 2 to 60 characters and two ends of 1 to 24 characters each, different from each other. Letters, digits, spaces and common punctuation are allowed. Line breaks and runs of spaces become one space.

### Writing topics

The topics follow `docs/couple-question-guidelines.md`. Paeonia writes them, they never sound like the partner wrote them, and they are warm and playful.

- Good subjects are tastes, habits and small preferences with a real range. Spicy food, mornings, surprise parties, rewatching a favorite series, getting lost on purpose, dancing in public, cold showers, a whole day with no plans.
- Ends name the two far sides of one feeling, in plain words a 16-year-old uses. Each fits on two short lines under its end of the line. Both ends are fine places to be.
- Topics stay away from the relationship itself (how much you miss them, how jealous you get), exes, money, bodies and looks, sex, religion, politics, family conflict and health. They also skip anything where a far guess could hurt. "How tidy is [Name]?" is a fight waiting to happen. No topic assumes gender, living together, marriage, children or a holiday.
- Each language has its own list. Norwegian can have brunost, hyttetur and fårikål. A topic may be in both lists when it is natural in both, written fresh each time.
- Ends are shown inside sentences on the reveal ("closer to never again"), so each end is written to read well in the middle of a sentence too. The phone lowercases the first letter there, except for names and the Norwegian nouns that need it.
- A test checks the lists: lengths, no duplicate subjects in a language, unique ids, and a list of banned words. A native speaker reads every topic before it ships, as with the Draw & Guess words.

## Scoring

Consensio always plays together and ignores the play style setting (see "Decisions"). The distance is the difference between the guess and the real spot, 0 to 100.

| Distance | Points | Verdict |
|---|---|---|
| 0 to 3 | 5 | Spot on |
| 4 to 7 | 4 | So close |
| 8 to 11 | 3 | So close |
| 12 to 15 | 2 | Close |
| 16 to 19 | 1 | Close |
| 20 or more | 0 | Now you know more |

Points are `max(0, 5 - floor(distance / 4))`. Each guess adds its points to the couple's shared total. A guess in the middle every time (50) averages about 1.1 points against spots spread evenly over the line, and a guess from real knowledge beats it. There are no bands drawn on the line, and the reveal never shows a target zone.

The total grows forever, like scores in other games. The server keeps it whatever the play style.

## Live

Live runs whenever both partners have the game open. Without the partner there, everything works as async play. Nothing about the round changes except how fast each side sees the other.

- **Presence and roles.** While the screen is open, the phone joins the `consensio` relay room and says `hello` with one of the shared roles: `choosing` on the topic list and while placing, `watching` while guessing, `result` on a reveal, and `present` anywhere else in the game. The partner's phone reads them as "picking a topic", "guessing" and "looking at the result". The Convex presence heartbeat runs next to it for push suppression.
- **The guess, live.** `ConsensioLiveMessage` has three fields: `roundID`, `position` (0 to 100, or none before the marker is placed) and `touching`. The guessing phone sends it at most 15 times a second while the finger moves, once when the finger lifts, and again when the placer arrives. The placer's waiting screen shows that marker moving on the line. Nothing in it is saved.
- **The real spot never goes over the relay.** No message type the relay can carry has a field for it, and the placing phone sends nothing about its marker. A test checks the message type.
- **The reveal.** The guess goes to Convex. The guesser's phone opens the reveal at once and plays it as soon as the server answers with the real spot. The placer's phone plays it when the live feed delivers the guessed round, usually within 300 ms.
- **Lost connection.** The relay reconnects as in Draw & Guess. The live marker on the placer's screen fades out, and the status falls back to the async wording until the relay is back.
- **Invite.** The bell at the leading edge of the toolbar, with the shared invite rules in `docs/games-plan.md`.

## Async

- The placer locks in and can leave. The guesser gets the turn push.
- The guesser locks in a guess and sees the reveal at once. The placer gets the result push (see "Notifications") and sees the reveal the next time they open the game.
- The placer may not open the game until the guesser has already placed the next marker. The game then shows the unseen reveal first, then "Your turn to guess".
- A guess made offline is saved on the phone. The guesser can leave the held reveal, place the next marker from the choices already on the phone, and leave. Both moves go out in order when the phone is online, and the reveal plays the next time the game opens.
- The server keeps when each partner first saw each reveal, so a second phone or a fresh install never plays an old reveal again.
- A turn that waits 72 hours gets one reminder, both when it waits for a guess and when it waits for a placement.

## Streak

Placing a marker counts toward the couple's streak through the `game_turn_completed` activity kind. The dedupe key is `game_turn_completed:<round id>:<user id>`.

## Notifications

`GAME_PUSH_COPY.consensio` in `lib/notificationCopy.ts`.

| Push kind | When | Title | Body |
|---|---|---|---|
| `game_turn_ready` | The partner locked in a marker. | Your turn in Consensio / Din tur i Consensio | Open Paeonia to make your guess. / Åpne Paeonia for å gjette. |
| `game_turn_ready`, step `guessed` | The partner guessed your marker and then placed one for you within 5 minutes. | [Name] guessed and placed one for you / [Name] har gjettet og satt en brikke til deg | Open Paeonia to see how close they got. / Åpne Paeonia for å se hvor nær gjetningen var. |
| `game_result` | The partner guessed your marker and placed nothing for 5 minutes. Goes to the placer. | [Name] made a guess / [Name] har gjettet | Open Paeonia to see how close they got. / Åpne Paeonia for å se hvor nær gjetningen var. |
| `game_invite` | Invite bell. | [Name] wants to play Consensio with you / [Name] vil spille Consensio med deg | Shared invite body. |
| `game_turn_reminder` | The turn waited 72 hours. Once per turn. | Your turn in Consensio / Din tur i Consensio | Shared reminder body. |

- A guess queues the result push 5 minutes ahead (`enqueueGamePush` gets an optional delay, a small addition to the shared helper). A guesser almost always places the next marker in the same sitting, so the placer usually gets one push, not two. When the next placement comes first, it sends the `guessed` step and the drain drops the waiting result push.
- Never show the topic, a position or the points. The push payload holds only ids and the deep link `paeonia://games/consensio`.
- Skip the turn and result pushes while the recipient has the game open.
- `pushStillWanted` drops a turn push or a reminder once the turn has moved on, and a result push once the placer has seen the reveal, has the game open, or the next round was placed. The result push waits 5 minutes, so the drain checks the placer's presence again.
- The topic pick sends no push.

## History

"What we know" lists the couple's revealed rounds, newest first.

- **Records** at the top, one column per partner with its avatar: spot-ons as the guesser, and the average distance of their guesses ("12% off"). Under them, one shared line with a heart: "142 points together". There is no winner. The records show once there is a guess.
- **Row.** The subject in `bodyEmphasis`, a small line with both markers in their places (the real spot with the placer's mark, the guess with the guesser's, as 26 pt heads in the owner's color), then "[Name] guessed · 4 points · Oct 12".
- **Detail.** The topic with its two ends, the line at full size with both markers and the gold thread between them, the verdict, and "You put it here" or "[Name] put it here" under the real spot.
- Pages by round number, 30 rounds a page. Only guessed rounds are listed, so an open round's spot never leaves the server.

## Screens

Copy keys start with `consensio.`, so their Swift symbols start with `consensio`. The tables list only the part after `consensio.`. "[Name]" is the partner's display name. Norwegian is Bokmål. Counts use String Catalog plural variants. Every string goes into the catalog with a translator comment.

### Shell

- One screen, `ConsensioScreen`, opened from the Games tab and from the pushes. It shows one phase at a time, picked by `ConsensioResolver` from the server's state, the queued moves, and what this person has seen. The view body holds no rules.
- Look. `.paeoniaScreenBackground(.paeoniaBackgroundSecondary)`, `.preferredColorScheme(.dark)`, inline title "Consensio", dark toolbar.
- Toolbar trailing. The score capsule with `heart.fill` and the shared total, which opens "What we know" (VoiceOver: "What we know, 142 points together"). Then a `…` menu with "How to play". The invite bell sits at the leading edge while the partner is away.
- Phase change. Cross-fade plus a 12 pt rise over `PaeoniaMotion.meaningfulMoment`. Reduce Motion: cross-fade over `motionFast`.
- The pinned bottom uses `paeoniaBottomBar`, capped with `.paeoniaReadableWidth()`. Every phase uses `.paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)`.
- Avatars are `PaeoniaProfilePhotoAvatar`, `.paeoniaPartnerOne` for me and `.paeoniaPartnerTwo` for the partner.
- A topic picked or written but not locked lives in the view model only. Leaving the screen before "Lock it in" drops it, and the topic list shows again.

### The line on screen

`ConsensioScale` is the one piece every phase shares. It is a straight line, not a dial.

- A thin track, 4 pt, `.paeoniaSurfacePrimary`, with rounded ends. It runs from where a pin at 0 stands to where a pin at 100 stands, so a pin at either end sits on the end of the track. There are no marks on it.
- The two ends sit under the track, left-aligned under the left end and right-aligned under the right end, in `callout` semibold, `.paeoniaTextSecondary`, up to two lines each.
- A marker (`ConsensioMarker`) is a pin: a 36 pt round head on a thin stem that stands on the track. The head is filled with its owner's color (`.boardGameMine` pink and `.boardGamePartner` lavender, as on the board games) and holds the owner's drawn mark in dark ink, as a Connect Four disc does, or their initial (`BoardMarkView` in `Features/Games/BoardGames/Shared/BoardPieces.swift`). The marks come from the board games cache. The stem lifts the head above the finger, so a finger never covers it. The whole line area takes touches. "What we know" draws the same marks. On a row, two heads that would overlap move apart until they touch (`ConsensioMiniLine.headCenters`).
- While the finger is down the head lifts 6 pt and grows 10 percent. Every 5 positions it moves gives `selection()` and `GameSound.tick` at volume 0.4. Lifting the finger settles it with `cardReveal`.
- The hidden spot is never drawn before the reveal. Nothing on the guesser's screen hints at it.
- VoiceOver. The track is one adjustable element. Its label is the subject, its value "62 percent of the way to book it now" (or "in the middle" from 45 to 55), and its hint "From never again to book it now. Swipe up or down to move it." A swipe moves it 5, and the custom actions "Move a little left" and "Move a little right" move it 1. On the waiting screen the value reads where the partner's live guess is, and it is never announced as it moves.

### Haptics and sounds

Existing tokens and sounds only.

| Moment | Haptic | Sound |
|---|---|---|
| Pick a topic row | `selection()` | `tap` 0.7 |
| Marker moves 5 positions | `selection()` | `tick` 0.4 |
| Lock it in, Lock in my guess | `drawingSent()` | `send` |
| Partner arrives, partner locked in | `partnerDrawingReceived()` | `nudge` 0.6 |
| Reveal build-up, three beats | `streakTick(intensity:)` 0.3, 0.5, 0.7 | `tick` 0.3, 0.5, 0.7 |
| The real marker lands | `answerRevealed()` | `chime` |
| Spot on | `streakCelebrated()` | `win` |
| So close, Close | `streakContinued()` | `bonus` |
| Now you know more | `partnerDrawingReceived()` | `soft` |
| Points count up | `streakTick(0.4)` per point | `tick` 0.5 |

### 1. Pick a topic

Purpose. One quick choice, then place.

Layout, top to bottom.

1. Title "Pick a topic" (`heroTitle`), subtitle "[Name] guesses where you stand." The first turn of a new game says "Put your marker where you stand. [Name] guesses where it is." instead.
2. Three topic rows in a `VStack(spacing: space12)`. A row is `radius16`, `.paeoniaSurfaceSecondary`, at least 72 pt tall. The subject in `title`, then the two ends on one line in `caption`, `.paeoniaTextSecondary`, joined by a small `arrow.left.and.right`.
3. A "Write your own" row with `square.and.pencil`.
4. Pinned bottom: primary "Start", off until a row is chosen.

Interactions. Start stays off while the own topic breaks a rule, and the rule shows under the fields. Tapping a row selects it (`strokeEmphasis` border in `.paeoniaAccentPrimary`, `checkmark.circle.fill`). "Write your own" opens three fields in place: the subject, then the left end and the right end side by side. Validation lines show under them as in Draw & Guess. Start goes to placing without waiting for the network, because the pick and the spot are sent together.

With no choices on the phone, as on a fresh install offline, the three rows give way to `PaeoniaEmptyStateView` with "Your topics are on their way" and "Try again in a moment, or write your own below." with Try again. It does not say the phone is offline, because the topics can be missing on a working connection too. "Write your own" still works under it.

VoiceOver reads a row as "Camping, from never again to book it now", with the selected trait on the chosen one.

| Key | English | Norwegian |
|---|---|---|
| `choose.offline.message` | Try again in a moment, or write your own below. | Prøv igjen om litt, eller lag ditt eget under. |
| `choose.offline.title` | Your topics are on their way | Temaene er på vei |
| `choose.own.error.characters` | Some of those characters can't be used. Try plain letters. | Noen av tegnene kan ikke brukes. Prøv vanlige bokstaver. |
| `choose.own.error.end` | Use 1 to 24 characters for each end. | Bruk 1 til 24 tegn på hver ende. |
| `choose.own.error.same` | Give the two ends different words. | Gi de to endene forskjellige ord. |
| `choose.own.error.subject` | Use 2 to 60 characters for what it's about. | Bruk 2 til 60 tegn på hva det handler om. |
| `choose.own.left` | One end | Den ene enden |
| `choose.own.right` | Other end | Den andre enden |
| `choose.own.subject` | What it's about | Hva det handler om |
| `choose.own.subtitle` | An inside joke, or something only the two of you know. | En intern spøk, eller noe bare dere to vet om. |
| `choose.own.title` | Write your own | Lag ditt eget |
| `choose.row.a11y` | %1$@, from %2$@ to %3$@ | %1$@, fra «%2$@» til «%3$@» |
| `choose.start` | Start | Begynn |
| `choose.subtitle` | %@ guesses where you stand. | %@ gjetter hvor du står. |
| `choose.subtitleFirst` | Put your marker where you stand. %@ guesses where it is. | Sett brikken din der du står. %@ gjetter hvor den er. |
| `choose.title` | Pick a topic | Velg et tema |
| `menu.a11y` | More options | Flere valg |
| `offline.message` | Connect to the internet to start the game. | Koble til internett for å starte spillet. |
| `offline.title` | You're offline | Du er ikke på nett |
| `startFailed.message` | We couldn't start the game. Try again in a little while. | Vi fikk ikke startet spillet. Prøv igjen om litt. |
| `title` | Consensio | Consensio |

### 2. Place

Purpose. Answer honestly, in one move.

Layout, centered.

1. The subject (`heroTitle`), then "Where are you on this?" (`body`, `.paeoniaTextSecondary`).
2. The line, with my marker in the middle.
3. One quiet line under it: "Be honest. [Name] won't see it until they've guessed."
4. Pinned bottom: primary "Lock it in" (`lock.fill`), Back in the toolbar returns to the topic list without sending.

"Lock it in" fires `drawingSent()` and `send`, and the phase moves to waiting. Offline, the spot is saved on this phone and the waiting screen shows the offline line.

| Key | English | Norwegian |
|---|---|---|
| `place.back` | Back to topics | Tilbake til temaene |
| `place.hint` | Be honest. %@ won't see it until they've guessed. | Vær ærlig. %@ ser det ikke før gjetningen er låst. |
| `place.lock` | Lock it in | Lås svaret |
| `place.question` | Where are you on this? | Hvor står du her? |
| `scale.empty` | not placed yet | ikke satt ennå |
| `scale.hint` | From %1$@ to %2$@. Swipe up or down to move it. | Fra «%1$@» til «%2$@». Sveip opp eller ned for å flytte den. |
| `scale.left` | Move a little left | Flytt litt til venstre |
| `scale.middle` | in the middle | midt på |
| `scale.partner.a11y` | %1$@'s guess, %2$@ | Gjetningen til %1$@, %2$@ |
| `scale.range` | From %1$@ to %2$@ | Fra «%1$@» til «%2$@» |
| `scale.right` | Move a little right | Flytt litt til høyre |
| `scale.value` | %1$lld percent of the way to %2$@ | %1$lld prosent av veien mot «%2$@» |

### 3. Waiting

Purpose. Say what the partner is doing and that the reveal is coming. Live, this is the placer's best screen: watching the partner look for the spot.

Two cases, one layout.

- **Waiting for the guess.** The subject and the line, with my marker at my spot at 0.6 opacity. Live, the partner's guess marker moves on the same line at full strength. While the two markers are within 7 positions, the track between them warms to `.paeoniaInkGold` at 0.3, so the placer sees "close" without a word. Title "[Name] is guessing" while live, "Waiting for [Name]" otherwise.
- **Waiting for a topic.** The partner's avatar, 96 pt, with a breathing ring while they are in the game (`.paeoniaAccentPrimary` 0.2 to 0.5 over 2.4 s, still at 0.35 under Reduce Motion). Title "[Name] is picking a topic" while their role is `choosing` or `placing`, "Waiting for [Name]" otherwise. When their marker arrives, the guess phase rises in with `cardReveal` and `partnerDrawingReceived()`.

Under the title, a hint. Live: "You'll both see it the moment [Name] locks in." Away: "We'll tell you when [Name] guesses." or "We'll tell you when it's your turn." When the placement is still on the phone after a failed send, the shared offline line shows, or, when the send failed on a working connection, "We couldn't send your move yet" with Try again (`ConsensioHeldLine`). When the partner's pin arrives while this screen waits for it, the guess opens with `partnerDrawingReceived()` and `nudge`.

| Key | English | Norwegian |
|---|---|---|
| `wait.choosing` | %@ is picking a topic | %@ velger et tema |
| `wait.guessing` | %@ is guessing | %@ gjetter |
| `wait.hintGuess` | We'll tell you when %@ guesses. | Vi sier fra når %@ har gjettet. |
| `wait.hintLive` | You'll both see it the moment %@ locks in. | Dere ser det begge så snart %@ har låst svaret. |
| `wait.hintTurn` | We'll tell you when it's your turn. | Vi sier fra når det er din tur. |
| `wait.title` | Waiting for %@ | Venter på %@ |
| `wait.yourSpot.a11y` | Your marker. Only you can see it. | Brikken din. Bare du ser den. |

### 4. Guess

Purpose. Think about the partner, then commit.

Layout, centered.

1. The live row (`GameLiveRow`): the partner's avatar and "[Name] is watching" with the accent ring while the placer is in the game, or "[Name] will see your guess later".
2. The subject (`heroTitle`), then "Where is [Name] on this?".
3. The line, with my marker in the middle.
4. Pinned bottom: primary "Lock in my guess" (`lock.fill`).

Lock in fires `drawingSent()` and `send`, and the reveal opens at once.

| Key | English | Norwegian |
|---|---|---|
| `guess.later` | %@ will see your guess later | %@ ser gjetningen din senere |
| `guess.lock` | Lock in my guess | Lås gjetningen |
| `guess.question` | Where is %@ on this? | Hvor står %@ her? |
| `guess.watching` | %@ is watching | %@ ser på |

### 5. Reveal

Purpose. The best three seconds of the game. The guesser learns something about the partner, and the placer sees how well they are known.

Both partners see the same reveal. The guesser's phone plays it right after the guess. The placer's phone plays it when they open the game, or live when the guess arrives. On each phone this person's own pin is the one that stands first (the guess on the guesser's phone, the real spot on the placer's), and the partner's pin is the one that drops in. The beats are the same. The reveal draws the line larger than the other screens (`ConsensioRevealStage`, pins at 1.7 times, 2.4 on wide layouts), with the subject above it in `title` and `.paeoniaTextSecondary`, so the verdict stays the biggest text.

Beats, in seconds after the reveal starts.

| Time | What happens |
|---|---|
| 0.00 | This person's pin stands on the line. The track dims to 0.3 and the ends to 0.4, and a soft pink glow rises behind the pins (a blurred ellipse at 0.16). On the guesser's phone the reveal waits here until the server answers. |
| 0.20, 0.50, 0.80 | Three build-up beats. The standing pin's head pulses 1 to 1.16 and back, each with `streakTick` 0.3, 0.5, 0.7 and `tick`. |
| 1.25 | The partner's pin drops from 90 pt above its spot and plants in the track with a small spring (bounce 0.3). `answerRevealed()`, `chime`. When the two heads would overlap, both pins already lean apart around the foot of their stems until the heads just touch, so who is where stays readable and the stems still stand on the true spots. |
| 1.55 | When the heads don't touch, a glowing gold arc (4 pt, `.paeoniaInkGold` with a soft gold shadow) draws from this person's head to the partner's over `motionMorph`. On a far guess it draws dashed in `.paeoniaTextTertiary` from the start. |
| 1.95 | The verdict. See below. |
| 2.35 | Title and line fade up. Their room is laid out from the start, so nothing above them moves. |
| 2.65 | The shared total counts up one point every 0.07 s, each with `streakTick` 0.4. |
| 3.05 | The button appears. |

Verdict.

- **Spot on** (0 to 3). Both heads glow gold, the glow behind them swells to 0.55, and a petal bloom bursts over the whole screen from where the heads meet (`GamePetalBloom`, intensity 2.2, seeded by the round id). `streakCelebrated()`, `win`. Title "Spot on!". Line "You know [Name] well." on the guesser's phone, "[Name] knows you well." on the placer's.
- **So close** (4 to 11) and **Close** (12 to 19). The glow swells to 0.3. `streakContinued()`, `bonus`. Titles "So close!" and "Close". The line names the distance: "Only 6% off."
- **Now you know more** (20 or more). The dashed arc stays, and the glow falls to 0.1. `partnerDrawingReceived()`, `soft`. Title "Now you know more". On the guesser's phone the line is "[Name] is closer to book it now than you thought.", naming the end the real spot lies toward, seen from the guess. On the placer's: "[Name] thought you were closer to never again.", naming the end the guess lies toward, seen from the real spot. A spot at 8 and a guess at 35 name the right end on both phones. When the real spot is in the middle (45 to 55), the line is "[Name] is right in the middle." or "[Name] thought you'd lean more to one side."

Once the partner's pin has landed, a small legend right under the line names the pins: a dot in each color with "You" and "[Name]". Captions under the pins would collide when the pins stand close.

Score line (from 2.65). Both avatars, slightly overlapping, next to the shared total counting up one point at a time, with "+4" beside it in `.paeoniaAccentPrimary` and "points together" under it. At 0 points only the total shows.

Everything is tappable from 2.30. A tap on the screen jumps to the settled state, as `DrawAndGuessRevealTimeline.skip` does, without repeating haptics. Reduce Motion: no pulses, drop, thread draw or bloom. The settled state shows at once, with only the verdict haptic and sound.

Buttons. The guesser gets the primary "Your turn to place". The placer gets "Continue", which goes to the guess when the partner already placed the next marker, and to waiting otherwise. Leaving the reveal marks it seen once its title has shown. A reveal left before the verdict plays again next time.

Held reveal. While the guess is on its way, the reveal holds at 0.00 with only the guesser's own pin on the dimmed line. Normally the server answers within a moment and the reveal plays. Once a send of the guess has failed, the line "Saved on this phone. We'll show where [Name] is when you're online." shows (or, after a failure on a working connection, "We couldn't send your move yet" with Try again), with "Your turn to place" under it, so the guesser can go on. Stepping past a held reveal does not mark it seen, so it plays on the next visit. If the server refuses the guess because the round already has one, as when a second phone guessed first, the screen plays the reveal of the guess the server has. Only another refusal shows the shared "Your move wasn't sent" banner and returns to the guess.

VoiceOver. On the verdict, one announcement: "Robin is 70 percent of the way to book it now. You guessed 62 percent of the way to book it now. So close. Points: 4." Focus moves to the title. The bloom and thread are hidden. Positions read as "62 percent of the way to" the nearer end, or "in the middle" from 45 to 55.

| Key | English | Norwegian |
|---|---|---|
| `handoff.continue` | Continue | Fortsett |
| `handoff.place` | Your turn to place | Din tur til å sette brikken |
| `reveal.announcement.guesser` | %1$@ is %2$@. You guessed %3$@. %4$@. Points: %5$lld. | %1$@ er %2$@. Du gjettet %3$@. %4$@. Poeng: %5$lld. |
| `reveal.announcement.placer` | %1$@ guessed %2$@. You were %3$@. %4$@. Points: %5$lld. | %1$@ gjettet %2$@. Du var %3$@. %4$@. Poeng: %5$lld. |
| `reveal.close.title` | Close | Nær |
| `reveal.far.guesser` | %1$@ is closer to %2$@ than you thought. | %1$@ er nærmere «%2$@» enn du trodde. |
| `reveal.far.middle.guesser` | %@ is right in the middle. | %@ står midt på. |
| `reveal.far.middle.placer` | %@ thought you'd lean more to one side. | %@ trodde du lå mer til den ene siden. |
| `reveal.far.placer` | %1$@ thought you were closer to %2$@. | %1$@ trodde du var nærmere «%2$@». |
| `reveal.far.title` | Now you know more | Nå vet du mer |
| `reveal.hidden.a11y` | Waiting for %@'s marker | Venter på brikken til %@ |
| `reveal.off` | Only %lld% off. | Bare %lld % unna. |
| `reveal.points` | +%lld | +%lld |
| `reveal.pointsTogether` | points together | poeng sammen |
| `reveal.soClose.title` | So close! | Så nær! |
| `reveal.spotOn.guesser` | You know %@ well. | Du kjenner %@ godt. |
| `reveal.spotOn.placer` | %@ knows you well. | %@ kjenner deg godt. |
| `reveal.spotOn.title` | Spot on! | Midt i blinken! |
| `reveal.stage.a11y` | The real spot is %1$@. The guess is %2$@. | Den riktige plassen er %1$@. Gjetningen er %2$@. |
| `reveal.waitingServer` | Saved on this phone. We'll show where %@ is when you're online. | Lagret på telefonen. Vi viser hvor %@ står når du er på nett. |
| `reveal.you` | You | Du |

### 6. What we know

Entry points: the score capsule in the toolbar, and a quiet link on the hub card once the couple has a revealed round. Layout as in "History" above, in one scroll view, with `.paeoniaSurfaceSecondary` rows on `radius16`.

Empty states use `PaeoniaEmptyStateView`: no rounds yet (`point.topleft.down.to.point.bottomright.curvepath`, "Nothing here yet", "Your rounds show up here after the first guess."), and offline with nothing cached (the shared offline state).

VoiceOver reads a row as "Camping. Robin was at 70 percent, you guessed 62 percent. 4 points, October 12."

| Key | English | Norwegian |
|---|---|---|
| `history.detail.placed` | %@ placed this one | %@ satte denne |
| `history.detail.placedByYou` | You placed this one | Du satte denne |
| `history.empty.message` | Your rounds show up here after the first guess. | Rundene deres dukker opp her etter første gjetning. |
| `history.empty.title` | Nothing here yet | Ingenting her ennå |
| `history.failed.message` | We couldn't load your rounds. Try again in a little while. | Vi kunne ikke laste rundene deres. Prøv igjen om litt. |
| `history.loadMore.failed` | We couldn't load older rounds. | Vi kunne ikke laste eldre runder. |
| `history.offline.message` | Connect to the internet to see your rounds. | Koble til internett for å se rundene deres. |
| `history.records.average` | On average | I snitt |
| `history.records.averageValue` | %lld% off | %lld % unna |
| `history.records.none` | Not yet | Ikke ennå |
| `history.records.spotOn` | Spot on | Midt i blinken |
| `history.row.a11y` | %1$@. The real spot is %2$@. The guess is %3$@. Points: %4$lld. | %1$@. Den riktige plassen er %2$@. Gjetningen er %3$@. Poeng: %4$lld. |
| `history.row.caption` | %1$@ guessed · %2$@ · %3$@ | %1$@ gjettet · %2$@ · %3$@ |
| `history.title` | What we know | Det vi vet |

### How to play

Three `GameTutorial` cards, opened the first time this phone opens the game and from the toolbar menu. Pictures in the `GameTutorial` asset folder, made with the `paeonia-illustrations` skill.

| Card | Picture | Title | Message |
|---|---|---|---|
| 1 (`GameTutorialConsensioPlace`) | A pink pin planted on the cream rail | Show where you stand / Vis hvor du står | Pick a topic and put your marker where you really stand. / Velg et tema og sett brikken din der du egentlig står. |
| 2 (`GameTutorialConsensioGuess`) | A lavender pin about to plant on the rail | [Name] guesses / [Name] gjetter | [Name] sees the same topic and guesses where you put it. Then you swap. / [Name] ser det samme temaet og gjetter hvor du satte den. Så bytter dere. |
| 3 (`GameTutorialConsensioClose`) | Both pins touching, a peony between them | Closer means more points / Jo nærmere, jo flere poeng | You score together. The closer the guess, the more points you both get. / Dere får poeng sammen. Jo nærmere gjetningen er, jo flere poeng får dere. |

### Hub card

`ConsensioHubCard` follows the Draw & Guess card: the picture behind the whole card, the partner-here chip and the score capsule over its scene, then the title, a status line, the primary button and the "What we know" link.

Artwork (`ConsensioHubArtwork`), following `docs/games/hub-artwork.md`. `GameHubConsensioRail` is a long cream rail with gold end caps, 640 pixels wide at the main object's spot, with a pink pin planted at about a third of its length. The beat: `GameHubConsensioPin`, a lavender pin, drops onto the rail at 62 percent of its length (0.620, 0.639 of the image) and plants with a small squash, and a gold glow swells between the two heads.

| State | Status line | Button |
|---|---|---|
| No game yet | Show where you stand. Then [Name] guesses. | Play |
| My turn to place | Your turn to pick a topic. | Pick a topic |
| The partner placed, my guess | [Name] placed a marker. Your turn. | Guess |
| I placed, waiting | Waiting for [Name] to guess. | Open |
| The partner is picking | [Name] is picking a topic. | Open |
| Unseen reveal | A guess is in. | See how close |

"Your turn" (the badge and the glow) means a guess, a placement or an unseen reveal waits for me.

| Key | English | Norwegian |
|---|---|---|
| `hub.guess` | Guess | Gjett |
| `hub.open` | Open | Åpne |
| `hub.pick` | Pick a topic | Velg et tema |
| `hub.play` | Play | Spill |
| `hub.seeReveal` | See how close | Se hvor nær |
| `hub.status.choosing` | %@ is picking a topic. | %@ velger et tema. |
| `hub.status.guess` | %@ placed a marker. Your turn. | %@ har satt brikken sin. Din tur. |
| `hub.status.new` | Show where you stand. Then %@ guesses. | Vis hvor du står. Så gjetter %@. |
| `hub.status.place` | Your turn to pick a topic. | Din tur til å velge et tema. |
| `hub.status.reveal` | A guess is in. | En gjetning er klar. |
| `hub.status.waiting` | Waiting for %@ to guess. | Venter på at %@ skal gjette. |
| `pointsTogether` | %lld point together / %lld points together | %lld poeng sammen |
| `stats.points` | %lld point / %lld points | %lld poeng |

### Wide layouts and Dynamic Type

- The line stays one line at every size. Its ends wrap to more lines at accessibility sizes, and the screen scrolls with the button pinned.
- Wide (700 pt or more and wider than tall): every phase keeps the focused width, centered. The line grows to at most 560 pt.
- iPad keeps the tab bar, as in Draw & Guess.

## Names

| kind (backend, relay channel) | Swift prefix | URL path `paeonia://games/<path>` | Folder | Design doc |
|---|---|---|---|---|
| consensio | consensio / Consensio | consensio | Consensio | docs/games/consensio.md |

## Data

The functions are in `backend/convex/consensio.ts`, the rules and table definitions in `backend/convex/lib/consensio.ts`. The topics are `backend/games/consensio/en.json` and `nb.json`, read like the Draw & Guess words (`lib/gameWords.ts`), with a test next to them.

- `consensio_games`: one row per couple. `turn_user_id`, the next placer's three topic choices, the shared total, `round_count`, and `version`, which goes up with every change to the game or its rounds, seen marks included.
- `consensio_rounds`: one row per round. `round_number`, the placer, the guesser, the topic as stored text (`topic_id` or none for an own topic, `language`, `subject`, `left_end`, `right_end`), `spot`, `placed_at`, `reminder_sent_at`, and once guessed, `guess`, `distance`, `points`, `guessed_at`, `placer_reveal_seen_at` and `guesser_reveal_seen_at`. The client makes the round id, so a placement queued offline can name its round.
- `consensio_used_topics`: the topics the couple has placed, per language. A language starts over when all its topics were used.
- The game is waiting for a placement when its newest round has a guess, or there is no round. It is waiting for a guess when its newest round has none. A placement turn waits from the newest round's `guessed_at` (or the game's creation), a guess turn from the round's `placed_at`.

Functions.

- `get_consensio` (query): the caller's view. The game, the newest round, and the latest guessed round while the caller has not seen its reveal. `spot` is returned only to the placer of an open round, and to both on a guessed round. The topic choices go only to the next placer. Returns `data_epoch: dataEpoch()`.
- `ensure_consensio_game`: makes the couple's game if there is none, with the caller as the first placer, and returns it either way.
- `place_consensio_spot` (client operation): `p_round_id`, a catalog topic (`p_topic_id`, `p_topic_language`) or an own one (`p_subject`, `p_left_end`, `p_right_end`), `p_spot`, and `p_round_number`, the round it makes. Checks access before the replay check, that the caller is the next placer, the topic, that the spot is a whole number from 0 to 100, and that the round number is the next one, so a placement queued on another phone can't land in a later turn. The operation's request names a catalog topic by id, so a catalog edit never breaks a retry. Opens the round for the partner, makes the partner's next choices, counts toward the streak, and queues the turn push (or the `guessed` step).
- `guess_consensio_spot` (client operation): `p_round_id`, `p_guess`. Checks access before the replay check, so a replay never hands the spot to someone who lost access, then that the caller is the round's guesser and the round has no guess. Scores it, adds the points, queues the delayed result push, and returns the guessed round with the real spot. A repeat of the same guess returns the same answer.
- `mark_consensio_reveal_seen` (client operation): `p_round_id`. Keeps the first time. Safe to repeat.
- `get_consensio_history`: `p_before_round_number`, `p_limit` (capped at 50). Guessed rounds only, newest first, with `next_before_round_number` and `records`: the shared total, and `mine` and `partner`, each `{ guesses, spot_ons, average_distance }` as a guesser.
- `consensioBackend` in `lib/consensio.ts` is the registry entry. `pushStillWanted` as in "Notifications". `deleteCoupleRows` deletes all three tables. `sendDueTurnReminders` sends one reminder per turn after `TURN_REMINDER_AFTER_MS`. `onLanguageChanged` replaces the next placer's choices.

Errors follow Draw & Guess so the app's refusal handling works: `42501` for access, `23514` for rules ("this round already has a guess", "it isn't your turn", "spot must be a whole number from 0 to 100", "topic must have a subject of 2 to 60 characters"), `23505` for a repeat with different values.

Relationship cleanup deletes the three tables with the other game rows.

## iOS

- **Folder.** `Features/Games/Consensio/` with `Models/`, `Data/`, `Game/` (view model, resolver), `Scale/` (the line and marker), `Screen/` (phases), `Reveal/` (timeline and script), `History/`, `Live/` and `Hub/`. Tests in `PaeoniaAppTests/Games/Consensio/`.
- **Local first.** Placing, guessing and seen marks go into the pending operations before anything is sent (`SyncPendingOperationKind.consensioPlace`, `.consensioGuess`, `.consensioRevealSeen`). The resolver applies queued moves on top of the server's state, so a placement shows the waiting screen at once and a guess opens the reveal at once. Creating the game needs a connection.
- **Order.** A placement or a guess waits for every earlier placement and guess of this person. A seen mark waits for the guess of its round. A refused move drops with the shared "Your move wasn't sent" banner, and a refused placement goes back to the line with the topic and marker it had. A guess refused because the round already has a guess reads the server's state and plays that reveal. The pending operation kinds are `placeConsensioSpot`, `guessConsensioSpot` and `markConsensioRevealSeen` (`Data/ConsensioPendingOperations.swift`).
- **Cache.** `ConsensioCache` keeps the last `get_consensio` result and the first history page per person, in its own `GamesDocumentStore` file. It never takes a state behind the one it holds (a lower `version`), and `isOlder(than:)` is false across different `data_epoch` values.
- **Live feed.** `ConsensioLiveFeed` subscribes to `consensio:get_consensio` and writes into the cache.
- **Live room.** One `WidgetLiveDrawing` connection on the `consensio` channel, for presence, roles and a `GameLiveChannel<ConsensioLiveMessage>`.
- **Registration.** `consensio` joins `GAME_KINDS`, `ALLOWED_CHANNELS` and `GameKind`. `scripts/deploy-backend` deploys the relay with the backend, and a relay without the channel drops every live message for it, so the relay deploys before any build that opens the room.

### Developer scenarios

`App/DeveloperScenarios/DeveloperScenario+Consensio.swift`, in this order:

| id | Opens |
|---|---|
| `consensio-first-turn` | The topic picker of a new game |
| `consensio-own-topic` | The topic picker with "Write your own" open |
| `consensio-place` | Placing, with a topic chosen |
| `consensio-wait-choosing` | Waiting while the partner picks a topic |
| `consensio-wait-live` | Waiting for the guess, with the partner's live marker moving |
| `consensio-wait-later` | Waiting for the guess, partner away, invite bell |
| `consensio-guess` | Guessing |
| `consensio-reveal-spot-on` | Reveal, 2% off, guesser side |
| `consensio-reveal-close` | Reveal, 14% off, guesser side |
| `consensio-reveal-far` | Reveal, 41% off, guesser side |
| `consensio-reveal-placer` | Reveal, 6% off, placer side |
| `consensio-reveal-held` | Reveal held: the guess is only on the phone and a send failed |
| `consensio-history` | What we know with 12 rounds |

## Open questions

- The topic lists need a native speaker's read before release.
- A trademark check on the chosen name before launch.
