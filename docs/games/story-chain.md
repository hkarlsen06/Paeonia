# Story Chain

Design for the third built game. The two partners write one story together, one or two sentences at a time. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Story Chain.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-13.

- **Name.** "Story Chain" in English and "Skrivestafett" in Norwegian. A skrivestafett is the Norwegian school exercise where people take turns writing a story.
- **Async first, with live letters.** Each partner writes a line whenever they like. When both have the game open, the waiting partner watches every letter as it is typed, deletions included. A sent line arrives on both phones at once with a write-in animation.
- **The writer always knows.** While the partner watches, the writer sees "[Name] is reading along" with the partner's avatar and a breathing ring. There is no setting to hide typing.
- **Openings.** A new story starts with a choice of three opening lines written by Paeonia in the couple's game language, or with the starter's own first line.
- **The dare word.** After writing a line, the writer may give the partner a word that the partner's next line must use. The writer picks one of three words Paeonia suggests, or types their own. It is optional on every turn.
- **The dare check.** A line uses the word when the line contains it, ignoring case. "hunden" and "gårdshund" both count for "hund". The phone and the server run the same check, and Send stays off until the word is used.
- **Length.** A line is 2 to 240 characters. The composer asks for "one or two sentences" and counts characters, not sentences.
- **The end.** From the 8th line on, the writer can make their line the last one. Line 20 is always the last.
- **The title.** The partner who did not write the last line names the story (1 to 40 characters), then starts the next one.
- **Lines are final.** There is no undo after sending.
- **No points.** Story Chain ignores the play style. A story has no winner. The hub card counts the stories the two of you have finished.
- **Streak.** Sending a line counts toward the couple's streak. Naming a story alone does not.
- **Reading.** The story reads as one flowing page in the system serif. Each partner's sentences have their own ink, Paeonia's opening is muted italic, and a dared word has a gold underline. Tapping a sentence shows who wrote it and when.
- **Pushes.** Five kinds, none showing story text: your turn, the last line was written, the story was named, an invite, and one reminder after 72 hours.
- **History.** Finished stories are kept in "Our stories" with private stars, like "Our drawings".

## Why this game

- It works across time zones. A line takes a minute, and the story grows over days.
- It becomes the couple's own: inside jokes, places, the dare words they give each other. Quality bar item 3 asks for exactly that.
- Live letters turn it into improv when both are online, and nothing is lost when only one is.

## The story

A couple has one ongoing Story Chain game. The game always holds one current story.

### Starting a story

The partner who opens Story Chain first starts the first story. After that, the partner who names a story starts the next one.

1. The starter sees three opening lines and a fourth choice, "Start with your own line".
2. Picking an opening and tapping "Start writing" starts the story in Convex. The opening shows at the top of the page, and the starter writes line 1 under it.
3. Picking "Start with your own line" starts a story without an opening. The starter's line 1 is the first sentence.

The three openings come from the couple's game language. They are fixed for the turn: reopening the game shows the same three. An opening the couple already started a story with is not offered again until the list runs out, then the list starts over. A language change shows openings in the new language at once.

The opening is not a line. It belongs to nobody, and it does not count toward the 8 and 20 line limits.

### Writing a line

- A line is 2 to 240 characters after trimming. Line breaks and runs of spaces become one space, so a line is always one run of prose. Characters are counted as Unicode code points on both sides.
- The writer sees the whole story above the composer. There is no hidden information.
- Send is off while the line is too short, too long, or missing the dare word.
- When the line is sent, the turn passes to the partner.

### The dare word

