# Ludo

Design for Ludo, the fourth board game. It runs on the board game engine from `docs/games/board-games.md`: one `board_games` row, `make_move` with a pure rules function, the drawn mark, the stake, the shell, the result panel, the tallies, the pushes and the offline queue. This file covers only what is different. Shared rules for all games live in `docs/games-plan.md`.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-14 with the developer.

- **A real 3D board, built in code with RealityKit.** RealityKit's `ARView` in its non-AR mode shows a tilted board with lights, soft shadows and a camera. The board is one glazed ceramic slab with the whole layout painted on its flat top and grooves carved round every square, like a real board. The pawns and the die are rounded meshes made in code, in the house palette, so a pawn always lands exactly on its square. No Metal, no SceneKit (deprecated at WWDC25), and no model files. The surfaces use scanned CC0 textures and a photographed studio for the light (see "Materials"). The die is thrown by hand and flies by a small rigid-body simulation in Swift (`LudoDiePhysics`), not RealityKit physics. The number is picked first, as the rules need, and the simulation tries slightly different spins until one lands on it, so the die really rolls there. The simulation is pure math, so both phones fly the same throw.
- **Two pawns each.** A shorter game than classic Ludo's four, because async turns can take hours.
- **The phone rolls the die.** The roll goes to the server inside the move, so a move can be made offline and queued like every other board game move. The roll also goes live through the relay the moment the die starts to tumble, with the throw, so a partner with the game open sees the same flight at the same time. A partner could cheat in theory. The board games already accept that between partners (see "The hidden photo" in `docs/games/board-games.md`).

Decided on 2026-10-15 with the developer.

- **Pick your color.** Ludo only. Each partner picks one of the four corner colors (pink, lavender, gold, sky blue) for their pawns at the start of each game. The two colors nobody picked stay as the empty corners. Both phones show the same color for the same person, so if I pick gold, my partner sees my corner, pawns and avatar in gold too. Nobody waits for a pick: a partner who has not picked keeps the color from the last game. The other board games keep pink for me and lavender for my partner.

## Decisions made without the developer

Made on 2026-10-14. Each can change.

- **The name is Ludo in both languages.** Norway calls the game Ludo.
- **A rolled die is kept.** The phone saves the roll before the die stops, with the game number and move count. Leaving and reopening the screen shows the same roll, so closing the app does not give a new one. The phone keeps it in the board games local document (`ludoRoll`), keyed by game, game number and move count, so sign out clears it with the rest and a different position ignores it.
- **One option moves by itself.** When only one move is possible, the pawn moves 0.5 seconds after the die lands. Two pawns on the same square, or both in the base, count as one option.
- **No legal move passes by itself.** The die lands, the board says "No move with a 3", and the turn passes after 1.2 seconds. With no pawn out, the pass only uses up one of the three tries for a 6.
- **No penalty for three sixes.** Ludo variants that take away the turn after three sixes punish luck. This one doesn't.
- **No blocks.** Two pawns of the same player on one square do not block the partner.
- **Teach by playing.** The status row says "Tap the die to roll" on the first roll of a game, "Roll a 6 to bring a pawn out" while all my pawns wait in the base, and "2 tries left to roll a 6" after a missed 6.

## Why Ludo

Ludo is the board game most couples already know, and it is the one board game here built on luck, so a partner who loses at Connect Four can still win it. It earns its place in Paeonia the same way the other board games do: each partner's drawn mark is printed on top of their pawns, the starter can play for something, and the pawns are in the couple's own colors.

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

### Swift API

`LudoBoard` conforms to `BoardGameRules`. The scene and the screen code use only this:

```swift
nonisolated struct LudoBoard: BoardGameRules {
    static let pawnsPerPlayer = 2
    static let homeProgress = 57
    static let trackLength = 52
    static let safeSquares: Set<Int>          // 0, 8, 13, 21, 26, 34, 39, 47
    static func startSquare(of player: BoardPlayer) -> Int  // 0 or 26

    /// Progress 0...57 per pawn. Index `pawnIndex(player, pawn)`: player one's pawns are 0 and 1, player two's are 2 and 3.
    let progress: [Int]
    static func pawnIndex(_ player: BoardPlayer, _ pawn: Int) -> Int

    static func move(die: Int, choice: LudoChoice) -> Int
    static func decode(_ move: Int) -> (die: Int, choice: LudoChoice)?

    /// The moves `next` can make with `die`: the movable pawns, or `[.pass]`.
    func legalChoices(die: Int) -> [LudoChoice]
    /// What one move does, for animation. Nil when the move is illegal.
    func transition(_ move: Int) -> LudoTransition?
}

nonisolated enum LudoChoice: Int, Sendable { case first = 0, second = 1, pass = 2 }

nonisolated enum LudoSquare: Equatable, Sendable {
    case base(BoardPlayer, slot: Int)
    case track(Int)                 // 0...51
    case homeColumn(BoardPlayer, step: Int)  // 1...5
    case home(BoardPlayer)
}

nonisolated struct LudoTransition: Equatable, Sendable {
    let player: BoardPlayer
    let die: Int
    let choice: LudoChoice
    /// The pawn that moved, as a `pawnIndex`, and every square it steps on in order, the last one included. Empty for a pass.
    let pawn: Int?
    let path: [LudoSquare]
    /// Partner pawns sent back to their base, as pawn indexes.
    let sentHome: [Int]
    let rollsAgain: Bool
}

extension LudoBoard {
    func square(ofPawn index: Int) -> LudoSquare
}
```

## Play

### Rolling

- On my turn the die sits in my yard and bobs gently. A drag that starts on the die picks it up: it rises 1.1 cells and follows my finger above the yard, and letting go throws it in the direction and at the speed of the flick, from 3 to 9 cells a second. A tap throws it from where it rests, away from me, give or take a little. The die bounces off the yard's edges and the pawns waiting in it, and lands flat with the rolled face up wherever the throw takes it, usually within a second and never later than 1.45 seconds. It plays `selection()` on each hard hit and a soft impact when it settles. It stays where it landed until it changes yards.
- The pawns I can move lift and glow in my color. Tapping one moves it. Tapping a pawn that can't move gives `gameWrongGuess()` and a small shake.
- The pawn hops square by square, 0.16 seconds a square, with a light tick on each landing. Coming out of the base is one hop onto the start square.
- Sending a partner's pawn home: my pawn lands, the partner's pawn pops up, arcs back to its base and settles, with `streakTick()`.
- A pawn reaching home stands on my half of the middle, which glows in my color.
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
- Replays follow the board games rule: moves since this phone last showed the board play in order, and a tap skips to the end.

### Timing

`BoardGameMoveTiming(mine: 1.4 s, partner: 3.05 s)`. My move's tumble happens before the move exists, so my timing covers only the hops and a send-home. The partner's covers the tumble too.

### Result

The result follows the board games table. At 0.15 the winner's home glows and the other pawns dim to 40%. At 0.70 the petal bloom rises from the center of the board.

### Reduce Motion

The die shows its face without tumbling. Pawns fade from one square to the next instead of hopping. A pawn sent home fades out and fades in at its base.

### VoiceOver

The 3D view is hidden from VoiceOver. A SwiftUI layer on top gives it:

- The die: "Roll the die" while I can roll, or "Rolled a 4" after.
- Each of my movable pawns: "Your pawn 1, 23 squares from home", with the action "Move 4 squares".
- Announcements: "[Name] rolled a 5 and moved a pawn", "[Name] sent your pawn home", "No move with a 3".

## Look

The art director owns the look, refines this section, and records the final values here. The values in `LudoSceneStyle.swift` must match it.

The scene should look like the hub card's board (`GameHubLudoBoard`) come to life: the same blush slab, full-color player corners, quiet gold and sky corners, a two-colored center and chunky glossy pawns. The pieces match the house sticker set (`GameHubPeony`, `GameHubConnectFourDiscPink`): rounded clay forms and a soft sheen on the pieces you touch. The board lies on a wooden table in a dark room, lit by a warm orange lamp and a candle, with a soft peach rim.

Lengths are in board cells, as in `LudoSceneStyle`: x runs to the right, y up, and z toward the viewer, so the camera stands at +z.

### The board

