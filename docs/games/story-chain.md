# Story Chain

Design for the third built game. The two partners write one story together, one or two sentences at a time. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Story Chain.

Keep this file current. When a decision lands or the design changes, update it in the same change.

Page eyebrows and partner activity groups are centered. Waiting hints wrap under their status. Story paragraphs and composers keep their existing alignment.

## Decisions

- Both partners can send !, ?, laughter and a heart while writing, reading or naming an unfinished story together. The buttons stay below the game title, above the page, including while the keyboard is open. Each tap shows a temporary reaction on both phones, with the same upward flight and random small tilt as Draw & Guess. Reactions use the live relay, belong to the current story and are not saved or sent as notifications. Reduce Motion uses a stationary fade. Finished stories keep their saved emoji reactions.

- **Name.** "Story Chain" in English and "Skrivestafett" in Norwegian. A skrivestafett is the Norwegian school exercise where people take turns writing a story.
- **Async first, with live letters.** Each partner writes a line whenever they like. When both have the game open, the waiting partner watches every letter as it is typed, deletions included. A watched line settles into place when sent. A partner's line missed while away writes itself in when the page opens.
- **The writer always knows.** While the partner watches, the writer sees "[Name] is reading along" with the partner's avatar. There is no setting to hide typing.
- **Openings.** A new story starts with a choice of three opening lines written by Paeonia in the couple's game language, or with the starter's own first line.
- **The dare word.** After writing a line, the writer may give the partner a word that the partner's next line must use. The writer picks one of three words Paeonia suggests, or types their own. It is optional on every turn.
- **The dare check.** A line uses the word when the line contains it, ignoring case. "hunden" and "gårdshund" both count for "hund". The phone and the server run the same check, and Send stays off until the word is used.
- **Length.** A line is 2 to 240 characters. The composer asks for "one or two sentences" and counts characters, not sentences. Both partners see letters past the limit in red until the writer removes them. The writer's counter also turns red, and Send stays off.
- **The end.** From the 8th line on, the writer can make their line the last one. Line 20 is always the last.
- **The title.** The partner who did not write the last line names the story (1 to 40 characters), then starts the next one.
- **Lines are final.** There is no undo after sending.
- **No points.** Story Chain ignores the play style. A story has no winner. The hub card counts the stories the two of you have finished.
- **Streak.** Sending a line counts toward the couple's streak. Naming a story alone does not.
- **Reading.** The story reads as one flowing page in the system serif. Each partner's sentences have their own ink, Paeonia's opening is muted italic, and a dared word has a gold underline. Tapping a sentence shows who wrote it and when.
- **Pushes.** Five kinds, none showing story text: your turn, the last line was written, the story was named, an invite, and one reminder after 72 hours.
- **History.** Finished stories are kept in "Our stories" with private stars, like "Our drawings". A star is a favorite (`FavoritesStore`, kind `story_chain_story`).
- **Reactions.** Either partner can put one emoji on a finished story, under the stats line of the reveal and on the story in "Our stories" (decided on 2026-10-21). The emoji of both partners shows on the story's row. They work like every reaction (`docs/implementation-map.md`, "Reactions"): kind `story_chain_story`, one gentle push for a first reaction, no queue. The row waits until the server has the title, so it never meets a refusal.

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
- The story and title fields explicitly enable system autocorrect. Corrections follow the person's keyboard settings.
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
- **Live letters.** While writing, the phone sends a `StoryChainLiveMessage` inside the draft case of `StoryChainRoomMessage`: the story id, the line number, the draft as typed, and whether it is set to be the last line. It sends the whole draft on every change, at most every 50 ms, and again when the partner arrives. Drafts have a separate safety cap of 4,096 code points. Sent lines keep the 240-code-point limit. Nothing in it is saved.
- **The reader's page.** The partner's draft shows at the end of the page in the partner's ink at reduced opacity, with a blinking caret. Letters past the normalized line limit turn red. Leading and trailing whitespace do not count, and inner whitespace counts once, as it does for Send. A composed character that crosses the limit turns red whole. VoiceOver can read the draft and its character count. Deletions show too. A draft older than 10 seconds without an update fades out, so a writer who left without sending leaves no ghost behind.
- **Sending live.** The writer's phone sends a final message with the line id and `sent: true` the moment Send is tapped. A line watched live during this visit settles into place without a replay, even after a pause in typing. An unwatched line plays its arrival before Convex confirms. A confirmation never replays the same line, whichever message arrives first. The reader's composer opens only once Convex says it is their turn.
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