- Below the composer, "Give [Name] a word" opens a small picker with three suggested words and a field for your own word. Choosing one shows it as a chip, "[Name] must use LIGHTHOUSE", with a button to remove it.
- The three suggestions come from the couple's game language and are fixed for the turn. A word the couple already dared is not suggested again until the list runs out.
- An own word is one word of 2 to 20 letters. Any letters are allowed, so "café" and "smørbrød" work. It is stored lowercase.
- The dare goes out with the line. The partner sees it at the top of their composer: "Use the word LIGHTHOUSE". The chip turns to a check once the draft contains the word.
- The check: lowercase both sides, normalize to NFC, and test whether the line contains the word. Because a dare word is letters only, "the line contains it" and "a word in the line contains it" are the same test.
- The last line can't carry a dare, because nobody writes after it.
- When the line that used the dare is sent, the word in it gets a gold underline on the page, for good.

### Ending

- From line 8 on, the composer shows a switch, "Make this the last line". It is off by default.
- Line 20 is always the last. The composer says "Write the last line" and the switch is on and locked.
- A last line ends the writing. The turn passes to the partner, who names the story.

### Naming

- The partner who did not write the last line sees the whole story and a title field, "Give it a title", 1 to 40 characters.
- "Name the story" finishes the story. The namer sees the finished story reveal, then "Start a new story" begins the next one with their opening choice.
- The partner who wrote the last line gets a push that the story has a name. Opening the game shows them the same reveal first, then "Continue".
- Each partner's "I have seen this finished story" is stored on the story, so a second phone does not show the reveal again. The namer's mark is set when they name it.

## Live

Live runs whenever both partners have the game screen open. Without the partner, everything works the same, only slower.

- **Presence.** The screen joins the game's relay room through `WidgetLiveDrawing`, used only for presence (no canvas). The `hello` role says what the screen shows:
  - `drawing`: writing a line (my turn, on the composer).
  - `watching`: reading the story while the partner writes.
  - `choosing`: picking an opening, or naming a story.
  - `result`: looking at a finished story.
  - `present`: anywhere else in the game.
- **Live letters.** While writing, the phone sends `StoryChainLiveMessage` on the game's `GameLiveChannel`: the story id, the line number, the draft as typed, and whether it is set to be the last line. It sends the whole draft on every change, at most every 50 ms, and again when the partner arrives. Nothing in it is saved.
- **The reader's page.** The partner's draft shows at the end of the page in the partner's ink at reduced opacity, with a blinking caret. Deletions show too. A draft older than 10 seconds without an update fades out, so a writer who left without sending leaves no ghost behind.
- **Sending live.** The writer's phone sends a final message with the line id and `sent: true` the moment Send is tapped. The reader's page plays the arrival right away, before Convex confirms. When the Convex update arrives with the same line id, nothing moves. The reader's composer opens only once Convex says it is their turn.
- **The dare stays a surprise.** The live message never carries the dare word. The reader learns it when their turn opens.
- **Invite.** When the partner isn't in the game, "Tell [Name] you want to play" shows, as in every live game.

## Play style and streak

- Story Chain has no score in either play style.
- Sending a line records `game_turn_completed` with the line id as the dedupe key. Naming a story does not count on its own.

## Content

Openings and dare words are hand-written for each language and live in `backend/games/story-chain/`. Norwegian is not a translation of English.

- `openings/en.json` and `openings/nb.json`: `{ "language": "en", "openings": [{ "id": "...", "text": "..." }] }`. About 40 per language to start.
- `words/en.json` and `words/nb.json`: `{ "language": "en", "words": [{ "id": "...", "text": "..." }] }`. About 120 per language to start.
- `lib/storyChain.test.ts` checks both lists against the rules below.

Rules for openings:

- Follow the voice rule in `docs/couple-question-guidelines.md`. An opening comes from Paeonia, never from a partner. Write in third person about invented characters and places. No "I", "me", "we", "our", and no "you". In Norwegian, no "jeg", "meg", "vi", "vår", "du" or "deg".
- One sentence, at most 120 characters, ending with a period.
- Concrete and open: an object, a place, a small mystery. Something a 16-year-old can continue at once.
- Warm, curious, or funny. Nothing scary, sad, sexual, or about real people.

Rules for dare words:

- Single concrete nouns, 4 to 14 letters, lowercase, that any 16-year-old knows.
- The check is "the line contains the word", so a word must still match its common forms. Avoid nouns whose plural or definite form changes the stem: English "knife", "mouse", "story", "city", and Norwegian "bok", "mann", "hånd", "sykkel", "nøkkel".
- No slurs, no words with a crude second meaning. A native speaker reads every word before it ships (see the "pakkis" note in `docs/games/draw-and-guess.md`).

## History and stars

- **Our stories.** Every finished story, newest first, paged by story number, 30 a page. A filter shows starred stories only. Each entry has the title, the first line, the date it finished, the number of lines, and whether I starred it.
- **Stars.** Either partner can star or unstar a finished story. A star is private. The server returns only the caller's own stars.
- **The detail.** A story opens as the finished page: title, byline, the full text, the end mark, and the star in the toolbar.
- Stars and stories are deleted with the rest of the couple's game rows.

## Data

The functions are in `backend/convex/storyChain.ts` and the rules in `backend/convex/lib/storyChain.ts`.

- `story_chain_games`: one row per couple, created by `ensure_story_chain_game` (the caller starts). `state` is `choosing_opening`, `writing` or `titling`. `turn_user_id` is the partner who acts next. The row also holds `turn_number` (seeds the suggestions), `current_story_id`, `story_count`, `finished_count`, `turn_started_at`, `turn_reminder_sent_at` and `version`. `version` goes up with every change.
- `story_chain_stories`: one row per story. It holds `story_number`, `starter_user_id`, the opening (`opening_id`, `opening_text`) when there is one, `state` (`writing`, `titling` or `finished`), and the `lines`. A line is `{ id, number, author_user_id, text, dare_word?, dare_word_id?, created_at }`, where `dare_word` is the word this line gave to the next line. A finished story adds `last_line_user_id`, `title`, `titled_by_user_id`, `finished_at`, and `seen_by` (the user ids that saw the finished story). The client creates the story id and each line id, so a line queued offline can name its story.
- `story_chain_stars`: one row per partner and starred story, with the story number so one partner's stars page in order.
- `story_chain_used`: the openings and words the couple has already used, per language. A kind starts over when all its entries were used.

Functions:

| Function | Kind | Args | Result |
|---|---|---|---|
| `ensure_story_chain_game` | mutation | | `{ game_id, created }` |
| `get_story_chain` | query | | `{ user_id, partner_user_id, couple_id, game, current_story, previous_story, opening_choices, word_choices }` |
| `get_story_chain_story` | query | `p_story_id` | story or null |
| `start_story` | mutation, client op | `p_game_id, p_story_id, p_opening_id?` | `{ story_id, story_number }` |
| `add_story_line` | mutation, client op | `p_story_id, p_line_id, p_text, p_is_last, p_dare_word?, p_dare_word_id?` | `{ line_id, number, story_state }` |
| `name_story` | mutation, client op | `p_story_id, p_title` | `{ story_id, title }` |
| `mark_story_seen` | mutation | `p_story_id` | `{ story_id }` |
| `set_story_star` | mutation | `p_story_id, p_starred` | `{ story_id, starred }` |
| `get_story_chain_history` | query | `p_starred_only, p_before_story_number?, p_limit` | `{ stories, next_before_story_number }` |

- `opening_choices` and `word_choices` go only to the partner whose turn it is, in the states that use them. They are computed in the query: a seeded pick from the unused entries of the couple's language, seeded by the game id and `turn_number`. The query reads no clock, and a language change recomputes them, so nothing is stored or redrawn.
- `current_story` is the story with the highest number. `previous_story` is the one before it, so a partner who missed a reveal still sees it after the next story started.
- `add_story_line` checks, in order: couple access, the story is current and `writing`, it is the caller's turn, the line text, the line number (the server assigns it), the dare word of the previous line when there is one, the end rules (`p_is_last` from line 8, forced on line 20), and the dare rules (none on a last line, a valid word). A list word (`p_dare_word_id`) takes its text from the list.
- Pushes go through `enqueueGamePush`. Turn pushes skip a partner who has the game open.
- Relationship cleanup deletes every Story Chain row through the game registry.