- The board is one thick blush slab of glazed ceramic, 0.7 cells thick, lying on a wooden table (see "The room"). Its corners are round seen from above (radius 1.6 cells), so it reads as a soft, safe object and not a sharp tile, and its top edge is softly rounded (radius 0.12). A lip of plain glaze 0.5 cells wide runs round the 15 by 15 grid. The slab is a mesh made in code (`LudoMeshGeometry+Board`), and its flat top inside the rounded edge carries the painting.
- No piece of the board stands up from it. Real boards are printed or painted flat, and raised tiles made the board look like separate pieces. The whole layout is painted on the flat top at height 0, where every pawn and the die stand (`LudoBoardArt`). The track squares are painted whiter than the slab, so the track reads as squares.
- Grooves are carved round every track and home column square, round a panel inside each base, round each pawn spot, round the middle, and along the seam of the middle. A groove is 0.06 cells wide and soft-edged. The light reads it from a bump picture, and the glaze pools 30 percent darker at its bottom, as on real carved ceramic. The painting is 2,048 pixels across and the bump picture 1,024. The painting is drawn when the board opens, off the main actor, and again when a player picks another color. The grooves are the same for both players and every color, so the bump picture is made once and reused.
- Colors belong to the person and are the same on both phones (see "Your color"). By default my base, start square and home column are petal pink (`.boardGameMine`) and my partner's are lavender (`.boardGamePartner`). The two colors nobody picked fill the two corners nobody plays, quiet by default: the first one at the top left and the second at the bottom right, in the order pink, lavender, gold, sky blue. With the defaults that is gold at the top left and sky blue at the bottom right.
- The board turns so my base is always nearest me at the bottom left.
- Each base fills its 6 by 6 corner in the corner's color, with its outer corner rounded (radius 1.0) to follow the board's, and a carved panel inset 0.25 cells (corner radius 0.5). The players' bases have a darker painted round spot, carved round its edge, where each pawn waits. The two empty corners have no spots.
- The middle is a painted round, 2.8 cells across, split in two halves: mine in my color on the near side and my partner's in theirs on the far side, pink and lavender by default. The carved seam runs across the board between the two home columns, so each column runs into its own half. This is the seam of the hub series, where the two worlds meet. A pawn at home stands on its own half. When a pawn arrives the half glows in the player's color: a flat glowing half disc just above the painting fades in (`homeGlows`).
- Safe squares carry a peony instead of a star: `LudoPeonyTop` painted on the square (see "Illustrated textures" below). The two players' start squares are colored and carry no peony. The other six safe squares (8, 13, 21, 34, 39 and 47) do.

### Colors

| Part | Hex | Note |
|---|---|---|
| Slab | `#F4DCE6` | Warm blush, a step darker than the track squares |
| Track squares | `#FFF8FB` | |
| Pink, the first game's color for player one | `#F27EB2` | `.boardGameMine` |
| Lavender, the first game's color for player two | `#B99CF2` | `.boardGamePartner` |
| Home column squares | The player's color mixed 10 percent with white | |
| Base | The corner color mixed 10 percent with white | |
| Pawn spots in a base | The base mixed 12 percent with black | |
| Gold | `#E9CF98` | Same as the painting. An empty corner unless a player picked it |
| Sky blue | `#A9C6E6` | Same as the painting. An empty corner unless a player picked it |
| A player's corner, start square, center half and pawns | The player's color | Any of the four. The home column and the base use the mixes above |
| Die | `#FFF8FB` | |
| Pips | `#4F203A` | Plum hearts, see the die |
| Mark on a pawn top | `#FFFFFF` | On the pawn's color darkened 38 percent, so the initial stands out |
| Ground and background | `#2A0B1E` | `.paeoniaBackgroundSecondary`, so the board sits on the screen |

### Pawns

The pawn follows the round-headed pawn the hub card first used, a little chunkier in the head so the mark stays readable from the camera. All sizes are 1.4 times the first version, so the pawns read on a phone. Pawns that share a square stand 0.5 cells apart at 66 percent size.

| Value | Cells | Share of the height |
|---|---|---|
| Height | 1.29 | 1.0 |
| Base radius | 0.49 | widest at 0.08 of the height |
| Waist radius | 0.18 | at 0.48 |
| Head radius | 0.42 | widest at 0.74 |
| Flat top radius | 0.32 | at the top |

The mark fills 86 percent of the flat top. A pawn is the player's color all over, with no second color.

### The die

