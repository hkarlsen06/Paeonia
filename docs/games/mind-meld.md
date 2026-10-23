# Mind Meld

Design for the second word game. Shared rules for all games (transports, the Convex model, notifications, the game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Mind Meld. The Norwegian name is Tenk likt.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-13.

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

- They have the same stem. The stem drops one ending from the key, the first of `ene`, `ane`, `ies` (which becomes `y`), `es`, `er`, `en`, `et`, `s`, `a`, `e` that leaves at least 3 letters. "dog" and "dogs", "hund" and "hunden", "hest" and "hestene" are near misses.
- Both keys have 5 or more letters and differ by one letter (one added, removed or changed). This catches a typo, and sometimes "house" and "horse". The couple decides with "Count it".

A near miss shows "So close!" on the reveal. Either partner can tap "Count it". The round then counts as a match, the game is won, and both phones celebrate. Nobody has to agree first, because both partners win together.

### Repeats

Nobody can lock in a word whose key equals the key of a word either partner already said in this game's revealed rounds. The field shows "You've already used OCEAN in this game." and Lock in stays off. The server refuses it too. Near misses of an earlier word are allowed ("dog" after "dogs").

### Surprise me

Round 1 only. The button fills the field with a random word from a hand-written list in the couple's game language, about 150 words per language. The list is on the phone (`MindMeldStarterWords`). The pick skips the word already in the field, so tapping again gives a new word. The person can still edit the word before locking in. A native speaker reads every word before it ships, with the same checks as the Draw & Guess list (slurs, crude second meanings, words most people don't know). Words are concrete and evocative, such as volcano, grandma, pizza or fjord, so the first reveal is funny.

### Locking in

- Lock in is final. A locked word cannot change. Until then the person can edit freely.
- The partner learns only that a word is locked in, never the word, until both have locked in. This holds on the server: the read returns the partner's word only for a revealed round.
- A lock-in made offline is saved on the phone and sent later. The screen shows it as locked, with "Saved on this phone. We'll send it when you're online."

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

## Screens

Copy keys start with `mindMeld.`, so their Swift symbols start with `mindMeld`. The tables list only the part after `mindMeld.`. "[Name]" is the partner's display name. Norwegian is Bokmål. Every string goes into the catalog with a translator comment.

### Shell

- One screen, `MindMeldScreen`, opened from the Games tab and from the pushes. It shows one phase at a time, picked by `MindMeldResolver` from the server's state, the queued moves, and what this person has seen. The view body holds no rules.
- Look. `.paeoniaScreenBackground(.paeoniaBackgroundSecondary)`, `.preferredColorScheme(.dark)`, inline title "Mind Meld" / "Tenk likt", dark toolbar. No cards except the two word cards and the trail chips.
- Toolbar trailing. The melds capsule and a `…` menu with "Start over" while a game is in play. The capsule has both avatars, slightly overlapping (mine first), and the meld count, in the same capsule as the other games' scores. Tapping it opens "Our melds". It shows in every phase, at 0 melds too. VoiceOver: "Our melds, 3 melds together".
- Phase change. Cross-fade plus a 12 pt rise over `PaeoniaMotion.meaningfulMoment`. Reduce Motion: cross-fade over `motionFast`.
- The pinned bottom uses `paeoniaBottomBar`, capped with `.paeoniaReadableWidth()`. The text-led phases use `.paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)`.
- Avatars are `PaeoniaProfilePhotoAvatar`, `.paeoniaPartnerOne` for me and `.paeoniaPartnerTwo` for the partner. My card is always on the leading side.
- The hub card has its own non-tappable stats capsule with the petal glyph (`camera.macro`) and "3 melds". VoiceOver: "3 melds together". Hidden at 0 melds.

**Haptics used.** Existing tokens only.

| Moment | Token |
|---|---|
| Surprise me, Count it | `selection()` |
| Lock in | `drawingSent()` |
| Partner joins | `partnerDrawingReceived()` |
| Partner locked in and you have not | `gameYourTurn()` (`GameAttentionCue`) |
| Invalid word on Lock in | `validationError()` |
| Reveal build-up, three beats | `streakTick(intensity:)` 0.3, 0.5, 0.7 |
| Each card flips | `streakTick(intensity: 0.85)` |
| Miss lands | `partnerDrawingReceived()` |
| Near miss lands | `streakContinued()` |
| Meld lands | `streakCelebrated()` |
| Meld stats appear | `streakContinued()` |

### 1. Write