## Notifications

None of these show story text, a title, or a dare word. The payload holds ids and the deep link `paeonia://games/story-chain`.

| Moment | Push kind | English | Norwegian |
|---|---|---|---|
| A line arrives | `game_turn_ready` | Your turn in Story Chain / Open Paeonia to read the newest line. | Din tur i Skrivestafett / Åpne Paeonia for å lese den nyeste linjen. |
| The last line arrives | `game_turn_ready`, step `last_line` | [Name] wrote the last line / Open Paeonia to give your story a title. | [Name] skrev den siste linjen / Åpne Paeonia for å gi historien en tittel. |
| The story was named | `game_result` | [Name] named your story / Open Paeonia to read it. | [Name] ga historien deres en tittel / Åpne Paeonia for å lese den. |
| Invite | `game_invite` | [Name] wants to play Story Chain with you | [Name] vil spille Skrivestafett med deg |
| 72 hours waited | `game_turn_reminder` | Your turn in Story Chain | Din tur i Skrivestafett |

- The turn and named pushes are skipped while the recipient has the game open.
- A turn push names the line that passed the turn (`round_id`). The drain drops it once that line is no longer the newest of the current story or the turn moved on, so a push that waited while the turn went around never counts for a later turn. A named push names the story and is dropped once its last writer has seen it.
- The last line push uses the `steps` copy of `GAME_PUSH_COPY` (`step: "last_line"`), a seam the foundation added on 2026-10-13 at Story Chain's request.
- The single reminder is per turn. Starting a story does not start a new turn, so a reminder sent while the starter picked an opening is not repeated after they start.

## Screens

Copy keys start with `storyChain.`, and the tables list only the part after it. "[Name]" is the partner's display name. Norwegian is Bokmål.

### Shell

- One screen, `StoryChainScreen`, opened from the Games tab and from pushes. It shows one phase at a time, picked by `StoryChainResolver` from the game, the current and previous story, the queued moves, and my user id.
- Look. `.paeoniaBackgroundSecondary`, dark toolbar, inline title "Story Chain" / "Skrivestafett", like Draw & Guess. Toolbar trailing: "Our stories" (`books.vertical`), and the star on a finished story.
- Phase change. Cross-fade plus a 12 pt rise over `meaningfulMoment`. Reduce Motion: cross-fade over `motionFast`.
- The page stays in place across writing, waiting and naming, so the story never jumps when the turn passes. Only the bottom changes.

### The page

The page is the heart of the game, so it gets the care a book would.

- Type. The system serif (`design: .serif`) at the `title3` text style, regular weight, line spacing 6, scaling with Dynamic Type. Measure is capped at 560 pt, centered.
- Inks. My lines are `.paeoniaTextPrimary` (blush). My partner's lines are `.paeoniaAccentPrimary` (petal pink, 7.2:1 on the background). So on both phones, the partner's voice is the pink one. Paeonia's opening is `.paeoniaTextSecondary` italic.
- Flow. All lines run together as one paragraph, each followed by a space. A line never starts a new paragraph.
- Dared word. A gold (`paeoniaInkGold`) underline under the word inside the line that used it.
- Header. Eyebrow "Story 4" (`caption` bold, uppercase, tracking 1.4, `.paeoniaTextTertiary`), then the title on a finished story.
- Who wrote it. Tapping a line shows a small popover: avatar, "Robin · Tue 21:04", and "Used LIGHTHOUSE" when the line used a dare. `StoryChainPageText` hit-tests the tap against the line runs it laid out.
- New lines arriving. A line the partner wrote since my last turn writes itself in when the page opens: word by word, each word rising 4 pt from a soft blur to sharp over 0.35 s, 45 ms apart, compressed so a line takes 1.6 s at most. `partnerDrawingReceived()` fires when it lands. A live line does the same at the moment the writer taps Send. Reduce Motion: the line fades in over `motionDefault`.
- My own line. On Send it writes itself into the page the same way, a little faster (30 ms per word), with `drawingSent()`.
- VoiceOver. Each line is one element: "Robin: It opened nothing in town, so she took the night bus to the coast." The opening reads "Opening: ..." The page has a rotor of lines.

