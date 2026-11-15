# Consensio

Design for the ninth game. One partner puts a marker where they honestly stand on a line between two ends, such as how they feel about camping. The other partner guesses where it went, from how well they know them. The reveal shows both markers on the line and scores how close the guess came. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Consensio.

The name is Consensio in both languages, Latin for harmony or shared agreement.

Keep this file current. When a decision lands or the design changes, update it in the same change.

The guessing activity row is centered. Waiting titles keep the portrait beside the text, then stack it above the title at accessibility sizes. The hint follows with a compact gap.

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
- The subject is a thing, a habit or a small situation, never a question in the first person. The screen asks the question in Paeonia's voice: "Where are you on this?" for the placer and "Where is [Name] on this?" for the guesser. So no topic can sound as if the partner wrote it, which `.agents/skills/paeonia-questions/writing.md` requires.
- The three choices are fixed when they are made. The server makes the next placer's three choices when a round opens for a guess, so the guesser has them on the phone before they guess. A guess and the next placement can then both be made offline. The server picks them from the couple's game language, among topics not yet used. Only the topic that gets placed counts as used. When fewer than three are left, the language starts over.
- A language change replaces the three choices. A placement queued with an older choice still works, because the server takes any topic id in its catalogs and stores the subject and ends on the round. A later edit to the catalog never changes an old round.
- To write your own, the placer gives a subject of 2 to 60 characters and two ends of 1 to 24 characters each, different from each other. Letters, digits, spaces and common punctuation are allowed. Line breaks and runs of spaces become one space.

### Writing topics

The topics follow `.agents/skills/paeonia-questions/writing.md`. Paeonia writes them, they never sound like the partner wrote them, and they are warm and playful.

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
- **Invite.** The first item in the `…` menu, with the shared invite rules in `docs/games-plan.md`.

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
| `game_turn_ready` | The partner locked in a marker. | Your turn in Consensio / Din tur i Consensio | Make your guess. / Gjør gjetningen din. |
| `game_turn_ready`, step `guessed` | The partner guessed your marker and then placed one for you within 5 minutes. | [Name] guessed and left you one to guess / [Name] har gjettet og lagt igjen en til deg | See how close they got. / Se hvor nær gjetningen var. |
| `game_result` | The partner guessed your marker and placed nothing for 5 minutes. Goes to the placer. | [Name] made a guess / [Name] har gjettet | See how close they got. / Se hvor nær gjetningen var. |
| `game_invite` | Invite to play. | [Name] wants to play Consensio with you / [Name] vil spille Consensio med deg | Shared invite body. |
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

## Open questions

- The topic lists need a native speaker's read before release.
- A trademark check on the chosen name before launch.