- Follow the voice rule in `.agents/skills/paeonia-questions/writing.md`. An opening comes from Paeonia, never from a partner. Write in third person about invented characters and places. No "I", "me", "we", "our", and no "you". In Norwegian, no "jeg", "meg", "vi", "vår", "du" or "deg".
- One sentence, at most 120 characters, ending with a period.
- Concrete and open: an object, a place, a small mystery. Something a 16-year-old can continue at once.
- Warm, curious, or funny. Nothing scary, sad, sexual, or about real people.

Rules for dare words:

- Single concrete nouns, 4 to 14 letters, lowercase, that any 16-year-old knows.
- The check is "the line contains the word", so a word must still match its common forms. Avoid nouns whose plural or definite form changes the stem: English "knife", "mouse", "story", "city", and Norwegian "bok", "mann", "hånd", "sykkel", "nøkkel".
- No slurs, no words with a crude second meaning. A native speaker reads every word before it ships (see the "pakkis" note in `docs/games/draw-and-guess.md`).

## History and stars

- **Our stories.** Every finished story, newest first, paged by story number, 30 a page. A filter shows starred stories only. Each entry has the title, the first line, the date it finished and the number of lines. The app shows the star from my favorites.
- **Stars.** Either partner can star or unstar a finished story. A star is a private favorite (`favorites:set_favorite`, kind `story_chain_story`), and the server saves it only for a finished story. A queued star waits for this person's queued title of the story (`StoryChainFavoriteGate`). The server returns no star state with the story, and `p_starred_only` reads the favorites.
- **The detail.** A story opens as the finished page: title, byline, the full text, the end mark, and the star in the toolbar.
- Stars are `favorites` rows. They are deleted with the rest of the couple's content.

## Notifications

None of these show story text, a title, or a dare word. The payload holds ids and the deep link `paeonia://games/story-chain`.

| Moment | Push kind | English | Norwegian |
|---|---|---|---|
| A line arrives | `game_turn_ready` | Your turn in Story Chain / Read the newest line and add yours. | Din tur i Skrivestafett / Les den nyeste linjen og skriv din. |
| The last line arrives | `game_turn_ready`, step `last_line` | [Name] wrote the last line / Give your story a title. | [Name] skrev den siste linjen / Gi historien en tittel. |
| The story was named | `game_result` | [Name] named your story / Read the whole story. | [Name] ga historien deres en tittel / Les hele historien. |
| Invite | `game_invite` | [Name] wants to play Story Chain with you | [Name] vil spille Skrivestafett med deg |
| 72 hours waited | `game_turn_reminder` | Your turn in Story Chain | Din tur i Skrivestafett |

- The turn and named pushes are skipped while the recipient has the game open.
- A turn push names the line that passed the turn (`round_id`). The drain drops it once that line is no longer the newest of the current story or the turn moved on, so a push that waited while the turn went around never counts for a later turn. A named push names the story and is dropped once its last writer has seen it.
- The last line push uses the `steps` copy of `GAME_PUSH_COPY` (`step: "last_line"`), a seam the foundation added on 2026-10-13 at Story Chain's request.
- The single reminder is per turn. Starting a story does not start a new turn, so a reminder sent while the starter picked an opening is not repeated after they start.

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