### 1. Choose an opening

| Key | English | Norwegian |
|---|---|---|
| `choose.title` | Start a new story | Start en ny historie |
| `choose.subtitle` | Pick a first line. Then you and [Name] take turns adding one or two sentences. | Velg en første linje. Så bytter du og [Name] på å skrive én eller to setninger. |
| `choose.own` | Start with your own line | Start med din egen linje |
| `choose.own.subtitle` | Write the first sentence yourself. | Skriv den første setningen selv. |
| `choose.start` | Start writing | Begynn å skrive |
| `choose.offline.message` | Connect to the internet to get your opening lines. | Koble til internett for å få åpningslinjene. |

- Title in `heroTitle`, subtitle `.paeoniaTextSecondary`.
- Three opening rows: `radius16`, `.paeoniaSurfaceSecondary`, the opening in serif italic `title3`. A selected row gets an accent `strokeEmphasis` border and `checkmark.circle.fill`, with `selection()`.
- The own-line row has `square.and.pencil`.
- Pinned bottom: "Start writing", disabled until a row is selected. Tapping queues `start_story` with `drawingSent()` and moves to writing at once.
- With the turn mine and no openings loaded (offline), the rows show the `wifi.slash` empty state with Try again. "Start with your own line" still works, and the start waits in the queue.

### 2. Writing

- The page, then the composer as the last paragraph of the page: a borderless serif field in my ink, placeholder "What happens next? One or two sentences." in `.paeoniaTextTertiary`. On line 1 without an opening the placeholder is "Write the first line."
- Above the field, when my partner dared me: a capsule "Use the word LIGHTHOUSE" with `textformat`, gold outline. It turns to `checkmark.circle.fill` in `.paeoniaSuccess` once the draft contains the word, with `selection()`.
- Live row above the composer: "[Name] is reading along" (avatar 24 pt with ring) while the partner is `watching`; "[Name] is here" while in the game; "[Name] will read it later" when away.
- Pinned bar above the keyboard, left to right: "Give [Name] a word" (quiet, `textformat.abc`) or the dare chip "[Name] must use ANCHOR" with an x; the last-line switch from line 8; the counter from 200 characters ("212/240", turns `.paeoniaErrorText` past 240); the round Send button (`arrow.up`, 44 pt hit area).
- The dare picker is a sheet at `.medium` detent: title "Give [Name] a word", subtitle "Their next line has to use it.", three word rows, and "Your own word" with a field. Choosing closes the sheet.
- Send is off with a hint line under the field: "Use LIGHTHOUSE to send." when the dare is missing, nothing otherwise.
- A line sent offline shows in the page with the offline line "Saved on this phone. We'll send it when you're online."

| Key | English | Norwegian |
|---|---|---|
| `write.placeholder` | What happens next? One or two sentences. | Hva skjer videre? Én eller to setninger. |
| `write.placeholderFirst` | Write the first line. | Skriv den første linjen. |
| `write.lastLinePrompt` | Write the last line. | Skriv den siste linjen. |
| `write.mustUse` | Use the word %@ | Bruk ordet %@ |
| `write.mustUseHint` | Use %@ to send. | Bruk %@ for å sende. |
| `write.readingAlong` | [Name] is reading along | [Name] leser med |
| `write.here` | [Name] is here | [Name] er her |
| `write.later` | [Name] will read it later | [Name] leser det senere |
| `write.giveWord` | Give [Name] a word | Gi [Name] et ord |
| `write.dareChip` | [Name] must use %@ | [Name] må bruke %@ |
| `write.dareRemove.a11y` | Remove the word | Fjern ordet |
| `write.lastLine` | Make this the last line | Gjør dette til siste linje |
| `write.send` | Send | Send |
| `write.send.a11y` | Send to [Name] | Send til [Name] |
| `write.count.a11y` | %1$lld of %2$lld characters | %1$lld av %2$lld tegn |
| `dare.title` | Give [Name] a word | Gi [Name] et ord |
| `dare.subtitle` | Their next line has to use it. | Neste linje må bruke det. |
| `dare.own` | Your own word | Ditt eget ord |
| `dare.own.placeholder` | One word | Ett ord |
| `dare.own.error` | Use one word of 2 to 20 letters. | Bruk ett ord på 2 til 20 bokstaver. |

