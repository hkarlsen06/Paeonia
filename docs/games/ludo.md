# Ludo

Design for Ludo, the fourth board game. It runs on the board game engine from `docs/games/board-games.md`: one `board_games` row, `make_move` with a pure rules function, the drawn mark, the stake, the shell, the result panel, the tallies, the pushes and the offline queue. This file covers only what is different. Shared rules for all games live in `docs/games-plan.md`.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-14 with the developer.

- **A real 3D board, built in code with RealityKit.** RealityKit's `ARView` in its non-AR mode shows a tilted board with lights, soft shadows and a camera. The board is one glazed ceramic slab with the whole layout painted on its flat top and grooves carved round every square, like a real board. The pawns and the die are rounded meshes made in code, in the house palette, so a pawn always lands exactly on its square. No Metal, no SceneKit (deprecated at WWDC25), and no model files. The surfaces use scanned CC0 textures and a photographed studio for the light (see "Materials"). The die is thrown by hand and flies by a small rigid-body simulation in Swift (`LudoDiePhysics`), not RealityKit physics. The number is picked first, as the rules need, and the simulation tries slightly different spins until one lands on it, so the die really rolls there. The simulation is pure math, so both phones fly the same throw.
- **Two pawns each.** A shorter game than classic Ludo's four, because async turns can take hours.
- **The phone rolls the die.** The roll goes to the server inside the move, so a move can be made offline and queued like every other board game move. The roll also goes live through the relay the moment the die starts to tumble, with the throw, so a partner with the game open sees the same flight at the same time. A partner could cheat in theory. The board games already accept that between partners (see "The hidden photo" in `docs/games/board-games.md`).

Decided on 2026-10-15 with the developer.

- **Every move is a tap.** Even when only one pawn can move, it glows and waits for the person to tap it. Moving it by itself took the person out of the game. Only a roll with no move passes by itself.
- **Pick your color.** Ludo only. Each partner picks one of the four corner colors (pink, lavender, gold, sky blue) for their pawns at the start of each game. The two colors nobody picked stay as the empty corners. Both phones show the same color for the same person, so if I pick gold, my partner sees my corner, pawns and avatar in gold too. Nobody waits for a pick: a partner who has not picked keeps the color from the last game. The other board games keep pink for me and lavender for my partner.

## Decisions made without the developer

Made on 2026-10-14. Each can change.

- **The name is Ludo in both languages.** Norway calls the game Ludo.
- **A rolled die is kept.** The phone saves the roll before the die stops, with the game number and move count. Leaving and reopening the screen shows the same roll, so closing the app does not give a new one. The phone keeps it in the board games local document (`ludoRoll`), keyed by game, game number and move count, so sign out clears it with the rest and a different position ignores it.
- **No legal move passes by itself.** The die lands, the board says "No move with a 3", and the turn passes after 1.2 seconds. With no pawn out, the pass only uses up one of the three tries for a 6.
- **No penalty for three sixes.** Ludo variants that take away the turn after three sixes punish luck. This one doesn't.
- **No blocks.** Two pawns of the same player on one square do not block the partner.
- **Teach by playing.** The status row says "Swipe the die to roll" on the first roll of a game, "Roll a 6 to bring a pawn out" while all my pawns wait in the base, and "2 tries left to roll a 6" after a missed 6.

## Why Ludo

Ludo is the board game most couples already know, and it is the one board game here built on luck, so a partner who loses at Four in a Row can still win it. It earns its place in Paeonia the same way the other board games do: each partner's drawn mark is printed on top of their pawns, the starter can play for something, and the pawns are in the couple's own colors.

## Rules

Player one started the game and moves first. The pure rules are in `backend/convex/lib/ludo.ts` and `Features/Games/BoardGames/Ludo/LudoBoard.swift`. They must agree move for move, and both have tests with the same fixture games.

### The board

- The classic cross board: 52 track squares in a loop, a home column of 5 squares for each player, and the home in the middle.
- Track squares are numbered 0 to 51 in the direction pawns move. Player one starts on square 0, player two on square 26, opposite.
- Safe squares are 0, 8, 13, 21, 26, 34, 39 and 47: the four start squares and the square 8 past each. A pawn on a safe square can't be sent home.

