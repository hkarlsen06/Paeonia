# Mind Meld

Design for the second word game. Shared rules for all games (transports, the Convex model, notifications, the game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Mind Meld. The Norwegian name is Tenk likt.

Keep this file current. When a decision lands or the design changes, update it in the same change.

The write header groups partner progress and the round in one centered row when they fit. The heading follows with a compact gap. Larger text stacks the statuses without shrinking them.

## Decisions

- **Round 1 is free choice.** Each partner types any word. A "Surprise me" button fills in a random word from a hand-written list in the couple's game language.
- **Matching is forgiving, and near misses can count.** The server ignores case, spaces, punctuation and accents, and treats ae, oe and aa as æ, ø and å. When two words are almost the same, the reveal says "So close!" and either partner can tap "Count it" to make it a match.
- **A game runs at most 10 rounds.** After round 10 without a match the game ends softly. Either partner can start over earlier, after a confirm alert. There are no timers.
- **Always together.** Mind Meld is cooperative, so it ignores the play style setting. It shows shared numbers only: how many times the couple melded and their fewest rounds to a meld.
- **History keeps the word trails.** Every finished game keeps its trail of word pairs. "Our melds" lists them, newest first. There are no stars.
- **Locking in a word counts toward the streak**, once per round and person.
- **The Norwegian name is Tenk likt.**
- **Live signals go over the relay.** The `mind_meld` relay room carries "here" and "typing". Words, locks and the reveal go through Convex only, so the relay never carries a word.
- **Turn and reveal pushes.** See "Notifications".
- **Repeats are blocked.** Nobody can use a word either partner already said in this game.
- **The hub card shows two words becoming one.**
- **A new game starts when either partner taps "Play again".**

## Decisions made without the developer

Made on 2026-10-14 while the developer was away. Each one is the option I would have recommended. Review them and change any that don't fit.

- **Lock in is final.** A locked word can't be changed. Until then the person edits freely.
- **Return only closes the keyboard.** Lock in sits above the keyboard, so a stray tap on Done never locks in a word.
- **Either partner can count a near miss**, without the other agreeing. Both win together, so there is nothing to protect.
- **A near miss in round 10 can still be counted.** It shows "So close!" with "Count it" and "Play again".
- **Counting a near miss removes the next open round**, with any word already locked in for it. The game is won, so that round can never be revealed.
- **A refused lock-in uses the shared Games banner** ("Your move wasn't sent"), and the word goes back in the field. No Mind Meld-only notice.
- **"Typing" means** the field is not empty and changed in the last 3 seconds. The phone repeats the typing message every 2 seconds, and the partner's phone drops it after 4 seconds without one.
- **Only the game's latest revealed round can play as an unseen reveal.** An older unseen round is skipped, as in Draw & Guess.
- **`stats.games` counts finished games**, so the "Our melds" link shows once a game has ended.
- **The "Surprise me" lists live on the phone**, about 150 words per language. They need a native speaker's read before release.

## The game

Both partners type a word without seeing the other's. When both have locked in, the two words are revealed together. If they are the same word, the couple melded and the game is won. If not, both look at the two words and try to name one word that connects them. That is the next round. The words drift closer each round until both partners say the same word.

1. **Round 1.** "Say any word." Each partner types anything. A partner who freezes taps "Surprise me".
2. **Reveal.** When the second partner locks in, both words are revealed side by side.
3. **Next round.** "Find a word that connects OCEAN and SUSHI." Both type again, without talking.
4. **Meld.** Both say FISH. The game is won, and the screen shows the whole trail: OCEAN + SUSHI, then SALT + FISH, then FISH + FISH.

A couple has at most one game in play at a time. A finished game stays in "Our melds".

### Words

- A word is 1 to 30 characters after trimming, at most three words separated by single spaces, and holds at least one letter. Letters from any alphabet, digits, spaces, hyphens and apostrophes are allowed. Phrases like "ice cream" or "New York" are fine.
- The phone checks a word as it is typed, and the server checks it again.
- Words are stored as typed, trimmed, with single spaces. The cards show them in capitals.
- The game language decides only the "Surprise me" list. A couple can type in any language.

### Matching

The server compares match keys. The phone never compares the two words, because it never sees the partner's word before the reveal.

The match key of a word is built in this order:

1. Unicode NFKC, then lowercase.
2. æ and ä become `ae`, ø and ö become `oe`, å becomes `aa`.
3. Accents are removed (é becomes e, ü becomes u).
4. Everything that is not a to z or 0 to 9 is removed, including spaces. "Ice cream", "ice-cream" and "icecream" match. So do "is krem" and "iskrem".

Two words **match** when their keys are equal.

Two words are a **near miss** when they don't match and either of these holds:

- They have the same stem. The stem drops one ending from the key, the first of `ingen`, `inger`, `ings`, `ing`, `ende`, `ene`, `ane`, `ers`, `ies` (which becomes `y`), `es`, `er`, `en`, `et`, `ed`, `s`, `a`, `e` that leaves at least 3 letters. When the stem then ends in a doubled letter, one of the two goes, as long as 3 letters stay. "dog" and "dogs", "hund" and "hunden", "hest" and "hestene", "kidnapping" and "kidnapper", "løper" and "løping" are near misses. The word-forming endings also pair a few unrelated words, such as "number" and "numbing". The couple decides with "Count it".
- Both keys have 5 or more letters and differ by one letter (one added, removed or changed). This catches a typo, and sometimes "house" and "horse". The couple decides with "Count it".

A near miss shows "So close!" on the reveal. Either partner can tap "Count it". The round then counts as a match, the game is won, and both phones celebrate. Nobody has to agree first, because both partners win together.

### Repeats

Nobody can lock in a word whose key equals the key of a word either partner already said in this game's revealed rounds. The field shows "You've already used OCEAN in this game." and Lock in stays off. The server refuses it too. Near misses of an earlier word are allowed ("dog" after "dogs").

### Surprise me

Round 1 only. The button fills the field with a random word from a hand-written list in the couple's game language, about 150 words per language. The list is on the phone (`MindMeldStarterWords`). The pick skips the word already in the field, so tapping again gives a new word. The person can still edit the word before locking in. A native speaker reads every word before it ships, with the same checks as the Draw & Guess list (slurs, crude second meanings, words most people don't know). Words are concrete and evocative, such as volcano, grandma, pizza or fjord, so the first reveal is funny.