### 3. Waiting while the partner writes

- The page stays. Under it, the partner's live draft when they write live.
- Bottom, one line of status: "[Name] is writing" with three breathing dots while the live draft is moving; "[Name] is here" in the game; "Waiting for [Name]" with "We'll tell you when it's your turn." when away, plus the invite bell at the leading edge of the toolbar.
- When the partner's line lands and the turn is mine, the composer rises in (`cardReveal`) with the dare capsule if there is one.

| Key | English | Norwegian |
|---|---|---|
| `wait.writing` | [Name] is writing | [Name] skriver |
| `wait.writingLast` | [Name] is writing the last line | [Name] skriver den siste linjen |
| `wait.generic` | Waiting for [Name] | Venter på [Name] |
| `wait.hint` | We'll tell you when it's your turn. | Vi sier fra når det er din tur. |
| `wait.opening` | [Name] is picking an opening | [Name] velger en åpning |
| `wait.startNext` | Waiting for [Name] to start a new story | Venter på at [Name] skal starte en ny historie |
| `wait.naming` | [Name] is naming your story | [Name] gir historien en tittel |

### 4. Naming

- The page with the whole story, then a centered ornament (`camera.macro`) and the title field: serif `title2`, centered, placeholder "Give it a title", counter "12/40".
- Pinned bottom: primary "Name the story", disabled while empty.
- The partner sees the page with "[Name] is naming your story".

| Key | English | Norwegian |
|---|---|---|
| `name.prompt` | [Name] wrote the last line. Give your story a title. | [Name] skrev den siste linjen. Gi historien en tittel. |
| `name.placeholder` | Give it a title | Gi den en tittel |
| `name.action` | Name the story | Gi historien tittel |

### 5. The finished story

The reveal. It should feel like closing a book you wrote together.

| Time | What happens |
|---|---|
| 0.00 | The bottom fades out. The page scrolls to the top (`meaningfulMoment`). |
| 0.40 | The title writes itself in letter by letter, from blur to sharp. Letters start 30 ms apart, compressed so a long title takes at most 0.75 s. `selection()`. |
| 1.10 | The byline fades up: "by you and Robin · Oct 13". |
| 1.30 | The ornament (`camera.macro`) scales in with `celebrationReveal`. `answerRevealed()`. A petal bloom bursts from it (the Draw & Guess bloom, seeded by the story id). |
| 1.80 | "14 lines" and, when dares were used, "3 dare words" fade up under the end of the text. |
| 2.10 | The star and the primary button rise in (`cardReveal`). |

- A tap on the screen jumps to the settled state without repeating haptics. Reduce Motion: the settled state at once, with only `answerRevealed()`.
- Built on a `StoryChainRevealTimeline` like `DrawAndGuessRevealTimeline`: run id, injected schedule and haptics, so tests run it fast.
- The namer's button is "Start a new story". The other partner's is "Continue", which marks the story seen. When the next story already started, it reads "See what [Name] started" or "Your turn to write".

| Key | English | Norwegian |
|---|---|---|
| `story.number` | Story %lld | Historie %lld |
| `finished.byline` | by you and %1$@ · %2$@ | av deg og %1$@ · %2$@ |
| `finished.lines` | %lld lines | %lld linjer |
| `finished.dares` | %lld dare words | %lld utfordringsord |
| `finished.startNew` | Start a new story | Start en ny historie |
| `finished.continue` | Continue | Fortsett |