### A pawn's progress

Each pawn has a progress from 0 to 57:

| Progress | Where the pawn is |
|---|---|
| 0 | In its base |
| 1 to 51 | On the track, at square `(start + progress - 1) % 52`, where start is 0 for player one and 26 for player two |
| 52 to 56 | In its own home column, step 1 to 5 |
| 57 | Home |

A pawn walks 51 track squares, then turns into its home column. The track square just before its own start square is the one it never steps on.

### A turn

- Roll the die, then move one pawn by the number rolled.
- A pawn in the base comes out only on a 6. It goes to progress 1, its start square.
- A pawn needs the exact number to reach home. A roll that would take it past 57 can't move it.
- Landing on a track square that holds the partner's pawns sends them all back to their base, unless the square is safe. Pawns in a home column are never sent back.
- Two pawns of the same player can share a square.
- Rolling a 6, sending a pawn back, or bringing a pawn home gives another roll. A 6 gives another roll even when no pawn could move.
- When no pawn can move with the roll, the move is a pass. A pass is legal only when no pawn can move.
- A player with no pawn out, every pawn in the base or home, gets three tries to roll a 6. The first two missed 6s give another roll and the third passes the turn. The rules count the misses in `missedSixes`, so the server and the phone agree from the move list alone.
- The first player with both pawns home wins. Ludo has no draws. The winning move gives no extra roll.

### The move

A move is one integer: `(die - 1) * 3 + choice`, so `moveLimit` is 18.

- `die` is 1 to 6.
- `choice` is 0 for the mover's first pawn, 1 for the second, and 2 for a pass.

Illegal: an integer out of range, a pawn that can't move by that die, a pass while a pawn could move, a move after the game ended.

The outcome's `line` is empty. The winner is enough, because the board shows the win itself.

## Play

### Rolling

- A loaded board reports readiness again when navigation shows it again, so partner moves resume and the next turn can roll without reopening the game.

- On my turn the die sits in my yard and bobs gently. Any one-finger drag picks it up, wherever it starts on the screen. At other times a one-finger drag does nothing. A die still hopping into my yard lands at once when picked up. Once picked up, it rises 1.1 cells and follows my finger above the yard, and letting go throws it in the direction and at the speed of the flick, from 4 to 9 cells a second. A tap on the die does nothing, because a roll by accident cannot be taken back. VoiceOver's roll action throws it from where it rests, away from me, give or take a little. The die tumbles about two full turns, bounces off the yard's edges and the pawns waiting in it, and lands flat with the rolled face up wherever the throw takes it, within 2.05 seconds. It plays `selection()` on each hard hit and a soft impact when it settles. It stays where it landed until it changes yards.
- Once the rest of a throw stays within 0.08 cells and 0.12 radians of its final pose, the die eases flat over 0.1 seconds. Tiny final movements no longer hold up the pawn choice or the handoff. A later bounce or face change still plays in full.
- My pawns light up the moment the die comes to rest, with the settle tap. The screen waits for the longest throw, 2.05 seconds, only if the board never says the die landed. Waiting for the longest throw every time left a short throw resting on its number for over a second before anything happened.
- While a player picks a pawn, the square each movable pawn would land on glows in that player's color: a round disc 0.78 cells wide that breathes with the pawns' bob, at most 60 percent opacity (`LudoStage+Landings.swift`, `LudoBoard.landings(die:)`). Two pawns that would land on one square light it once, and a square with a partner pawn on it glows around that pawn, so a capture shows before it happens. Mine show once my die has landed and go out when I tap a pawn. The partner's show while their live roll rests in their yard and go out when their move arrives. A pass shows none.
- The pawns I can move lift and glow in my color. Tapping one moves it. Tapping a pawn that can't move gives `gameWrongGuess()` and a small shake.
- The pawn hops square by square, 0.16 seconds a square, with a light tick on each landing. Coming out of the base is one hop onto the start square.
- Sending a partner's pawn home: my pawn lands, the partner's pawn pops up, arcs back to its base and settles, with `streakTick()`.
- A pawn reaching home stands on my half of the middle, which pulses in my color. After the winning pawn the half stays lit and runs on into the result.
- Another roll: the status row says "Roll again", or "2 tries left to roll a 6" after a missed 6, and the die returns to my tray.