### Locking in

- Lock in is final. A locked word cannot change. Until then the person can edit freely.
- The partner learns only that a word is locked in, never the word, until both have locked in. This holds on the server: the read returns the partner's word only for a revealed round.
- A lock-in made offline is saved on the phone and sent later. The screen shows it as locked without a save-status line.

### Ending

- **Meld.** The round's words match, or a partner counted a near miss. The game is won.
- **Got away.** Round 10 is revealed without a match. The game ends softly with "This one got away". A near miss in round 10 can still be counted.
- **Start over.** Either partner can end the game in play from the toolbar menu, with a confirm alert. A new game starts at once. A word the partner had locked in for the open round is never revealed. The partner sees "[Name] started a new game" once.
- **Play again.** A finished game shows "Play again". The first partner who taps it starts a new game at round 1. A partner who taps it after that joins the same game. A partner who has not seen the end of the last game sees it first, then lands in the new game.
- No timers. A game waits as long as it needs to.

### Play style

Mind Meld ignores the play style setting. Both partners win or lose together in both styles, and the game never shows a personal score. The shared numbers are:

- **Melds.** How many games the couple has won.
- **Fewest rounds.** The fewest rounds a meld took.

They grow forever, like scores in other games.

## Live

Live runs whenever both partners have the game open. Without the partner there, everything works as async play. Nothing about the round changes except how fast each side sees the other.

