# Ludo

Design for Ludo, the fourth board game. It runs on the board game engine from `docs/games/board-games.md`: one `board_games` row, `make_move` with a pure rules function, the drawn mark, the stake, the shell, the result panel, the tallies, the pushes and the offline queue. This file covers only what is different. Shared rules for all games live in `docs/games-plan.md`.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided on 2026-10-14 with the developer.

- **A real 3D board, built in code with RealityKit.** A `RealityView` shows a tilted board with lights, soft shadows and a camera. Tiles, pawns and the die are rounded meshes made in code with satin clay materials in the house palette, so a pawn always lands exactly on its square. No Metal, no SceneKit (deprecated at WWDC25), and no model files. The die tumble is a scripted animation, not physics, so it always lands on the rolled face and looks the same on both phones.
- **Two pawns each.** A shorter game than classic Ludo's four, because async turns can take hours.
- **The phone rolls the die.** The roll goes to the server inside the move, so a move can be made offline and queued like every other board game move. A partner could cheat in theory. The board games already accept that between partners (see "The hidden photo" in `docs/games/board-games.md`).

## Decisions made without the developer

Made on 2026-10-14. Each can change.

- **The name is Ludo in both languages.** Norway calls the game Ludo.
- **A rolled die is kept.** The phone saves the roll before the die stops, with the game number and move count. Leaving and reopening the screen shows the same roll, so closing the app does not give a new one. The phone keeps it in the board games local document (`ludoRoll`), keyed by game, game number and move count, so sign out clears it with the rest and a different position ignores it.
- **One option moves by itself.** When only one move is possible, the pawn moves 0.5 seconds after the die lands. Two pawns on the same square, or both in the base, count as one option.
- **No legal move passes by itself.** The die lands, the board says "No move with a 3", and the turn passes after 1.2 seconds.
- **No penalty for three sixes.** Ludo variants that take away the turn after three sixes punish luck. This one doesn't.
- **No blocks.** Two pawns of the same player on one square do not block the partner.
- **Teach by playing.** The status row says "Tap the die to roll" on the first roll of a game, and "Roll a 6 to bring a pawn out" while all my pawns wait in the base.

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

- On my turn the die sits on its tray at my side of the board and bobs gently. Tapping it rolls. The die tumbles for 0.8 seconds and lands with the rolled face up, with `selection()` on each bounce and a soft impact when it settles.
- The pawns I can move lift and glow in my color. Tapping one moves it. Tapping a pawn that can't move gives `gameWrongGuess()` and a small shake.
- The pawn hops square by square, 0.16 seconds a square, with a light tick on each landing. Coming out of the base is one hop onto the start square.
- Sending a partner's pawn home: my pawn lands, the partner's pawn pops up, arcs back to its base and settles, with `streakTick()`.
- A pawn reaching home sinks into the center, which pulses in my color.
- Another roll: the status row says "Roll again" and the die returns to my tray.

### The partner's move

- The die moves to the partner's tray and tumbles to their roll, then their pawn hops the same way. A move that sends my pawn home plays a soft `partnerDrawingReceived()`.
- Replays follow the board games rule: moves since this phone last showed the board play in order, and a tap skips to the end.

### Timing

`BoardGameMoveTiming(mine: 1.4 s, partner: 2.4 s)`. My move's tumble happens before the move exists, so my timing covers only the hops and a send-home. The partner's covers the tumble too.

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

The scene should look like the hub painting (`GameHubLudoPainting`) come to life: the same blush slab, full-color player corners, quiet gold and sky corners, a two-colored center and chunky glossy pawns. The pieces match the house sticker set (`GameHubPeony`, `GameHubConnectFourDiscPink`): rounded clay forms, a soft gloss on the pieces you touch, lit from the upper right with a pink rim.

Lengths are in board cells, as in `LudoSceneStyle`: x runs to the right, y up, and z toward the viewer, so the camera stands at +z.

### The board