Purpose. Think of one word and lock it in, with the partner's progress in view.

Layout, top to bottom. At normal text sizes the whole phase is meant to fit above the keyboard on a 6.1 inch phone, without scrolling.

1. One line (`GameLiveRow`): partner status on the leading side (see below), and "Round 3 of 10" on the trailing side (`caption` bold, uppercase, tracking 1.4, `.paeoniaTextTertiary`).
2. Round 1: title "Say any word" (`title`) and subtitle "[Name] does the same. Then you try to meet in the middle." Later rounds: the title "Find a word that connects them", then the last two words as a pair of chips (`MindMeldWordPair`), mine leading, with a small `plus` between.
3. The trail so far, when round 3 or later: the two rounds before the last pair, in a compact column above it, at `caption` size in `.paeoniaTextTertiary`. The plus signs line up in the middle, with my word right-aligned before it and the partner's left-aligned after it. "Our melds" keeps the whole trail.
4. The field. One large centered text field in `PaeoniaTypography.title`, `radius16`, `.paeoniaSurfaceSecondary`, 64 pt tall, `autocorrectionDisabled`, no autocapitalization, `submitLabel(.done)`. It takes focus when the phase opens. Placeholder "Type a word".
5. Under the field, one line: a validation message (`exclamationmark.circle`, `caption`, `.paeoniaErrorText`) or, in round 1, the quiet "Surprise me" button (`dice`).
6. Pinned bottom, above the keyboard while it is open: primary "Lock in" (`lock.fill`). The invite bell sits in the toolbar while the partner is away. Lock in is disabled while the field is empty or a message shows. Return only closes the keyboard, because a locked word is final and a stray tap on Done must not lock it in.

Partner status. A 24 pt avatar and one line:

- "[Name] locked in" with `lock.fill` in `.paeoniaAccentPrimary`, when the server says so. It arrives with `cardReveal` and a pulse of the avatar (1 to 1.12 and back). The shared turn cue taps the phone, also when the partner locked in before this screen opened its write phase. VoiceOver announces it.
- "[Name] is typing" with three dots that rise in turn (`motionDefault`, repeating). Reduce Motion: still dots.
- "[Name] is here" when the partner has the game open but isn't typing.
- "[Name] will answer later" in `.paeoniaTextTertiary` when the partner is away. The invite bell shows in the toolbar until the partner arrives.

Validation. Too long, too many words, no letter, and repeats show inline as the person types, with an announcement. Lock in on an invalid word fires `validationError()`.

Offline. Lock in always works. The phase moves to waiting with the offline line.

| Key | English | Norwegian |
|---|---|---|
| `title` | Mind Meld | Tenk likt |
| `round` | Round %1$lld of %2$lld | Runde %1$lld av %2$lld |
| `write.firstTitle` | Say any word | Si et hvilket som helst ord |
| `write.firstSubtitle` | %@ does the same. Then you try to meet in the middle. | %@ gjør det samme. Så prøver dere å møtes på midten. |
| `write.connectTitle` | Find a word that connects them | Finn et ord som binder dem sammen |
| `write.placeholder` | Type a word | Skriv et ord |
| `write.surprise` | Surprise me | Overrask meg |
| `write.lockIn` | Lock in | Lås inn |
| `write.error.tooLong` | That's a bit long. Use 30 characters at most. | Det er litt langt. Bruk høyst 30 tegn. |
| `write.error.tooManyWords` | Use 3 words at most. | Bruk høyst 3 ord. |
| `write.error.noLetters` | Use at least one letter. | Bruk minst én bokstav. |
| `write.error.characters` | Use only letters, numbers, spaces, hyphens and apostrophes. | Bruk bare bokstaver, tall, mellomrom, bindestrek og apostrof. |
| `write.error.repeat` | You've already used %@ in this game. | Dere har allerede brukt %@ i dette spillet. |
| `partner.locked` | %@ locked in | %@ har låst inn |
| `partner.typing` | %@ is typing | %@ skriver |
| `partner.here` | %@ is here | %@ er her |
| `partner.later` | %@ will answer later | %@ svarer senere |
| `stats.melds` | %lld meld / %lld melds | %lld treff |
| `stats.melds.a11y` | %lld melds together | %lld treff sammen |

### 2. Waiting

Purpose. Say that the word is safe and the reveal is coming, and make the wait feel shared.

Layout, centered.