### Your color

- Before my first move of a game, a row sits under the status row, above "Add a bet": "Your color" and four round color circles (pink, lavender, gold and sky blue). It is there for the partner who moves second too, while they wait for the first move.
- The circle I have shows a ring and a check mark. The circle my partner has is faded, shows their initial and can't be tapped. A tap on another circle gives `selection()` and recolors my corner, start square, home column, half of the middle, pawns, avatar ring, name and the result at once. The board keeps its shape, so my corner stays on my near side.
- The row goes away when I make my first move of the game. A pick after that does not exist, so a color can't change in the middle of a game.
- The pick goes to the server inside that first move (`make_move` with `p_ludo_color`), so it works offline through the pending queue like the stake. My phone shows the pick on its own until then. The server stores each player's color on the game's row, and it stays for the next game.
- The server ignores a pick that is the partner's current color. The move still goes through. If both partners pick the same color before either move arrives, the first move wins, and the second phone shows its old color again once it hears.
- A new couple's first game gives the partner who opens the game pink and the other lavender.
- VoiceOver reads each circle as its color name, with "selected" on mine and "taken by [Name]" on my partner's. Reduce Motion turns off the small selection animation.
- The result of an ending I missed uses the colors the game has now.

### The partner's move

- With the game open on both phones, the partner's die tumbles on my phone while it tumbles on theirs. Their phone sends `LudoLiveMessage` (the game, game number, move count, face and throw) to the `<couple>:ludo` relay room as the tumble starts, and again, without the throw, when I open the game in the middle of their turn. The throw is in the frame of the roller's own yard, and my phone turns it half a circle onto their yard. Both phones run the same simulation, so the die flies and lands the same way. A die not already in the hand rises into the throw over 0.15 seconds. A roll without a throw uses the tap throw of its position, which both phones make the same. A roll for a position my board has not reached yet waits for the move that leads there. When their move arrives, the die has already rolled, so only the pawn hops.
- Without a live roll, for example when the relay is down or I open the game after they moved, the die tumbles to their roll when their move arrives, then their pawn hops the same way. A move that sends my pawn home plays a soft `partnerDrawingReceived()`.
- Replays follow the board games rule: moves since this phone last showed the board play in order, and a tap skips to the end. The replay waits until the loading view has faded (see "Loading"). It used to start at once, so a partner's move that sent my pawn home played under "Setting the table" and I only saw the result.

### Timing

`BoardGameMoveTiming(mine: 1.0 s, partner: 3.65 s)`. My move's tumble happens before the move exists, so my timing covers only the hops. It fits the longest winning move, 6 hops of 0.16 seconds, so the result follows my last pawn home without a wait. A send-home of mine takes up to 1.58 seconds, and when one replays, the next move ends it early. My own moves replay only when they were made on another phone. The partner's timing covers the tumble too, so it is the longest the partner's move can take. The board ends it sooner: once the partner's pawns stand still and their die has landed, `LudoBoardView` calls `BoardGameViewModel.finishMoveAnimation(number:)`, and my turn starts at once. Before, a move whose die had already rolled live kept my die waiting in my yard for up to 2 seconds.

### Result

The result follows the board games table. The winner's half of the middle is already lit from the moment the last pawn arrived. At 0.15 the other pawns dim to 40%. At 0.70 the petal bloom rises from the center of the board. The result waits only for the pawns to stand still, not for the home pulse to fade or the die to hop to the next yard, so the bloom lands with the win sound.

### Reduce Motion

The die shows its face without tumbling. Pawns fade from one square to the next instead of hopping. A pawn sent home fades out and fades in at its base.

### VoiceOver

The 3D view is hidden from VoiceOver. A SwiftUI layer on top gives it:

- The die: "Roll the die" while I can roll, or "Rolled a 4" after.
- Each of my movable pawns: "Your pawn 1, 23 squares from home", with the action "Move 4 squares".
- Announcements: "[Name] rolled a 5 and moved a pawn", "[Name] sent your pawn home", "No move with a 3".