- The board is a thick blush slab with rounded edges on the screen's deep plum. It has no border: the slab ends 0.25 cells past the 15 by 15 grid, a thin rounded lip that still reads as a thick board. The scene has a clear background, so the screen's plum shows around it. Tiles are raised squares, 0.18 cells tall with fully rounded edges like small pillows, and whiter than the slab, so the track reads as tiles.
- Colors follow the phone. My base, start square and home column are petal pink (`.boardGameMine`). My partner's are lavender (`.boardGamePartner`). The two corners nobody plays are quiet gold and sky blue.
- The board turns so my base is always nearest me at the bottom left.
- Each base is a raised pad, 5.6 cells square inside its 6 by 6 corner, 0.24 cells tall with a 0.6 corner radius. A rim of the slab shows around it and its rounded edge catches the light, so the corner reads as a sticker piece and not a flat block. The players' bases are full color, as in the painting, with darker round dents where the pawns wait. Only the two empty corners are pale.
- The center is a low round dome, 2.8 cells across and 0.26 tall in the middle, split in two halves: mine in pink and my partner's in lavender. The seam runs across the board between the two home columns, so each column runs into its own half. This is the seam of the hub series, where the two worlds meet. The empty corners have no pad in the center. A pawn at home stands on its own half, and the half glows in the player's color when a pawn arrives.
- Safe squares carry a flat peony instead of a star: `LudoPeonyTop` laid on the tile (see "Illustrated textures" below). The two players' start squares are colored and carry no peony. The other six safe squares (8, 13, 21, 34, 39 and 47) do.

### Colors

| Part | Hex | Note |
|---|---|---|
| Slab | `#F4DCE6` | Warm blush, a step darker than the tiles |
| Track tiles | `#FFF8FB` | |
| My corner, start square, center half | `#F27EB2` | `.boardGameMine` |
| Partner's corner, start square, center half | `#B99CF2` | `.boardGamePartner` |
| Home column tiles | The player's color mixed 10 percent with white | |
| Base plate | The corner color mixed 10 percent with white | |
| Base dents | The base plate mixed 12 percent with black | |
| Empty corner, gold | `#E9CF98` | Same as the painting |
| Empty corner, sky | `#A9C6E6` | Same as the painting |
| Die | `#FFF8FB` | |
| Pips | `#4F203A` | Plum hearts, see the die |
| Mark on a pawn top | `#FFFFFF` | On the pawn's color darkened 38 percent, so the initial stands out |
| Ground and background | `#2A0B1E` | `.paeoniaBackgroundSecondary`, so the board sits on the screen |

### Pawns

The pawn follows the illustrated pawn (`GameHubLudoPawnPink`), a little chunkier in the head so the mark stays readable from the camera. All sizes are 1.4 times the first version, so the pawns read on a phone. Pawns that share a square stand 0.5 cells apart at 66 percent size.

| Value | Cells | Share of the height |
|---|---|---|
| Height | 1.29 | 1.0 |
| Base radius | 0.49 | widest at 0.08 of the height |
| Waist radius | 0.18 | at 0.48 |
| Head radius | 0.42 | widest at 0.74 |
| Flat top radius | 0.32 | at the top |

The mark fills 86 percent of the flat top. A pawn is the player's color all over, with no second color.

### The die

- The die is blush white with rounded edges (corner radius 0.23 of a 1.3 die) and pips shaped as small plum hearts, as in the hub painting. Hearts match the heart discs of Connect Four and Ultimate Tic-Tac-Toe, and six hearts still count at a glance.
- A heart pip is 0.27 cells wide, raised 0.04 cells, with rounded edges. Its point faces the face's `down` direction, so on the top face it points toward the viewer and reads upright. Pip places stay as they are.
- There are no trays. The die rests in the base yard of whoever rolls: my corner on my roll, my partner's corner on theirs. It lies in the free space of the yard beside the two pawn slots, which sit in the yard's outer row, and it tumbles there too. A die that changes player hops from one yard to the other.

### Materials

All materials are metallic 0 and specular 0.5, with self fill 0.06 so shadows never go black. Clearcoat roughness is 0.12 everywhere, so the clearcoat gives a small, clear highlight.

| Material | Roughness | Clearcoat |
|---|---|---|
| Slab | 0.6 | 0.1 |
| Tiles, bases, home columns, trays | 0.45 | 0.2 |
| Center dome | 0.3 | 0.6 |
| Pawns | 0.24 | 0.9 |
| Die | 0.26 | 0.9 |
| Pips | 0.5 | 0 |
| Peony decal | 0.6 | 0 |

The pieces you touch, the pawns and the die, are glossier than the board, like the sticker discs. A movable pawn and a winning home glow with emissive intensity 0.8 in the player's color mixed 15 percent with white. A glow in the pawn's own color barely shows on a lit pawn, and more white makes the pawn look pale and switched off. With the lift of 0.34 cells, a movable pawn reads as a brighter pink piece that rises.

### Light