1. My card, face up, smaller (`MindMeldWordCard`, 0.8 scale), with `lock.fill` and my word.
2. The partner's card next to it, face down, with a soft breathing glow while the partner is in the game (`.paeoniaAccentPrimary` 0.2 to 0.5 over 2.4 s). The face-down side shows the petal mark. Reduce Motion: still glow at 0.35.
3. Title. "[Name] is typing" while live typing, "Waiting for [Name]" otherwise.
4. Hint. "We'll show both words at the same time." When the partner is away: "We'll tell you when [Name] locks in."
5. The offline line when the lock-in is still on the phone.
6. Toolbar, only while the partner is not in the game: the invite bell at the leading edge of the toolbar.

When the partner locks in while this screen is open, the reveal starts at once.

| Key | English | Norwegian |
|---|---|---|
| `wait.title` | Waiting for %@ | Venter på %@ |
| `wait.hintLive` | We'll show both words at the same time. | Vi viser begge ordene samtidig. |
| `wait.hintLater` | We'll tell you when %@ locks in. | Vi sier fra når %@ har låst inn. |
| `wait.yourWord.a11y` | Your word, %@, locked in | Ordet ditt, %@, er låst inn |
| `wait.partnerCard.a11y` | %@'s word, hidden until you both lock in | Ordet til %@, skjult til dere begge har låst inn |
| `offline` | Saved on this phone. We'll send it when you're online. | Lagret på telefonen. Vi sender det når du er på nett. |

### 3. Reveal

Purpose. The best three seconds of the game. Two minds, one moment.

Two cards side by side (`MindMeldWordCard`), mine leading. Each card is `radius20`, at most 160 pt wide and 200 pt tall, with an avatar above it. Face down shows the petal mark on `.paeoniaSurfaceSecondary`. Face up shows the word in capitals (`PaeoniaTypography.title`, `minimumScaleFactor(0.5)`, up to two lines) on `.paeoniaSurfacePrimary`.

Beats, in seconds after the reveal starts.

| Time | What happens |
|---|---|
| 0.00 | Both cards face down. The glow behind them rises from 0.16. |
| 0.25, 0.58, 0.86 | Three build-up beats that speed up into the flips. Both cards pulse to 1.035, 1.05 and 1.065 and back, each with `streakTick` 0.3, 0.5, 0.7. The glow rises 0.05 with each beat. |
| 1.10 | My card flips (a 3D turn around the vertical axis, 0.4 s). `streakTick(0.85)`. |
| 1.55 | The partner's card flips. `streakTick(0.85)`. |
| 2.10 | The verdict. See below. A near miss or a miss lets the glow fall back to 0.16. |
| 2.34 | A meld's cards touch. |
| 2.60 | Title and line fade up (`celebrationReveal`). |
| 3.00 | Buttons appear. |

Verdict.

- **Meld.** At 2.10 the cards speed up into each other (0.24 s, an ease-in curve, like two magnets). The partner's card stays solid and slides under mine. At 2.34 they touch: the partner's card hides, the card swells to 1.07 and back, the borders turn `.paeoniaSuccess`, the glow peaks at 0.40, and a big petal bloom bursts from the merged card (`GamePetalBloom` at intensity 1.6, seeded by the round id). `streakCelebrated()` and the win sound play on the touch, not at 2.10. At 2.60 the title "You melded!" and "In 4 rounds". At 2.90 the stats line, with `streakContinued()`: "Meld number 3. Your fewest is 2 rounds.", "Your first meld." for the first one, or, on a new record, "Your fewest rounds yet." in `.paeoniaAccentPrimary`.
- **Near miss.** The cards reach for each other on a bouncy spring, nearly touch, and settle 13 pt closer each, and their borders turn `.paeoniaAccentPrimary`. `streakContinued()`. Title "So close!", line "OCEAN and OCEANS are almost the same word.", and a quiet "Count it" button next to the primary.
- **Miss.** The cards stay apart and a thin line draws between them with a small `plus` in the middle (`motionMorph`). `partnerDrawingReceived()`. Title "Now find the link", line "What connects OCEAN and SUSHI?".
- **Got away** (round 10, miss). As a miss, then title "This one got away" and line "You came close. Want to try another?". A near miss in round 10 shows "So close!" with "Count it" and "Play again".

Everything is tappable from 2.60. A tap on the screen jumps to the settled state, as `DrawAndGuessRevealTimeline.skip` does, without repeating haptics. Reduce Motion: no pulses, flips, slides or bloom. The settled state shows at once with only the verdict haptic.

Buttons.