### 6. Our stories

- Entry: the toolbar button on every Story Chain screen, and a quiet link on the hub card once a story has finished.
- A segmented "All" / "Starred" picker, then a list. A row is the title in serif `title3`, the first line in `caption` (two lines, `.paeoniaTextSecondary`), and "Oct 13 · 14 lines". A starred story shows `star.fill` at the trailing edge.
- Empty: "No stories yet" (`books.vertical`), "Your stories will show up here when you finish your first one." Starred empty: "No starred stories", "Tap the star on a story you like, and it shows up here."
- The detail is the finished page without the reveal, with the toolbar star.

| Key | English | Norwegian |
|---|---|---|
| `history.title` | Our stories | Historiene våre |
| `history.filter.all` / `.starred` | All / Starred | Alle / Stjernemerket |
| `history.row.caption` | %1$@ · %2$lld lines | %1$@ · %2$lld linjer |
| `history.empty.title` | No stories yet | Ingen historier ennå |
| `history.empty.message` | Your stories will show up here when you finish your first one. | Historiene deres dukker opp her når dere er ferdige med den første. |
| `history.emptyStarred.title` | No starred stories | Ingen stjernemerkede historier |
| `history.emptyStarred.message` | Tap the star on a story you like, and it shows up here. | Trykk på stjernen på en historie du liker, så dukker den opp her. |
| `star` / `starred` | Star / Starred | Stjernemerk / Stjernemerket |
| `star.privacy` | Only you can see your stars. | Bare du ser stjernene dine. |

### Hub card

- Artwork: a notebook page with lines in both partners' inks, one line in gold, the fountain pen and an ink bottle. A peony bud pops up after the last line. It follows `docs/games/hub-artwork.md`.
- Status: "Your turn to write", "Start a new story", "Give your story a title", "[Name] is writing", "Waiting for [Name]".
- Detail line: "3 stories finished" once one exists.
- The badge counts any of my turns: choosing an opening, writing, naming, or an unseen finished story.

| Key | English | Norwegian |
|---|---|---|
| `name` | Story Chain | Skrivestafett |
| `hub.subtitle` | Write a story together, one line at a time. | Skriv en historie sammen, én linje om gangen. |
| `hub.status.write` | Your turn to write | Din tur til å skrive |
| `hub.status.start` | Start a new story | Start en ny historie |
| `hub.status.name` | Give your story a title | Gi historien en tittel |
| `hub.status.read` | Read how your story ended | Les hvordan historien endte |
| `hub.status.partnerTurn` | [Name]'s turn to write | [Name] sin tur til å skrive |
| `hub.finishedCount` | %lld stories finished | %lld historier ferdige |
| `hub.action.write` | Write | Skriv |
| `hub.action.open` | Open | Åpne |

## iOS