- The key light comes from high on the right and a little in front. The tops are lit, the fronts of the tiles and pads fall into soft shade, and the shading falls toward the lower left, as in every Paeonia illustration. The shaded fronts make each tile read as a raised piece. A directional light from position (7, 14, 1.5), looking at the board's center, color `#FFF0E4`, 2,800 lux, casting shadows. A stronger key washes the tile tops to white.
- The rim light is pink and comes low from behind on the right, so it draws a pink edge on the right sides of the pawns and the die. It is low so it grazes the pieces and adds little to the flat board. A directional light from (12, 2.5, -6), color `#F27EB2`, 6,000 lux, no shadows.
- The soft fill is the environment picture. Its sky carries the two worlds of the hub series: pink `#E88DBA` on the left half of the horizon, lavender `#A992E6` on the right, a light blush `#F6DCEA` zenith, and the `#2A0B1E` ground. The light zenith gives the glossy pieces and the dome a soft white highlight. The glossy pawns and the die then pick up pink on their left side and lavender on their right. If the colors land on the wrong sides, mirror the picture.
- Shadows are soft and short. The shadow reaches 30 cells (the slab is about 18 across), which keeps a pawn's shadow smooth without hard steps.

### Camera

The default camera looks down at 64 degrees with a vertical field of view of 30 degrees. The narrow field keeps the board flat and graphic like the painting, and a pawn on the far side stays big enough to tap. There is no camera roll.

The board fills the screen sideways. The board view takes the full width of the screen, past the shell's padding, and all the height between the players row and the status row. The camera stands as close as lets the near edge of the slab run up to 15 percent of the view's width past the left and right edges (`cameraOvershoot` 0.3), so the near corners run off the screen. The far edge then spans the width, and the far pawns stay well inside it. The board is centered from top to bottom. On a phone in portrait this board is about 15 percent taller than at 60 degrees with the near edge exactly at the screen's edges, which shrinks the plum bands above and below it.

The person can handle the board like a model:

- A one-finger drag orbits the camera around the middle of the board. Yaw is free. Pitch stays between 35 and 80 degrees. The orbit keeps going a little after the finger lifts and slows down.
- A pinch zooms between 0.55 and 1.35 times the default distance.
- A double tap glides back to the default view in 0.5 seconds.
- Taps on the die and the pawns keep working. A drag needs a small movement to start, which tells it from a tap.
- The board stays where the person leaves it.
- Reduce Motion: no inertia, and the reset cuts instead of gliding.
- VoiceOver follows the camera, so its elements stay on the pieces.

### Illustrated textures

One illustrated texture goes into the scene. Everything else is made in code.

| Asset | Size | Aspect | Where |
|---|---|---|---|
| `LudoPeonyTop` (folder `Ludo`) | 256 by 254 px | 1.008 | Flat on the six peony safe squares, 0.7 cells across, 0.004 above the tile top. It replaces the turned bud mesh. |

The peony is a top view with very soft painted shading, so the scene's light shades it lightly. Use its alpha as the material's opacity, roughness 0.6, no clearcoat. A soft painted ground under the board would not add enough to earn a texture: the plum ground and the environment's pink and lavender do the same job in code.

## Data

Nothing new beyond the kind. `ludo` joins `BOARD_GAME_KINDS`, `GAME_KINDS`, the relay's `ALLOWED_CHANNELS`, the schema's `board_games.kind` literal, `GAME_BACKENDS` (with `boardGameBackend`), `GAME_PUSH_COPY` and `BOARD_RULES`. In Swift it is `GameKind.ludo`, path `ludo`, folder `Features/Games/BoardGames/Ludo`.

Notifications follow the board games: "Your turn in Ludo", "Your game of Ludo is over", "[Name] wants to play Ludo with you", and one reminder after 72 hours.

## Hub card

A painting made to `docs/games/hub-artwork.md` by the art director, with its beat. The card's status lines and buttons are the board games' own.

- The painting is `GameHubLudoPainting`. It shows the blush board under the moon, the pink and lavender corners in full color, the gold and sky corners quiet, one pink pawn on the pink home column, two lavender pawns on the track, and a die with heart pips on the ground at the front right. The center dome is left empty.
- The beat (`LudoHubArtwork`, 1.8 seconds): the last pink pawn (`GameHubLudoPawnPink`, 84 pixels tall) pops up on the end of the pink home column at (349, 314), hops onto the dome's seam at (512, 330), squashes as it lands, and the dome glows gold, centered at (512, 337) with a radius of 190. Points are where the pawn's base touches the board, in the painting's pixels.
- The pawn lands on the seam, not on the pink half where a pawn stands at home in the game. Pink on the pink half did not read, and the seam is where the series' two worlds meet.
- `art_asset.py text`: name 6.7, status 5.3, your turn 8.4, link 7.0.

## Open questions

None.