- Miss and near miss: primary "Next round". A near miss adds "Count it" (`PaeoniaQuietButtonStyle`). "Count it" turns the reveal into a meld in place. The near title and buttons fade out in 0.16 s, then the meld plays with the same gaps as above: the cards slide together, touch 0.24 s later with the bloom and `streakCelebrated()`, and "You melded!" fades up 0.5 s after the slide began.
- Meld and got away: primary "Play again", and a quiet "See our melds".

Leaving the reveal (Next round, Play again, or back) marks it seen once its verdict has shown. A reveal left before the verdict plays again next time.

VoiceOver. On the verdict, one announcement: "You said OCEAN. Robin said SUSHI. Not a match yet." or "You both said FISH. You melded!" Focus moves to the title. The cards are one element each after the flip: "You, OCEAN", "Robin, SUSHI". The bloom and glow are hidden.

| Key | English | Norwegian |
|---|---|---|
| `reveal.you` | You | Du |
| `reveal.meld.title` | You melded! | Dere tenkte likt! |
| `reveal.meld.rounds` | In %lld round / In %lld rounds | På %lld runde / På %lld runder |
| `reveal.meld.counted` | %@ counted it. | %@ telte det med. |
| `reveal.meld.countedByYou` | You counted it. | Du telte det med. |
| `reveal.meld.number` | Meld number %lld. | Treff nummer %lld. |
| `reveal.meld.fewest` | Your fewest is %lld round. / Your fewest is %lld rounds. | Det raskeste dere har klart er %lld runde. / ... %lld runder. |
| `reveal.meld.first` | Your first meld. | Deres første treff. |
| `reveal.meld.record` | Your fewest rounds yet. | Det raskeste dere har klart så langt. |
| `reveal.near.title` | So close! | Så nære! |
| `reveal.near.line` | %1$@ and %2$@ are almost the same word. | %1$@ og %2$@ er nesten samme ord. |
| `reveal.near.count` | Count it | Tell det med |
| `reveal.miss.title` | Now find the link | Finn det som binder dem |
| `reveal.miss.line` | What connects %1$@ and %2$@? | Hva binder %1$@ og %2$@ sammen? |
| `reveal.gotAway.title` | This one got away | Denne gangen gikk det ikke |
| `reveal.gotAway.line` | You came close. Want to try another? | Dere var nære. Vil dere prøve igjen? |
| `reveal.next` | Next round | Neste runde |
| `reveal.playAgain` | Play again | Spill igjen |
| `reveal.seeMelds` | See our melds | Se treffene våre |
| `reveal.missAnnouncement` | You said %1$@. %2$@ said %3$@. Not a match yet. | Du sa %1$@. %2$@ sa %3$@. Ikke likt ennå. |
| `reveal.meldAnnouncement` | You both said %@. You melded! | Dere sa begge %@. Dere tenkte likt! |
| `reveal.card.a11y` | %1$@, %2$@ | %1$@, %2$@ |
| `reveal.card.facedown.a11y` | [Name]'s word, hidden | Ordet til [Name], skjult |

### 4. Game over

When a person opens a game whose ending they have already seen, the screen shows the settled reveal of the last round, with the trail above the cards and "Play again". A partner whose game was started over by the other partner sees the new game's write phase with a one-time line above the title: "[Name] started a new game." That marks the old game's end as seen.

| Key | English | Norwegian |
|---|---|---|
| `restart.menu` | Start over | Begynn på nytt |
| `restart.title` | Start a new game? | Begynne et nytt spill? |
| `restart.message` | This game ends, and you both start again at round 1. | Dette spillet slutter, og dere begynner på runde 1 igjen. |
| `restart.confirm` | Start over | Begynn på nytt |
| `restart.cancel` | Keep playing | Fortsett å spille |
| `restart.partnerNote` | %@ started a new game. | %@ begynte på et nytt spill. |
| `menu.a11y` | More options | Flere valg |
| `offline.title` | You're offline | Du er ikke på nett |
| `offline.message` | Connect to the internet to start a game. | Koble til internett for å starte et spill. |

### 5. Our melds

Entry points: the melds capsule in the toolbar of `MindMeldScreen`, "See our melds" on a finished reveal, and a quiet link on the hub card once the couple has a finished game.

Layout, in one scroll view.

1. Records. Two values side by side in `PaeoniaTypography.countdownNumber`: melds, and fewest rounds ("Not yet" in `.paeoniaTextTertiary` without a meld).
2. The list. One row per finished game, newest first, as in "History". Rows have `.paeoniaSurfaceSecondary` and `radius16`. Tapping pushes the detail.