- The die is blush white with rounded edges (corner radius 0.23 of a 1.3 die) and pips shaped as small plum hearts. Hearts match the heart discs of Connect Four and Ultimate Tic-Tac-Toe, and six hearts still count at a glance.
- A heart pip is 0.27 cells wide, raised 0.04 cells, with rounded edges. Its point faces the face's `down` direction, so on the top face it points toward the viewer and reads upright. Pip places stay as they are.
- There are no trays. The die rests in the base yard of whoever rolls: my corner on my roll, my partner's corner on theirs. It starts in the free space of the yard beside the two pawn spots, which sit in the yard's outer row. A throw can take it anywhere inside the base's carved panel, and it stays where it lands. A die that changes player hops from one yard to the other.

### Materials

Everything is glazed ceramic. Two scanned CC0 texture sets from ambientCG give the glaze its grain, made gray by `ios/Scripts/ludo-surfaces.swift` so the players' colors tint them (`LudoGlazeDetail`, `LudoGlazeRoughness`, `LudoGlazeNormal`). The clay grain of Clay005 shows faintly through, with sparse iron speckle, and the gloss comes from Porcelain002's roughness, so a surface shines unevenly like a real glaze. Its roughness runs from about half to all of the number in the table. The board top lays the grain over its painting, repeated every 4 cells. The slab's edge and the die have the grain as bumps too. The pawns and the mark discs are made in code without the directions a bump picture needs, so they have the glaze without bumps.

The finish is a soft satin glaze, not a gloss. Glossy pieces under a bright light looked like plastic, so every part is rough enough that the lamp leaves a broad sheen and no glare. All materials are metallic 0 and specular 0.35, with self fill 0.02 so shadows never go fully black. The studio picture lights the shaded sides, and a stronger self fill made every surface look flat. Clearcoat roughness is 0.4 everywhere, so the thin clearcoat gives a broad, soft sheen instead of a small sharp highlight. The pips stay one flat color.

| Material | Roughness | Clearcoat |
|---|---|---|
| Slab and its painted top | 0.85 | 0.03 |
| Pawns | 0.55 | 0.15 |
| Die | 0.55 | 0.15 |
| Pips | 0.5 | 0 |

The pieces you touch, the pawns and the die, have a little more sheen than the board. A movable pawn and a winning home glow with emissive intensity 0.8 in the player's color mixed 15 percent with white. A glow in the pawn's own color barely shows on a lit pawn, and more white makes the pawn look pale and switched off. With the lift of 0.34 cells, a movable pawn reads as a brighter pink piece that rises.

### Light

The light is a warm orange, like a lamp or the last sun on an evening, and soft. A narrow lamp made a bright pool with dark edges, like an interrogation light, so the main light is wide and lights the whole board evenly. The numbers were tuned in an offscreen RealityKit render of the board on a Mac, so check them on a phone after a change.

- The main light is a wide orange lamp, a spot light high over the far left at (-9, 20, -7) aimed at the board's center, color `#FF8A3C`, 5,500,000 lumens, with a 120 degree cone that is at full strength in its middle 80 percent. It is the only light that casts shadows. The lamp is 0.7 cells across (`SpotLightComponent.Shadow.lightSize`, iOS 27), so the shadows have soft edges. A bigger lamp makes them softer and grainier. They do not depend on the camera, so they stay put as it turns and zooms.
- A dim warm key light from high on the right, a directional light from (7, 14, 1.5), `#FFA060`, 350 lux, keeps the faces turned from the lamp in color. A warm fill from the front left, from (-8, 9, 7), `#FF9A66`, 500 lux, keeps every side of a piece from going dark. Neither casts shadows.
- The rim light is a soft peach from low behind on the right, a directional light from (12, 2.5, -6), `#FFA08A`, 1,500 lux, no shadows. It draws a faint warm edge on the right sides of the pawns and the die.
- The soft fill is a photo of a warm living room with a lit fireplace, Poly Haven's CC0 `fireplace`, kept as the OpenEXR data asset `LudoRoomLight` so its lamps keep their brightness. The same script touches the photo with the two worlds of the hub series, a quarter of the way toward pink `#E88DBA` on the left half of the horizon, lavender `#A992E6` on the right and a light blush `#F6DCEA` zenith, as the room is warm already. It turns the floor dark and nearly neutral with a hint of `#2A0B1E` plum: a strong plum floor showed as magenta in the polished brass. At `environmentExposure` 0 it matches the brightness of the painted sky it replaced. It runs at -0.3, a little darker, so its cool pink and lavender do not wash out the orange. The pawns and the die pick up pink on their left side and lavender on their right. If the colors land on the wrong sides, turn on `mirrorsSky`.
- The candle on the table gives a small warm light of its own (see "The room").
- The view turns off ARView's grounding shadows, motion blur, depth of field and camera grain.

