# Board games

Design for Connect Four, Dots and Boxes and Ultimate Tic-Tac-Toe. The three games share one turn engine, one table, one screen shell and one twist. Shared rules for all games (transports, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to the board games.

Ludo runs on this engine too, with its own design in `docs/games/ludo.md`.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-13.

- **Your own mark.** Each partner draws a mark once on the Paeonia canvas. It is printed on every Connect Four disc they drop, fills every box they close in Dots and Boxes, and replaces X and O in Ultimate Tic-Tac-Toe. Until a partner draws one, their initial is their mark, so the first game starts at once. Either partner can redraw their own mark at any time.
- **A bet.** The partner who starts a game can write a small bet, such as "Loser makes coffee". It sits under the board while they play, and the result says who claimed it.
- **A hidden photo under Dots and Boxes.** The board sits over a random photo from the couple's Memories. Each closed box uncovers its piece of the photo, tinted in the color of the partner who closed it, and the last box shows the whole picture. A couple with no photos gets plain boxes.
- **Play style changes only the score.** The board is always head to head. "Against each other" shows each partner's wins, which grow forever. "Together" hides the tally and shows how many games the couple has finished together, and the result says who won this one without keeping score.
- **Dots and Boxes is 4 by 4 boxes.** That is 5 by 5 dots and 40 lines.
- **Every move counts toward the streak.** Making a move records `game_turn_completed`. The streak needs only one action per partner per day, so more moves add nothing.
- **The photo is random.** When a Dots and Boxes game starts, the server picks a random photo from the couple's Memories. Neither partner knows which one until boxes start closing.
- **Norwegian names.** Fire på rad, Prikker og streker and Ultimat bondesjakk.
- **Gentle rematch.** When a game ends, either partner can tap "Play again". The partner who did not start the last game starts the new one.
- **Past games.** Decided on 2026-10-15. The server keeps every finished game with its moves, and the couple can watch any of them again, faster than it was played. Ultimate Tic-Tac-Toe shows them so far. The other board games keep theirs on the server, and each needs a replay mode on its board view before it shows them (see "Past games" under "Screens").

## Decisions made without the developer

Made on 2026-10-14 while the developer was away. Each is the option that was recommended, and each can change.

- **No relay room.** Live play runs on the Convex subscription and the shared game presence. Showing the partner's finger hovering over a column would need a relay channel, so it is left for later. Ludo is the exception: it sends each roll through its relay room, so both dice tumble together (see `docs/games/ludo.md`).
- **Saving a mark needs a connection.** The editor keeps the drawing and shows a banner when the save fails. A mark is not queued like a move.
- **A refused move is told on the board.** The board keeps the notice until it opens, then shows the banner. The Games tab shows the game as it is, without a banner.
- **The stake counts Unicode scalars.** The server counts them, so the phone counts them the same way and never sends a stake the server refuses.
- **An empty stake means no stake.** The server accepts it from anyone on any move and stores nothing.
- **A mark can be drawn before the partner joins.** Starting a game needs both partners. Drawing a mark doesn't.
- **The reminder uses the shared body.** "Pick up where you left off." The title names the game.
- **Turn pushes carry a turn token.** `round_id` holds `<game number>:<move count>`, so the drain can tell whether the push is still wanted. It never holds the move.
- **The petal bloom comes from the board.** The result panel draws none, so a win blooms once, from the winning line.
- **"Whole board" also shows in a forced zoom** in Ultimate Tic-Tac-Toe, so a player who was sent to a board can still look at the whole game.
- **A Connect Four draw** dims the discs to 60% and brings them back.
- **Marks are drawn in blush** on boxes and cells, so both partners' marks read the same on their colors.
- **The partner's pieces are lavender.** Draw & Guess's second partner color is a pink close to the first, and on a full board the two sides were hard to tell apart, so the partner's pieces, glow and badge use `.paeoniaInkLavender`.

## Why these games

GamePigeon already has all three inside iMessage. They earn a place here only with the twist: the partner's own hand-drawn mark on every piece, a stake that is between the two of you, and a photo of the two of you that each box uncovers. All three are turn based, so they work async across time zones and feel live when both partners have the game open.

## Rules

Player one started the game and always moves first. Each game has a pure rules function on the server (`backend/convex/lib/<camelKind>.ts`) and the same rules on the phone (`Features/Games/BoardGames/<Folder>/<Game>Board.swift`). The server stores only the list of moves. The board, whose turn it is and the outcome come from replaying them. Both sides have tests for wins, draws and illegal moves.

### Connect Four

- 7 columns and 6 rows. A move is a column. The disc falls to the lowest empty cell.
- Four or more in a row, horizontally, vertically or diagonally, wins. Every cell of every winning run through the last disc lights up.
- A full board with no four in a row is a draw.
- Illegal: a column out of range, a full column, a move after the game ended.

### Dots and Boxes

- 5 by 5 dots, 4 by 4 boxes, 40 lines. A move is one line.
- A line that closes one or two boxes gives them to the mover, who moves again. Otherwise the turn passes.
- The game ends when all 40 lines are drawn. More boxes wins, and 8 to 8 is a draw.
- Illegal: a line that is already drawn, a move after the game ended.

### Ultimate Tic-Tac-Toe

- 9 small boards in a 3 by 3 grid. A move is one cell.
- The first move can go anywhere. After that, the cell you play decides which small board your partner must play in next. If that board is won or full, your partner can play in any open board.
- Three in a row wins a small board. A full small board with no winner belongs to nobody.
- Three won small boards in a row wins the game. When every small board is won or full without that, the game is a draw.
- Illegal: a taken cell, a closed board, a board other than the one you were sent to, a move after the game ended.

## The game

- A couple has one game of each kind. The first partner to open a board game creates it and moves first.
- **Turns.** Only the partner whose turn it is can move. The other partner's board shows "[Name]'s turn". In Dots and Boxes a turn can hold several moves.
- **Ending.** The last move shows the outcome on both phones (see "Result"). The game stays finished until either partner taps "Play again".
- **Rematch.** "Play again" starts a fresh board on the same row. The partner who did not start the last game starts the new one. If both tap at once, the first tap wins and the second phone shows the new game.
- **An ending you missed.** When your partner made the last move and started a rematch before you looked, the game first shows the ending you missed, then "Continue" leads to the new game. The server keeps the last finished game until the next one finishes, and the phone remembers which ending it showed.
- **No forfeits.** A game waits as long as it needs to. There is no timer and no way to lose by waiting.

## The twist

### Your mark

- A mark is a small drawing made with the PencilKit pen in one ink. It is stored per partner in the couple, not per game, so one mark shows in every board game.
- The phone crops the mark to a square around its strokes, so a mark drawn small or off center still fills its piece. The crop is at least half the canvas, so a tiny mark grows at most 2x.
- The board tints the mark in its owner's color. On this phone, my pieces use `.paeoniaPartnerOne` and my partner's use `.paeoniaInkLavender` (`Color.boardGameMine` and `Color.boardGamePartner`). Ludo is the exception: each partner picks one of four colors, and both phones show the same colors (see `docs/games/ludo.md`).
- Without a drawn mark, a partner's mark is the first letter of their display name.
- The first time a partner opens any game, the first-time sheet ends on the mark editor for someone with no mark, after setup or the partner's choices. Cancel skips it, and the game opens either way.
- Later the editor opens from "Your mark" in the game settings sheet on the hub, "Your mark in games" on the Us tab, and the "Your mark" button in the board toolbar. It never blocks a game.
- Saving needs a connection. A failed save keeps the drawing in the editor and shows "We couldn't save your mark. Check your connection and try again."
- The partner's new mark shows on their pieces the next time the board renders. Nobody gets a push for it.

### A bet

- Only the partner who starts the game can write the stake, and only before their first move. It goes to the server with that first move, so it is fixed from then on, and the other partner sees both together.
- Before the first move the starter sees a quiet "Add a bet" button ("Legg til et veddemål") under the board, above the pinned bottom. Tapping it opens a one-line text field that rises with the keyboard, with the keyboard's Done button. The text can be changed until the first move. The code calls the bet a stake.
- A stake holds 1 to 60 characters on one line. It is optional.
- While playing, the stake shows under the board in a capsule: "Bet: Loser makes coffee".
- The result names who claimed it (see "Result"). A draw says nobody claimed it.
- Push notifications and the lock screen never show the stake.

### The hidden photo

- When a Dots and Boxes game starts, the server picks a random photo from the couple's Memories. It checks the photo again every time the game is read. A photo whose memory was deleted or hidden stops showing, and the board falls back to plain boxes.
- The phone loads the photo the same way Memories does. The photo is never shown whole until the last box closes. Each closed box shows its own piece.
- The phone has the whole photo, so a partner could in theory peek. Cheating is not a real risk between partners, the same reasoning as the Draw & Guess word.
- A couple with no photos gets plain colored boxes with the owner's mark, and nothing on screen mentions a missing photo.

## Live and async

- **Convex only.** Moves go through Convex and reach the other phone through its subscription within a few hundred milliseconds. Board games use no relay room.
- **Presence.** The open board screen sends the game's presence heartbeat, as Draw & Guess does. While the partner has the same game open, a green dot sits on their avatar. The status row stays empty then, unless the game shows a hint there.
- **Invite.** While the partner is not in the game, the board shows "Tell [Name] you want to play" (see `docs/games-plan.md`).
- **The partner's moves arrive animated.** A move that arrives while the board is open plays its animation. When the board opens after the partner moved, it first shows the board as this phone left it for 0.6 seconds, so the person sees where things stood. Then the moves since this phone last showed the board play in order, each one after the last one's animation. A tap on the board skips to the end.
- **Offline.** A move made offline shows on the board at once and is saved on the phone as a pending operation. The screen says "Saved on this phone. We'll send it when you're online." Moves leave in order. A move the server refuses as stale or illegal is dropped with "Your move wasn't sent", and the board shows the server's state again.
- **Notifications.**
  - "Your turn in Connect Four" when the turn passes to you, skipped while you have that game open.
  - "[Name] finished your game of Connect Four" when the partner's move ends the game, skipped while you have it open.
  - "[Name] wants to play Connect Four with you" for an invite.
  - One reminder, "Your turn in Connect Four", when a turn has waited 72 hours. A turn never gets a second one, and a finished game gets none.
  - Pushes name only the game. They never show the move, the stake or the result.

## Scoring

- The server keeps every partner's wins, the draws and the number of finished games for each kind, whatever the play style. Switching style loses nothing.
- **Against each other.** The toolbar capsule shows my avatar and wins next to my partner's avatar and wins. The result counts the winner's tally up by one.
- **Together.** The capsule shows a heart and "12 games". The result says "[Name] won this one" or "You won this one", then counts the couple's games up by one.

## Streak

Every accepted move records `game_turn_completed` with the dedupe key `game_turn_completed:<game id>:<game number>:<move number>`.

## Data

The functions are in `backend/convex/boardGames.ts`, the shared helpers in `backend/convex/lib/boardGames.ts` and each game's rules in `backend/convex/lib/<camelKind>.ts`.

- `board_games`: one row per couple and kind. It holds the current game and the couple's tallies for that kind.
  - `game_number` goes up with every new game. `status` is `playing` or `finished`.
  - `first_user_id` is player one. `moves` is the list of move indexes in order. `turn_user_id` is the partner who moves next, and is absent once the game is finished.
  - `winner_user_id` and `win_line` describe a finished game. A finished game without a winner is a draw.
  - `stake` and `stake_by_user_id` hold the stake. `photo_media_asset_id` is the hidden photo of a Dots and Boxes game.
  - `colors_by_user` holds each player's piece color, in Ludo only.
  - `wins_by_user`, `draws` and `games_finished` are the tallies. They never reset.
  - `previous` keeps the last finished game (its number, first player, moves, winner, line, stake and photo) after a rematch, so a partner who missed the ending can see it.
  - `turn_started_at` and `turn_reminder_sent_at` drive the 72-hour reminder. `version` goes up with every change.
- `board_game_marks`: one row per couple and partner, with the mark as base64 `PKDrawing` data (at most 48 KB) and `updated_at`.
- `board_game_history`: one row per finished game, written by the move that ends it. It holds the kind, `game_number`, `first_user_id`, `moves`, `winner_user_id` (absent for a draw), `win_line`, `stake`, `started_at` and `finished_at`. The index is `by_couple_id_kind_game_number`.
- Functions:
  - `get_board_games` returns all three games for the caller as `view_for` projections: the moves, whose turn it is, the outcome, the stake, the photo asset id (only while its memory is visible), my and my partner's tallies, and `previous`. Ludo games also carry `my_color` and `partner_color`. A game the couple has not started is `null`.
  - `get_board_game_marks` returns both marks. It is a separate subscription, so a move never resends the drawings.
  - `ensure_board_game({ kind })` creates the row with the caller as player one.
  - `make_move({ game_id, expected_version, move, stake?, ludo_color? })` checks couple access, that the game is playing, that it is the caller's turn and that `expected_version` matches. It then runs the pure rules for the row's kind. A stale version fails instead of overwriting. It is a client operation, so a retry is answered from the server's record.
  - `start_rematch({ game_id, expected_version })` starts the next game when the current one is finished.
  - `set_board_game_mark({ drawing })` saves or clears the caller's mark.
  - `get_board_game_history({ kind, before_game_number?, limit })` pages the finished games of one kind, newest first, at most 50 a page. `next_before_game_number` is the cursor for the next page and is null on the last one.
- Refusals use the wording the phone's queue understands: `42501 it is not your turn`, `23514 that move is not allowed` and `40001 the game has changed`. A game id the server doesn't have, such as after a restore of the server, is `40001` too.
- Relationship cleanup deletes the couple's `board_games`, `board_game_marks` and `board_game_history` rows. Account deletion ends the relationship, so it follows the same path.
- Pushes and reminders go through `boardGameBackend` in `lib/boardGameBackend.ts`, registered in `GAME_BACKENDS` for all three kinds. A turn or result push carries `round_id` as a turn token, `<game number>:<move count>`, and the push drain sends it only while the game is still at that turn or result. The DB helpers are in `lib/boardGameStore.ts`.

## Screens

Copy keys start with `boardGames.` for the shared shell and `connectFour.`, `dotsAndBoxes.` or `ultimateTicTacToe.` for each game. "[Name]" is the partner's display name. Every string has English and Norwegian Bokmål with a translator comment.

### Shell shared by the three games

- One screen per game, built on `BoardGameScreen` in `Features/Games/BoardGames/Shared/`. It opens from the hub card, the turn and invite pushes and the deep link.
- Look. The Draw & Guess shell: `.paeoniaBackgroundSecondary`, dark color scheme, inline title with the game's name, no tab bar on iPhone.
- **Players row.** My avatar on the leading side and my partner's on the trailing side, 44 pt, each with its mark in a small badge. Each column sits on a small card of plum-tinted Liquid Glass that hugs the avatar and name, the same glass as a hub card's badge, so they stay readable over Ludo's board. Whoever's turn it is gets glass in their piece color instead of plum (mixed 45 percent with the plum so white text stays readable), an avatar 10 percent larger, and a bold white name. There is no glow, because it looked muddy on the dark backing. On a finished game the winner stays marked, and a draw marks neither. A green dot at the top of my partner's avatar shows they have the game open. VoiceOver reads "Your turn", "[Name]'s turn", "You won" or "[Name] won" on the active avatar, and "[Name] is here" as my partner's name while they are.
- **Stake row.** Under the status row, above the pinned bottom. The stake capsule, or the "Add a bet" button for the starter before the first move. Hidden otherwise, without leaving a gap. In the wide layout it sits under the players row.
- **Board.** Square for Dots and Boxes and Ultimate Tic-Tac-Toe, 7 by 6 for Connect Four. It takes the width up to 560 pt and never scrolls on a phone in portrait.
- **Color row.** Ludo only. Four round color circles under the status row and above the stake row, until the player's first move of the game (see "Your color" in `docs/games/ludo.md`). In the wide layout it sits under the players row, above the stake.
- **Your turn.** When the partner's move hands me the turn, `gameYourTurn()` and `nudge` play once the board has finished showing that move (`GameAttentionCue`). A Dots and Boxes box or a Ludo 6 keeps my turn and plays nothing. A rematch counts as a handover only when the partner started it.
- **Status row.** Under the board. On a Dots and Boxes extra turn, "Another turn" pops in for 1.5 seconds. A game can show its own hint there, as Ludo does ("Roll again"). VoiceOver announces when the partner comes and goes.
- **Pinned bottom.** In Ludo, the invite button while it is not my turn and the partner is away. The bar always keeps room for it, so the board never resizes. The other boards show the invite as a bell at the leading edge of the toolbar instead. The offline line while a move waits to send. Under it, "[Name] isn't here right now" while the partner doesn't have the game open. While they do, the dot on their avatar says so and the line is gone.
- **Score capsule.** Toolbar trailing, as in Draw & Guess (see "Scoring"). In a game with past games, a tap on it opens them.
- **Toolbar.** "Your mark" (`scribble.variable`) opens the mark editor.

### Result

The moment the last move lands.

| Time | What happens |
|---|---|
| 0.00 | The last move's own animation finishes, whether the move was made on this phone or arrived. Input locks. |
| 0.15 | The winning pieces light up one after another, starting from the piece that won, and the rest of the board dims to 40%. A glowing line draws from that piece through the winning run (Connect Four and Ultimate Tic-Tac-Toe). In Dots and Boxes the tints lift off the photo and it shows whole. |
| 0.70 | `answerRevealed()` and the petal bloom from the middle of the winning line, as in Draw & Guess. A draw gets one soft `partnerDrawingReceived()` and no bloom. |
| 1.10 | The result panel rises from the bottom: the title, the stake line, the score and "Play again". The board glides smaller and up to make room for it, and the bet moves up with it (`meaningfulMoment`). |

- Titles. Against each other: "You won!", "[Name] won" or "It's a draw". Together: "You won this one", "[Name] won this one" or "It's a draw".
- Stake line. "You claimed: Loser makes coffee", "[Name] claimed: Loser makes coffee", or after a draw "Nobody claimed: Loser makes coffee".
- Score. Against each other: the two avatars with their wins, and the winner's count goes up by one with `streakTick`. Together: "13 games together", counting up by one.
- A tap jumps to the settled state. Reduce Motion shows the settled state at once with only the haptic.
- "Play again" is the primary action. The board stays visible above the panel, and the panel can be collapsed to look at the board.

### Connect Four

- The board face is a rounded plum frame with 42 round holes. The discs sit behind the face, so a falling disc shows through the holes.
- Playing. Tap a column, or drag across the board. A hovering disc with my mark follows the finger above the columns and snaps to each column with `selection()`. Releasing, or tapping, drops it. A full column makes the hovering disc shake with `gameWrongGuess()` and nothing is sent.
- The drop. The disc falls with gravity and lands with a small bounce. A soft impact haptic and the drop sound play when it lands, and a quieter tap and sound when it comes down from its first bounce. The partner's disc first hovers over its column for 0.25 seconds, then drops the same way. A move takes as long as its disc falls, so the result starts 0.15 seconds after the winning disc stops, however far it fell.
- Reduce Motion. The disc fades in at its cell.
- VoiceOver. Each column is one element, "Column 3, 2 discs, yours on top", with the action "Drop a disc". The partner's move announces "[Name] dropped a disc in column 3".

### Dots and Boxes

- 25 dots on a square board over the hidden photo. Undrawn lines are faint dotted guides. Closed boxes show their piece of the photo with a 30% tint in the owner's color and the owner's mark small in a corner. Without a photo, a closed box fills with the owner's color and the mark in the middle.
- Playing. Tap anywhere near a line. Each line's tap area is the triangle between it and the centers of its neighboring boxes, so every point of the board picks exactly one line. The line is drawn at once.
- The line snaps in from its middle to both dots with a spring, and its two dots pulse once. A closed box's piece scales up from 0.85 and fades in, with `streakTick`. Two boxes from one line are 0.12 seconds apart. The photo loads after the board shows, and its pieces fade in over the plain boxes (0.36 seconds).
- Reduce Motion. Lines and boxes fade in.
- VoiceOver. The board is a grid of boxes. Each box reads its four sides, for example "Box row 2, column 3, top and left drawn", with actions for each undrawn side. Closing a box announces "You closed a box. Another turn."

### Ultimate Tic-Tac-Toe

- The big grid has 9 small boards with wide gaps. Open boards that the next move may use glow softly in the mover's color. Other boards dim.
- Zoom. When I must play in one board, the board zooms in on it so its cells are large, then I tap a cell. When I may choose, the whole board shows, I tap a small board to zoom into it, and a tap outside it or a pinch zooms back out. After my move the board zooms out, and once the camera has settled, the board my partner is sent to pulses once to 110%.
- The partner's move. The board zooms into the small board they played, their mark draws in, then the view moves to the board I am sent to. A move from one small board to another pulls back partway and swoops in, so it never slides across the board at full zoom.
- A won small board gets a strike line through its three cells, its cells fade to 30%, and the winner's mark draws large over it. The strike line lies under the big mark and is paler than it (45% saturation, 70% opacity), so the line never covers the mark. The line through the three winning boards at the end of a game is drawn the same way, under the big marks. A full small board without a winner fades to 30%. When a move closes a small board and ends the game, the board goes straight on to the result, which starts 0.15 seconds after the closing beat.
- Reduce Motion. The board still zooms, so the cells stay large enough to tap, but the view cuts to the new board instead of gliding. My partner's move shows at once, without the trip to their board. VoiceOver never zooms. The board I am sent to keeps its glow.
- VoiceOver. Each small board is a group, "Board 5, center, open" or "Board 5, won by [Name]". Each cell reads "Row 1, column 2, empty".

### Past games

- Ultimate Tic-Tac-Toe has "Past games" ("Tidligere spill"). It opens from a quiet link on the hub card once the couple has finished a game, and from the score capsule on the board screen. The shared code is in `Features/Games/BoardGames/Shared/History/`, so another board game gets it by passing a replay board to its `BoardGameHubModel`.
- The list shows every finished game, newest first: the winner's photo (an equals sign for a draw), "You won!", "[Name] won" or "It's a draw", the number of moves and the date, and the bet when there was one. It pages 30 games at a time. It reads the server each time it opens. Without a connection it says "Connect to the internet to see your past games." Any other failure says "Something went wrong" and to try again in a little while. Both offer "Try again".
- A row plays that game again. The replay screen has the players row, which marks whose move it is and then the winner, the board, the bet, and a play button with a slider and "Move 12 of 39" under it.
- The replay starts at once and plays one move every 0.32 seconds. The board never zooms in a replay, and moves make no haptics or sounds. After the last move the outcome highlight plays as it did in the game. The play button pauses, and at the end it reads "Watch again" and starts over. Moving the slider pauses the replay and shows the board after that move.
- My pieces are pink and my partner's lavender, whoever started that game.

### Mark editor

- A sheet with the title "Your mark" and the line "Draw your mark. It shows on your pieces in every board game."
- A square canvas with the PencilKit pen in one color and one width, plus Undo and Clear. Under it, a live preview of the mark on a Connect Four disc, a Dots and Boxes box and an Ultimate Tic-Tac-Toe cell, in my color.
- Save is the primary action. "Use my initial" removes the drawn mark.

### Hub cards

Each game has its own card on the Games tab, with its own objects on the shared backdrop, made to `docs/games/hub-artwork.md`.

- Connect Four. A cream board with both partners' discs. The last pink disc drops into its hole and the row glows gold.
- Dots and Boxes. A board of pearls whose closed boxes show a sunset photo. A warm light swells behind it.
- Ultimate Tic-Tac-Toe. Nine small boards of hearts and rings. A gold line strikes through three hearts.
- The card shows "Your turn", "[Name]'s turn", "You won", "[Name] won", "It's a draw" or "Start a game", with "Play", "Look at the board", "Play again" or "Start". The partner-here chip and the score capsule match Draw & Guess.

## iOS

Code map in `docs/implementation-map.md`. Decisions the sections above leave open:

- **Local first.** A move and "Play again" go into the pending operations before anything is sent (`boardGameMove`, `boardGameRematch`). `BoardGameResolver` puts them on top of the server's game. An action applies only when it names the version the game has reached, so an action the server already took is never applied twice, and a refused one falls away. Several Dots and Boxes moves queued offline each name the next version.
- **Sending.** A move waits for this person's earlier board game actions. When the server takes it, the phone saves the answer and reads every board game again before the move leaves the queue. A refusal a retry can't fix (`40001`, `23514`, `42501 it is not your turn`) drops the move with "Your move wasn't sent". Any other server answer drops it on the third refusal. A refused "Play again" means the partner already started the next game, so it succeeds quietly.
- **What this phone showed.** The cache keeps, for each game, the game number and move count this phone last showed (`BoardGameShownPosition`). The board replays from there, and a missed ending shows when the last game ended past it. Without a record the replay starts after this person's own last move. The board moves only while the screen is open. A board that needs time to load sets `isWaitingForBoard` on the view model, and the replay and the outcome wait until it clears. Ludo sets it while its loading view shows. A board that knows when a move's animation has ended can call `finishMoveAnimation(number:)` to end that move's wait early. Ludo does for the partner's moves.
- **Marks.** Both marks come from their own subscription, so a move never resends the drawings. The phone renders a mark once per update as a template image and tints it.
- **Hidden photo.** The phone loads it through the Memories photo cache (`MemoryMediaImageProviding`) and downsamples it to 1200 pixels.

## Wide layouts and Dynamic Type

- Wide means 700 pt or more and wider than tall, as in Draw & Guess. The board sits on the left (up to 640 pt), and the players, stake, status and result sit in a column on the right (up to 420 pt). Ludo's board bleeds, so it keeps the single column on a wide screen. Its 3D view covers the whole screen behind the rows, the camera fits the board in the space between the players row and the status row, and the screen color fades in over the board past that space so the rows stay readable. When that space changes, for example as a result panel comes, the board and its camera glide to the new space over `PaeoniaMotion.stateChange` instead of jumping. Reduce Motion snaps. It is not a material blur: a material can't blur the 3D view and shows gray strips over the plain background.
- At accessibility text sizes the players row stacks and the screen scrolls. The board keeps its size.

## Open questions

None.