Detail. The trail, top to bottom, with a header ("Melded in 4 rounds · Oct 12", "Got away · Oct 12" or "Started over · Oct 12"). Each round row has my word leading and the partner's trailing, both in capitals, with the round number as an eyebrow. The two chips touch the ends of a line in the middle of the row, and the line gets shorter each round, from 120 pt to 16 pt. A meld ends with one merged chip in `.paeoniaSuccess` with the petal mark.

Empty states use `PaeoniaEmptyStateView`: no finished games yet (`point.3.connected.trianglepath.dotted`, "No melds yet", "Your finished games will show up here."), and offline with nothing cached (the shared offline state).

| Key | English | Norwegian |
|---|---|---|
| `history.title` | Our melds | Treffene våre |
| `history.records.melds` | Melds | Treff |
| `history.records.fewest` | Fewest rounds | Færrest runder |
| `history.records.none` | Not yet | Ikke ennå |
| `history.row.rounds` | %lld round / %lld rounds | %lld runde / %lld runder |
| `history.row.gotAway` | Got away | Gikk ikke |
| `history.row.startedOver` | Started over | Begynt på nytt |
| `history.detail.melded` | Melded in %lld round / Melded in %lld rounds | Likt på %lld runde / Likt på %lld runder |
| `history.detail.counted` | Counted | Telt med |
| `history.empty.title` | No melds yet | Ingen treff ennå |
| `history.empty.message` | Your finished games will show up here. | Spillene dere har fullført, dukker opp her. |
| `history.loadMore.failed` | We couldn't load older games. | Vi kunne ikke laste eldre spill. |
| `history.offline.message` | Connect to the internet to see your finished games. | Koble til internett for å se spillene dere har fullført. |
| `history.detail.round` | Round %lld | Runde %lld |

### Hub card

`MindMeldHubCard` follows the Draw & Guess card: the picture behind the whole card, with the partner-here chip and the stats capsule over its scene, then the title, a status line, the primary button and the "Our melds" link.

Artwork (`MindMeldHubArtwork`). Two blank word cards leaning together, one edged in each partner's color. The beat opens a peony where their tops meet. It follows `docs/games/hub-artwork.md`.

| State | Status line | Button |
|---|---|---|
| No game yet | Say a word at the same time. Meet in the middle. | Play |
| Nobody locked in | Round 3. Pick your word. | Play |
| The partner locked in | [Name] locked in. Your turn. | Pick your word |
| I locked in | Waiting for [Name]. | Open |
| Unseen reveal | Your words are in. | See your words |
| Game over, seen | You melded in 4 rounds. / This one got away. | Play again |