### The room

The board is a safe place in a quiet evening at home: it lies on a wooden table, with a lit candle and a pot of tea with two cups, one for each of us, and the table fades into a dark room (`LudoRoom`).

- The scene fills the whole screen. The board view runs under the navigation bar, the players row and the status row, with no cover over it, and the navigation bar has no background on this screen. Past the table the view shows the room's color, `#220A18`, a dark plum close to the app's own background, so the warm table fades into the same color as the rows on top of it. The players row's glass takes a light plum tint, so the warm scene glows through it.
- The table is lacquered cherry, Poly Haven's CC0 `lacquered_cherry_wood` (`LudoTableColor`, `LudoTableNormal`, `LudoTableRoughness`), repeating every 30 cells over a table 140 cells across. Its top is at the bottom of the slab. Its gloss follows the grain: `ios/Scripts/ludo-surfaces.swift` makes the roughness picture from the wood's own colors, rough in the dark grain lines and pores and glossier between them, and makes the grain's bumps 2.5 times stronger. There is no clearcoat, which lay over the grain as one smooth sheen. A linen runner, Poly Haven's CC0 `rough_linen` made gray by the script and tinted `#D9C4A8` (`LudoRunnerDetail`, `LudoRunnerNormal`, `LudoRunnerRoughness`), lies along the middle of the table from far to near, 11 cells wide and 0.02 thick, under the board and the props, with the weave repeating every 6 cells. A see-through layer of the room's color lies over both, clear within 13 cells of the middle and thick from 34 cells out, so the table fades into the dark however the camera turns.
- The props are CC0 models from Poly Haven, kept as geometry only in `Resources/LudoRoom` (`LudoBrassCandle.usdz`, the single candle of `brass_candleholders`, and `LudoTeaSet.usdz` from `tea_set_01`). The models describe their materials in a way RealityKit does not read reliably, so the app makes their materials from small pictures in the asset catalog (`LudoBrassCandle*` and `LudoTeaSet*`, both with a metallic picture for the brass and the gilt rims). The candle's file keeps only its holder and wax: its own flame, the faces and points under it, and its material groups are taken out. A mesh with a material group and no material shows RealityKit's magenta pattern, and the leftover flame points made the candle look taller. The models are Z-up and in meters, so the app stands them up and scales them by 26 cells to the meter, a third smaller than true size so they do not crowd the board.
- The candle stands off the far left corner of the board at (-8.5, -9). The teapot stands at (5.5, -12.5) and my partner's cup at (9.5, -9.5) on the far side, and my cup at (2.5, 11) in front of the board, near me. The tea set comes laid out like a catalog photo, so the app takes the teapot and two cups and stands each cup in its saucer. Each cup holds tea: a glossy dark amber disc, `#5A2A10`, near the rim.
- The flame is a small glowing teardrop made in code, 0.9 cells tall, with a softer glow round it. A warm point light at the flame, `#FF9A3C`, 400,000 lumens with a reach of 30 cells, warms the table and the near props. The flame and its light flicker a little, the light by up to 12 percent. Under Reduce Motion they hold still.

### Loading

The scene takes a moment to build, longest on the first open. Until it has drawn three frames, the board shows `LudoLoadingView`: the room's dark color with a small candle flame that flickers, and "Setting the table". The flame and the words come in softly. The loading view shows for at least 1.2 seconds, so a fast load never flashes it, then fades over 0.8 seconds into the scene, which sits on the same dark color, so the flame seems to be lit before the room appears. It stays in place and fades by its opacity: a view removed from the stack over the 3D view vanished at once instead of fading. Reduce Motion holds the flame still and switches without the fades.

- The board painting and the room load side by side, and the studio light loads while the board builds.
- The grooves' bump picture is the same for both players and every color, so it is made once and kept. The room is kept after the first build and copied for the next board, and the studio light is loaded once.

### Camera