- **Folder.** Everything lives in `Features/Games/StoryChain/` (`Game/`, `Screen/`, `History/`, `Data/`, `Models/`, `Live/`), and tests in `PaeoniaAppTests/Games/StoryChain/`.
- **Local first.** Starting a story, a line, a name, a seen mark and a star go into the pending operations before anything is sent. The screen applies queued moves on top of the server's state, so a sent line is on the page at once.
- **Order.** A line waits for the start of its story. A start waits for this person's earlier name. A seen mark and a star wait for the name of their story. When the server takes a move, the phone reads the state again before the move leaves the queue.
- **Never older.** The cache never takes a state behind the one it holds, judged by the game's `version`.
- **Shared rules on the phone.** `StoryChainRules` mirrors `lib/storyChain.ts`: line normalization and limits, the dare check, the end rules. Tests cover both sides with the same cases.
- **Drafts.** The composer's text is saved on the phone (`StoryChainLocalDocument.draft`) half a second after typing stops, and at once when the screen closes, the app goes to the background, or a line is sent. The draft belongs to no story: it comes back into the first empty composer after the screen opens, before any edit, unless the story already holds that exact line. A new line to write keeps words that were never sent. Words typed while Send saves the line stay in the composer.
- **Refused lines.** When the server refuses a queued line for good, the handler keeps its words in `rescuedLines`. The next composer this person writes in takes them in one cache step that also saves them as the draft, and adds them after whatever it holds, together with the "Your move wasn't sent" notice.
- **A refused start.** When the server refuses the start of a story for good, the story never exists. The lines, title, seen mark and star queued for it stop too, because nothing could ever send them. The words of its line are rescued the same way.
- **Arrivals.** A line writes itself in once per app session. The page runs the write-in from a `TimelineView` clock (`StoryChainPageText`), and the view model sets `page.arrivingLineID` and `arrivalPace` (`.partner` 45 ms between words, `.mine` 30 ms). The haptic for a partner line fires when it lands.
- **Live room.** Story Chain uses `WidgetLiveDrawing` only for presence and the socket, with no canvas, and sends `StoryChainLiveMessage` on a `GameLiveChannel`.
- **Built screens.** The screens follow the design with these differences. The dare hint "Use WORD to send." shows only once the line is otherwise valid, because the capsule above the field already names the word. On line 20 the locked switch keeps its "Make this the last line" label, and the placeholder says "Write the last line." The hub card's status before the first story is the card subtitle, and "Waiting for [Name]" reuses the shared Games copy. Each line is its own VoiceOver element, and there is no rotor or VoiceOver action for the line popover yet.
- **Offline history.** The phone keeps the current and previous story and the first page of "Our stories". An older story's page needs the network.
- **Testing.** Every screen has a developer scenario (`story-chain-choose`, `-writing`, `-writing-last`, `-waiting-live`, `-waiting-away`, `-saved-offline`, `-naming`, `-waiting-name`, `-finished`, `-waiting-opening`, `-history`, `-history-empty`, `-choose-offline`). `backend/scripts/story-chain/play.mjs` plays the partner against the hosted backend, including live typing over the relay.

## Decisions made without the developer

Made on the night of 2026-10-13, while the developer was away. Each is the option that would have been recommended.

- **Drafts and refused lines.** A half-written line is saved on the phone, and a line the server refuses goes back into the next composer, whatever story that is. Without this, a refused line was lost, which breaks the rule that user content is never dropped silently.
- **Disk write failures are not handled.** Like the rest of the Games cache, the Story Chain cache writes its file on a best-effort basis. On a full disk, a rescued line can still be lost. Making every cache write throw and keeping the move queued until the words are on disk is the upgrade path.
- **A refused start stops its moves.** Lines, a title, a seen mark and a star queued for a story whose start the server refused are dropped with it, instead of retrying forever.
- **Turn pushes name the line.** The push payload's `round_id` is the line that passed the turn, so a stale push can't come back to life a turn later.
- **One reminder per turn.** Starting a story continues the starter's turn, so it does not earn a second reminder.
- **Content fixes.** "balcony" left the English dare words ("balconies" fails the contains check) for "carousel". The Norwegian "skatt" (also "tax") became "skattekart", because "skattekiste" turns into "skattekista" and fails the check. One opening uses "et pizzabud" and another "brannfolkene".
- **Test access.** The test couple's subscription had lapsed, so every simulator stopped at the paywall. An active `test` entitlement grant for Hjalmar, ending 2026-11-12, was added on the hosted deployment (a test-data edit, which is pre-approved).
- **Shared test.** The foundation's backend test "only Draw & Guess has a backend so far" now lists one line per built game, so each game adds a line instead of editing the same list.

## Open questions

- A native Norwegian speaker should read the Norwegian openings and dare words before release, as the Draw & Guess words were read. Words worth a second look: "pulk", "akebrett", "geitost", "rømmegrøt", "agurk", "troll", "saks".