"Your turn" (the badge and the card's accent border) means the partner locked in and I haven't, or a reveal or an ending waits for me. A round nobody has locked in is not anybody's turn, so it does not badge.

| Key | English | Norwegian |
|---|---|---|
| `hub.status.new` | Say a word at the same time. Meet in the middle. | Si et ord samtidig. Møtes på midten. |
| `hub.status.open` | Round %lld. Pick your word. | Runde %lld. Velg ordet ditt. |
| `hub.status.partnerLocked` | %@ locked in. Your turn. | %@ har låst inn. Din tur. |
| `hub.status.waiting` | Waiting for %@. | Venter på %@. |
| `hub.status.reveal` | Your words are in. | Ordene deres er klare. |
| `hub.status.melded` | You melded in %lld round. / You melded in %lld rounds. | Dere tenkte likt på %lld runde. / Dere tenkte likt på %lld runder. |
| `hub.status.gotAway` | This one got away. | Denne gangen gikk det ikke. |
| `hub.play` | Play | Spill |
| `hub.pick` | Pick your word | Velg ordet ditt |
| `hub.open` | Open | Åpne |
| `hub.seeWords` | See your words | Se ordene |

### Wide layouts and Dynamic Type

- The cards sit side by side at every size. At accessibility text sizes they grow in height, and the screen scrolls with the button pinned.
- Wide (700 pt or more and wider than tall): the write and waiting phases keep the focused width, centered. The reveal grows the cards to at most 220 pt wide.
- iPad keeps the tab bar, as in Draw & Guess.

## Data

The functions are in `backend/convex/mindMeld.ts`, the rules and table definitions in `backend/convex/lib/mindMeld.ts`.

- `mind_meld_games`: one row per game. `game_number` counts up per couple. `state` is `playing`, `melded` or `ended`. An ended game has `end_reason` (`rounds` or `restart`) and `ended_by_user_id` for a restart. `end_seen_by_user` maps a user id to the first time that person saw the ending. `version` goes up with every change to the game or its rounds.
- `mind_meld_rounds`: one row per round. `state` is `open` or `revealed`. A revealed round has `outcome` (`match`, `near` or `miss`) and, when a partner counted a near miss, `counted_by_user_id`. `waiting_since` is set while exactly one partner has locked in, and `reminder_sent_at` once its reminder went out.
- `mind_meld_words`: one row per partner and round. It holds the word as typed, its match key, `locked_at`, and `reveal_seen_at`.

Functions.

- `get_mind_meld` (query, no arguments): the caller's view. `current` is the couple's newest game. `previous` is the game before it while the caller has not seen its ending. Each game carries its rounds, oldest first. A round carries `my_word`, `my_locked_at`, `partner_locked`, `partner_locked_at`, `partner_word` (only when revealed), `outcome`, `counted_by_user_id`, `revealed_at` and `my_reveal_seen_at`. A game carries `my_end_seen_at`. `stats` has `melds`, `fewest_rounds` and `games` (finished games). The read never returns the partner's word for an open round.
- `start_mind_meld_game`: starts a new game at round 1 unless a game is in play, and returns the game in play either way.
- `lock_mind_meld_word` (client operation): `p_round_id`, `p_word`. Checks access, that the round is open and its game in play, the word rules, repeats, and that the caller has not locked in. The second lock-in reveals the round, decides the outcome, ends the game on a match or after round 10, and otherwise opens the next round. Counts toward the streak. Queues the turn or result push.
- `count_mind_meld_round`: `p_round_id`. The latest revealed round of its game, with a near-miss outcome, in a game that is in play or ended after round 10. Sets `counted_by_user_id`, melds the game, and deletes the next open round with any word locked in for it. Safe to repeat.
- `mark_mind_meld_reveal_seen` (`p_round_id`) and `mark_mind_meld_end_seen` (`p_game_id`): keep the first time. Safe to repeat.
- `restart_mind_meld`: `p_game_id`. Ends that game if it is still in play (reason `restart`), marks its end seen for the caller, and starts a new game. When the game already ended and a newer one is in play, it returns the newer one.
- `get_mind_meld_history`: `p_before_game_number`, `p_limit` (capped at 50). Finished games, newest first, with their revealed rounds, and `next_before_game_number`.
- `send_due_mind_meld_reminders` (internal, cron every 15 minutes): one reminder per round, 72 hours after `waiting_since`.

Errors follow Draw & Guess so the app's refusal handling works: `42501` for access, `23514` for rules ("this round is already finished", "that word was already used in this game", "word must be 1 to 30 characters in at most three words"), `23505` for "you already locked in a word this round".

Relationship cleanup deletes the three tables with the other game rows.

## iOS

- **Folder.** `Features/Games/MindMeld/` with `Models/`, `Data/`, `Game/` (view model, resolver), `Words/` (word rules, starter words), `Screen/` (phases and components), `Reveal/` (timeline and script), `History/` and `Hub/`. Tests in `PaeoniaAppTests/Games/MindMeld/`.
- **Local first.** Lock in, Count it, and "seen" marks go into the pending operations before anything is sent. The resolver applies queued moves on top of the server's state, so a lock-in shows at once. Starting and restarting a game need a connection, as creating the Draw & Guess game does.
- **Order.** A lock-in waits for this person's earlier lock-ins. A seen mark waits for this person's lock-in of that round. A refused lock-in (round finished, repeat, rules) drops and shows "Your word wasn't sent", and the field comes back with the word in it.
- **Cache.** `MindMeldCache` keeps the last `get_mind_meld` result and the first history page per person, in its own file. It never takes a state that is behind the one it holds: a lower `game_number`, or the same game with a lower `version`.
- **Live feed.** `MindMeldLiveFeed` subscribes to `mindMeld:get_mind_meld` and writes into the cache.
- **Live room.** One `WidgetLiveDrawing` connection on the `mind_meld` channel, used only for presence and a `GameLiveChannel<MindMeldLiveMessage>`.
- **Seen.** A reveal counts as seen when the server has `my_reveal_seen_at` or a seen mark waits on this phone.

## Open questions

- The "Surprise me" lists need a native speaker's read before release.