- **Presence.** While the game screen is open, the phone joins the `mind_meld` relay room and says `hello` with the role `present`. The relay's `welcome`, `joined` and `left` tell each phone whether the partner is there, as in Draw & Guess. The Convex presence heartbeat runs next to it for push suppression.
- **Typing.** The phone sends a `MindMeldLiveMessage` with the round number and whether the person is typing. It is typing while the field is not empty and the text changed in the last 3 seconds. The phone sends the message when that changes, and again when the partner arrives. Nothing in it is saved, and it never carries letters.
- **Thinking.** While the partner is in the game and has not locked in, the waiting screen circles their portrait on the face-down card with a ring of dots that breathes (`ThinkingOrb` from Libraries.dev). It fades out when they leave.
- **Locked in.** Comes from Convex, not the relay, because it must survive a lost connection. The partner's status changes to "[Name] locked in" within a few hundred milliseconds.
- **The reveal.** The second lock-in reveals the round on the server. The second partner's phone skips the waiting screen. It opens the reveal at once with both cards face down, and plays it as soon as the server answers. If the word fails to send, the phone shows the waiting screen with the line that the word is saved on the phone. The first partner's phone plays it when the live feed delivers the revealed round, usually within 300 ms. Both reveals start nearly together without a shared clock.
- **Lost connection.** The relay reconnects as in Draw & Guess. Status falls back to the async wording until it is back.
- **Invite.** "Tell [Name] you want to play" shows when the partner is not in the game, with the shared invite rules in `docs/games-plan.md`.

## Async

- A partner who locks in first sees the waiting screen and can leave. The other partner gets the turn push.
- The partner who locks in second sees the reveal at once. The first partner gets the reveal push and sees the reveal the next time they open the game.
- Each partner can lock in the next round before the other has seen the last reveal. The other partner sees the reveal first, then the next round with "[Name] locked in".
- The server keeps when each partner first saw each reveal and each game ending, so a second phone or a fresh install never plays an old reveal again.

## Streak

Locking in a word counts toward the couple's streak through the `game_turn_completed` activity kind. The dedupe key is `game_turn_completed:<round id>:<user id>`, so each partner's lock-in counts once per round.

## Notifications

| Push kind | When | Title | Body |
|---|---|---|---|
| `game_turn_ready` | The partner locked in first. | Your turn in Mind Meld / Din tur i Tenk likt | Pick your word. / Velg ordet ditt. |
| `game_result` | The partner locked in second, so the round is revealed. Goes to the partner who locked in first. | Your words are in / Ordene deres er klare | See what you both said. / Se hva dere begge sa. |
| `game_invite` | Invite button. | [Name] wants to play Mind Meld with you / [Name] vil spille Tenk likt med deg | Shared invite body. |
| `game_turn_reminder` | The partner's lock-in waited 72 hours. Once per round. | Your turn in Mind Meld / Din tur i Tenk likt | Shared reminder body. |

- Never show a word or whether the couple matched. The push payload holds only ids and the deep link `paeonia://games/mind-meld`.
- Skip the turn and result pushes while the recipient has the game open.
- A push waits in the outbox until the drain sends it, and the drain checks it again first. It drops a turn push or a reminder once the recipient has locked in or the round is no longer open, and a result push once the recipient has seen the reveal.
- "Count it", "Start over" and "Play again" send no push.

## History

"Our melds" lists the couple's finished games, newest first: melded, got away, and started over. Each shows its revealed rounds as pairs of words, my word first.

- **List row.** The final word in capitals for a meld ("FISH"), or "Got away" / "Started over". Under it, "4 rounds · Oct 12". A meld gets a small petal mark.
- **Detail.** The whole trail, top to bottom. Each round is a row with my word on the left and the partner's on the right, joined by a thin centered line that gets shorter as the words get closer. The last row of a meld is one merged word with the petal mark. A counted near miss shows both words with "Counted".
- **Records** at the top: melds and fewest rounds.
- The open round of a game someone started over is never shown, because its words were never revealed.
- Pages by game number, 30 games a page.

## Open questions

- The "Surprise me" lists need a native speaker's read before release.
