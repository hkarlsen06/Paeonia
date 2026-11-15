# Board games

Design for Four in a Row, Dots and Boxes and Ultimate Tic-Tac-Toe. The three games share one turn engine, one table, one screen shell and one twist. Shared rules for all games (transports, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to the board games.

Ludo runs on this engine too, with its own design in `docs/games/ludo.md`.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

- **Your own mark.** Each partner draws a mark once on the Paeonia canvas. It is printed on every Four in a Row disc they drop, fills every box they close in Dots and Boxes, and replaces X and O in Ultimate Tic-Tac-Toe. Until a partner draws one, their initial is their mark, so the first game starts at once. Either partner can redraw their own mark at any time.
- **A bet.** The partner who starts a game can write a small bet, such as "Loser makes coffee". It sits under the board while they play and stays there with the result, whose title says who won it.
- **A hidden photo under Dots and Boxes.** The board sits over a random photo the couple shared: a Memories photo, a story, or a Guess my spot photo. Each closed box uncovers its piece of the photo, tinted in the color of the partner who closed it, and the last box shows the whole picture. A couple with no photos gets plain boxes.
- **Play style changes only the score.** The board is always head to head. "Against each other" shows each partner's wins, which grow forever. "Together" hides the tally and shows how many games the couple has finished together, and the result says who won this one without keeping score.
- **Dots and Boxes is 4 by 4 boxes.** That is 5 by 5 dots and 40 lines.
- **Every move counts toward the streak.** Making a move records `game_turn_completed`. The streak needs only one action per partner per day, so more moves add nothing.
- **The photo is random.** When a Dots and Boxes game starts, the server picks a random photo from the couple's Memories, stories and Guess my spot rounds (decided on 2026-11-02). Neither partner knows which one until boxes start closing.
- **Norwegian names.** Fire på rad, Prikker og streker and Ultimat bondesjakk.
- **Gentle rematch.** When a game ends, either partner can tap "Play again". The partner who did not start the last game starts the new one.
- **Past games.** The server keeps every finished game with its moves, and the couple can watch any of them again, faster than it was played. All four board games show them.

## Decisions made without the developer

Made on 2026-10-14 while the developer was away. Each is the option that was recommended, and each can change.

- **Moves also go through a relay room** (changed on 2026-11-15). Through Convex alone, a move reached the other phone about half a second late, while a drawing stroke through the relay arrives at once. Each board game now has a relay room while its screen is open, and every move goes through it as well as through Convex (see "Live and async"). Showing the partner's finger hovering over a column is still left for later. Ludo also sends each roll through the room, so both dice tumble together (see `docs/games/ludo.md`). Ultimate Tic-Tac-Toe also sends the cell a player picked before Lock in, so the partner sees it.
- **Saving a mark needs a connection.** The editor keeps the drawing and shows a banner when the save fails. A mark is not queued like a move.
- **A refused move is told on the board.** The board keeps the notice until it opens, then shows the banner. The Games tab shows the game as it is, without a banner.
- **The stake counts Unicode scalars.** The server counts them, so the phone counts them the same way and never sends a stake the server refuses.
- **An empty stake means no stake.** The server accepts it from anyone on any move and stores nothing.
- **A mark can be drawn before the partner joins.** Starting a game needs both partners. Drawing a mark doesn't.
- **The reminder uses the shared body.** "Pick up where you left off." The title names the game.
- **Turn pushes carry a turn token.** `round_id` holds `<game number>:<move count>`, so the drain can tell whether the push is still wanted. It never holds the move.
- **The petal bloom comes from the board.** The result panel draws none, so a win blooms once, from the winning line.
- **Ultimate Tic-Tac-Toe never zooms by itself** (decided on 2026-10-23). The whole board stays in view, so the player keeps the overview. Zooming into a small board is a pinch, for looking closely, and there is no "Whole board" button.
- **A Four in a Row draw** dims the discs to 60% and brings them back.
- **Marks are drawn in blush** on boxes and cells, so both partners' marks read the same on their colors.
- **The partner's pieces are lavender.** Draw & Guess's second partner color is a pink close to the first, and on a full board the two sides were hard to tell apart, so the partner's pieces, glow and badge use `.paeoniaInkLavender`.

## Why these games

GamePigeon already has all three inside iMessage. They earn a place here only with the twist: the partner's own hand-drawn mark on every piece, a stake that is between the two of you, and a photo of the two of you that each box uncovers. All three are turn based, so they work async across time zones and feel live when both partners have the game open.

## Rules

Player one started the game and always moves first. Each game has a pure rules function on the server (`backend/convex/lib/<camelKind>.ts`) and the same rules on the phone (`Features/Games/BoardGames/<Folder>/<Game>Board.swift`). The server stores only the list of moves. The board, whose turn it is and the outcome come from replaying them. Both sides have tests for wins, draws and illegal moves.

### Four in a Row

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
- **Turns.** Only the partner whose turn it is can move. In Dots and Boxes a turn can hold several moves. The line under the board says "Your turn" or "[Name]'s turn" next to a small dot in that player's color, and a ring in the same color circles that player's avatar. The line cross-fades when the turn passes. A game's own hint takes the line's place while it has one, such as Ludo's "Roll again" or Ultimate Tic-Tac-Toe's "Choose a board". A finished game has no line, because the result panel says how it ended. The line always keeps its height, so the board never moves when it changes (`BoardGameStatusRow`).
- **Another turn.** Each time a move earns me another one, such as closing a box in Dots and Boxes, the line says "Another turn" for 1.5 seconds, rising into place, and then goes back to "Your turn". A hint on screen at that moment already says it, so the line keeps the hint.
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
- Later the editor opens from "Your mark" in the game settings sheet on the hub, "Your mark in games" on the More tab, and "Your mark" in the board's toolbar menu or a long press on its hub card. It never blocks a game.
- Saving needs a connection. A failed save keeps the drawing in the editor and shows "We couldn't save your mark. Check your connection and try again."
- The partner's new mark shows on their pieces the next time the board renders. Nobody gets a push for it.

### A bet

- Only the partner who starts the game can write the stake, and only before their first move. It goes to the server with that first move, so it is fixed from then on, and the other partner sees both together.
- Before the first move the starter sees a quiet "Add a bet" button ("Legg til et veddemål") under the board, above the pinned bottom. Tapping it opens a one-line text field that rises with the keyboard, with the keyboard's Done button. The text can be changed until the first move. The code calls the bet a stake.
- A stake holds 1 to 60 characters on one line. It is optional.
- While playing, the stake shows under the board in a capsule: "Bet: Loser makes coffee".
- The capsule stays above the result panel, so the panel does not repeat the stake. Its title already says who won.
- Push notifications and the lock screen never show the stake.

### The hidden photo

- When a Dots and Boxes game starts, the server picks a random photo from the couple's newest 500 files: a photo in a visible memory, a story photo, or the photo of a Guess my spot round that has been guessed. A round still waiting for its guess is skipped, so the board never shows the photo before the guesser does. The server checks the photo again every time the game is read. A photo whose memory was deleted or hidden, whose story was deleted, or whose round was deleted stops showing, and the board falls back to plain boxes.
- The phone loads the photo the same way Memories does. The photo is never shown whole until the last box closes. Each closed box shows its own piece.
- The phone has the whole photo, so a partner could in theory peek. Cheating is not a real risk between partners, the same reasoning as the Draw & Guess word.
- A couple with no photos gets plain colored boxes with the owner's mark, and nothing on screen mentions a missing photo.

## Live and async

- **Moves go through the relay room and Convex.** While the board screen is open, the phone keeps the game's relay room open (`<couple>:<kind.relayChannel>`). Once a move is saved on the phone, it goes to the partner through the room, and the outbox sends it to Convex as before. The partner's board shows it at once, with the same animation as a move from Convex. Convex stays the record. The partner's phone puts the live move on top of the server's game only while the server's game is at the version the move names, so the move drops out by itself once Convex has it. Until then the partner cannot move, because their next move would name a version the server does not have yet. A live move that Convex has not taken after 15 seconds is dropped, and the board shows the server's game again. A move that fails to save on the phone never goes to the partner. Ludo's rolls and Ultimate Tic-Tac-Toe's picked cell go through the same room. Nothing sent through the relay is saved.
- **Presence.** The open board screen sends the game's presence heartbeat, as Draw & Guess does. While the partner has the same game open, the shared green presence ring surrounds their avatar, outside the turn ring when both show. The status row stays about the turn and never says who is here.
- **Invite.** While the partner is not in the game, the board shows "Tell [Name] you want to play" (see `docs/games-plan.md`).
- **The partner's moves arrive animated.** A move that arrives while the board is open plays its animation. When the board opens after the partner moved, it first shows the board as this phone left it for 0.6 seconds, so the person sees where things stood. Then the moves since this phone last showed the board play in order, each one after the last one's animation. A tap on the board skips to the end.
- **Offline.** A move made offline shows on the board at once and is saved on the phone as a pending operation. The screen shows no routine save status. Moves leave in order. A move the server refuses as stale or illegal is dropped with "Your move wasn't sent", and the board shows the server's state again.
- **Notifications.**
  - "Your turn in Four in a Row" when the turn passes to you, skipped while you have that game open.
  - "[Name] finished your game of Four in a Row" when the partner's move ends the game, skipped while you have it open.
  - "[Name] wants to play Four in a Row with you" for an invite.
  - One reminder, "Your turn in Four in a Row", when a turn has waited 72 hours. A turn never gets a second one, and a finished game gets none.
  - Pushes name only the game. They never show the move, the stake or the result.

## Scoring

- The server keeps every partner's wins, the draws and the number of finished games for each kind, whatever the play style. Switching style loses nothing.
- **Against each other.** The toolbar capsule shows my avatar and wins next to my partner's avatar and wins. The result counts the winner's tally up by one.
- **Together.** The capsule shows a heart and "12 games". The result says "[Name] won this one" or "You won this one", then counts the couple's games up by one.

## Streak

Every accepted move records `game_turn_completed` with the dedupe key `game_turn_completed:<game id>:<game number>:<move number>`.

## Wide layouts and Dynamic Type

- Wide means 700 pt or more and wider than tall, as in Draw & Guess. The board sits on the left (up to 640 pt), and the players, stake, status and result sit in a column on the right (up to 420 pt). Ludo's board bleeds, so it keeps the single column on a wide screen. Its 3D view covers the whole screen behind the rows, the camera fits the board in the space between the players row and the status row, and the screen color fades in over the board past that space so the rows stay readable. When that space changes, for example as a result panel comes, the board and its camera glide to the new space over `PaeoniaMotion.stateChange` instead of jumping. Reduce Motion snaps. It is not a material blur: a material can't blur the 3D view and shows gray strips over the plain background.
- At accessibility text sizes the players row stacks and the screen scrolls. The board keeps its size.