The default camera looks down at 50 degrees, turned 18 degrees round the board, as if seated at the table by the corner of my own base, with a vertical field of view of 30 degrees. The lower, turned view shows the props standing up round the board, and the narrow field keeps a pawn on the far side big enough to tap. There is no camera roll.

The board view takes the full width of the screen and all the height of the screen, and the camera frames the scene inside the space between the players row and the status row (`boardFitHeight`). The whole slab fits that space both ways, so no corner runs off the screen. The props (the candle to the tip of its flame, the teapot and both cups, listed in `framedProps`) must also stay inside it from top to bottom, so none sits under the players row or the button, but they may run off the sides. The camera then centers the whole group from top to bottom. A camera that fitted only the board ran its corners off the sides and hid the candle and the teapot under the rows.

The person can handle the board like a model:

- A one-finger drag orbits the camera around the board point in the middle of the view. Yaw is free. Pitch stays between 35 and 80 degrees. The orbit keeps going a little after the finger lifts and slows down.
- A pinch zooms between 0.55 and 1.35 times the default distance. The board point under the fingers stays under them, so moving the two fingers also slides the board. The slide reaches up to 4.5 cells from the middle at the closest zoom, enough to center a base, and shrinks to none at the default distance, so zooming out brings the board back to the middle.
- A double tap glides back to the default view in 0.5 seconds.
- Taps on the die and the pawns keep working. A drag needs a small movement to start, which tells it from a tap.
- The board stays where the person leaves it.
- Reduce Motion: no inertia, and the reset cuts instead of gliding.
- VoiceOver follows the camera, so its elements stay on the pieces.

### Illustrated textures

One illustrated texture goes into the scene. Everything else is made in code.

| Asset | Size | Aspect | Where |
|---|---|---|---|
| `LudoPeonyTop` (folder `Ludo`) | 256 by 254 px | 1.008 | Painted into the board top on the six peony safe squares, 0.7 cells across. It replaces the turned bud mesh. |

The peony is a top view with very soft painted shading, so the scene's light shades it lightly.

## Data

The kind, the live roll and the colors. `ludo` joins `BOARD_GAME_KINDS`, `GAME_KINDS`, the relay's `ALLOWED_CHANNELS`, the schema's `board_games.kind` literal, `GAME_BACKENDS` (with `boardGameBackend`), `GAME_PUSH_COPY` and `BOARD_RULES`. In Swift it is `GameKind.ludo`, path `ludo`, folder `Features/Games/BoardGames/Ludo`.

Colors. `board_games.colors_by_user` maps each player's user id to `pink`, `lavender`, `gold` or `sky`, always two different colors. `ensure_board_game` sets player one to pink and the partner to lavender, and the colors stay through rematches. `make_move` takes an optional `p_ludo_color`. It counts only when the mover has no move yet in this game (the server replays the moves to check) and the partner does not have that color. Any other pick is ignored without refusing the move. A color sent with another board game is refused with `23514 that color is not allowed`. `get_board_games` returns `my_color` and `partner_color` for the caller, both null outside Ludo. The pick is part of the move's request hash. On the phone `BoardGameMovePayload.ludoColor` carries it and `BoardGameResolver` shows it on top of the server's colors, and `BoardGameViewModel.ludoColors` is what the screen shows.

Notifications follow the board games: "Your turn in Ludo", "Your game of Ludo is over", "[Name] wants to play Ludo with you", and one reminder after 72 hours.

## Hub card

The shared backdrop with the Ludo board on it, made to `docs/games/hub-artwork.md`, with its beat. The card's status lines and buttons are the board games' own.

- The board is `GameHubLudoBoard`, 600 pixels wide on the canvas. It shows the cream board with a corner in each color, one pink pawn and one lavender pawn on the track, and the dome in the center empty.
- The beat (`LudoHubArtwork`, 1.8 seconds): a pink pawn (`GameHubLudoPawnPink`, 81 pixels tall) pops up on the last pink tile before the dome, hops onto the dome's seam, squashes as it lands, and the dome glows gold. The pawn is the board's own pink pawn, cut out of the board image, so it has the board's camera and light. It has no shadow of its own, since one made it look like it floated over the dome.
- The pawn lands on the seam, not on the pink half where a pawn stands at home in the game. Pink on the pink half did not read, and the seam is where the series' two worlds meet.
- `art_asset.py text`: name 6.7, status 5.3, your turn 8.4, link 7.0.

## Open questions

None.
