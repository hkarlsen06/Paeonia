import UIKit
import simd

/// Every number that shapes the look and the motion of the Ludo scene, in one
/// place. The art director tunes this file. Lengths are in world units, and one
/// board cell is 1.0. Angles are in degrees unless the name says radians.
nonisolated enum LudoSceneStyle {
    // MARK: Board

    /// The board is one glazed slab with the layout painted on its flat top (see
    /// `LudoBoardArt`). A lip of plain glaze runs round the 15 by 15 cells.
    static let slabMargin: Float = 0.5
    static let slabThickness: Float = 0.7
    /// The slab's corners are round, seen from above, and its top edge is softly
    /// rounded. The corner leaves the painted cells just inside it.
    static let slabCornerRadius: Float = 1.6
    static let slabEdgeRadius: Float = 0.12
    static let slabCornerSegments = 12
    static let slabEdgeSegments = 4
    /// Grooves are carved round every square, yard panel, pawn spot and the middle.
    /// Width and softness are in cells. Depth is how deep they look to the light.
    /// Pooling is how much darker the glaze is at the bottom of a groove.
    static let grooveWidth: Float = 0.06
    static let grooveSoftness: Float = 0.02
    static let grooveDepth: Float = 0.04
    static let groovePooling: Float = 0.3
    /// Pixels across the painted colors and the groove bumps. The colors are sharp to
    /// the closest zoom. Grooves are soft, so their picture can be smaller.
    static let boardArtSide = 2_048
    static let boardBumpSide = 1_024
    /// The glaze grain repeats every this many cells.
    static let boardGrainCells: Float = 4
    /// Each yard fills its 6 by 6 corner, its outer corner rounded like the board's,
    /// with a carved panel inset by this much.
    static let yardOuterCornerRadius: Float = 1.0
    static let yardPanelInset: Float = 0.25
    static let yardPanelCornerRadius: Float = 0.5
    /// The painted round spot where one pawn waits in its base.
    static let yardSlotRadius: Float = 0.6
    /// The middle is a painted round in two halves, mine and my partner's.
    static let homeDiameter: Float = 2.8
    /// The glow over a half of the middle lies this far above the board, to avoid flicker.
    static let homeGlowLift: Float = 0.003
    /// The disc on a square a movable pawn would land on: its width in cells, its
    /// height above the board, and its strongest opacity.
    static let landingSize: Float = 0.78
    static let landingLift: Float = 0.006
    static let landingOpacity: Float = 0.6
    /// Pawns that share a square stand this far apart, and shrink to `sharedPawnScale`.
    static let sharedPawnSpacing: Float = 0.5
    static let sharedPawnScale: Float = 0.66
    /// Pawns at home are a little smaller.
    static let homePawnScale: Float = 0.7
    /// The sideways distance between two pawns at home.
    static let homeLaneSpacing: Double = 0.45
    /// How far from the center point a player's home pawns stand, along their column.
    static let homeDistance: Double = 0.78

    // MARK: Room

    /// The board lies on a varnished wooden table in a dim room. The table ends a little
    /// past the props, so its edges show, and it stands on four legs `tableHeight` above
    /// a parquet floor. Its corners are a little round. The wood repeats every
    /// `tableGrainCells` cells.
    static let tableWidth: Float = 34
    static let tableDepth: Float = 44
    static let tableThickness: Float = 1.2
    static let tableCornerRadius: Float = 0.6
    static let tableGrainCells: Float = 30
    static let tableHeight: Float = 19
    /// Square legs, `tableLegSide` thick, set in from the corners by `tableLegInset`.
    static let tableLegSide: Float = 1.6
    static let tableLegInset: Float = 1.2
    /// The table's gloss comes from its roughness picture, which follows the grain (see
    /// `ios/Scripts/ludo-surfaces.swift`). This scales it. There is no clearcoat, which
    /// lay over the grain as one smooth sheen.
    static let tableRoughness: Float = 1
    /// The floor is herringbone parquet, `floorSize` across, so the view never shows where
    /// it ends, with the wood repeating every `floorGrainCells` cells. A cream wool rug lies
    /// under the table. The lamp lights the table, so the floor and the rug are darkened by
    /// their shade (1 is unchanged): clearly seen, but quiet, and the rows on top stay easy
    /// to read. A fade into the dark toward the top of the view looked like a horror film.
    static let floorSize: Float = 400
    static let floorGrainCells: Float = 18
    static let floorShade: CGFloat = 0.32
    static let rugShade: CGFloat = 0.42
    static let rugWidth: Float = 56
    static let rugDepth: Float = 68
    static let rugCornerRadius: Float = 2
    static let rugGrainCells: Float = 10
    static let rugLift: Float = 0.05
    /// The room is `roomHalfWidth` and `roomHalfDepth` cells from its middle to each wall,
    /// and its walls are `wallHeight` tall: beige plaster repeating every `wallGrainCells`
    /// cells, darkened like the floor, with a painted skirting board along the bottom.
    /// Each wall shows only from inside, so the one between the camera and the table
    /// is not drawn.
    static let roomHalfWidth: Float = 42
    static let roomHalfDepth: Float = 46
    static let wallHeight: Float = 72
    static let wallGrainCells: Float = 24
    static let wallShade: CGFloat = 0.5
    static let skirtingHeight: Float = 2.4
    static let skirtingHex: UInt32 = 0x6E625A
    /// Two chairs pulled up to the sides of the table, and a low chest of drawers against
    /// the far wall, as (x, z) in cells with a turn round the vertical axis in radians.
    /// Nothing by the walls is taller than about 1.2 meters: the camera passes over it
    /// when the board turns, and a tall cabinet filled the view.
    static let chairSpots: [(spot: SIMD2<Float>, turn: Float)] = [(SIMD2(-21, 3), 1.45), (SIMD2(21, -4), -1.75)]
    static let cabinetSpot = SIMD2<Float>(-14, -roomHalfDepth + 7.5)
    /// The chairs and the chest are painted white, which glared under the lamp, so they
    /// are darkened.
    static let paintedShade: CGFloat = 0.55
    /// The color behind the scene and under the loading view, a warm brown like the floor
    /// in shadow. The app's own plum looked like a backdrop, not a room.
    static let roomHex: UInt32 = 0x1C120D
    /// A linen runner lies along the middle of the table from far to near, under the
    /// board and the mugs, `runnerLift` thick. It hangs `runnerDrop` cells down over each
    /// end of the table in soft folds up to `runnerFold` deep, and its edges wave a little,
    /// so it reads as cloth. The weave repeats every `runnerGrainCells` cells.
    static let runnerWidth: Float = 11
    static let runnerDrop: Float = 6
    static let runnerFold: Float = 0.3
    static let runnerGrainCells: Float = 6
    static let runnerLift: Float = 0.02
    static let runnerHex: UInt32 = 0xD9C4A8
    /// The models are in meters. At true size next to a 40 centimeter board they crowd
    /// it, so they stand a third smaller, as if the board were a little bigger.
    static let cellsPerMeter: Float = 26
    /// Where the props stand on the table, as (x, z) in cells. Far is negative z. A small
    /// plant stands off the far left corner, a plate of croissants behind the board,
    /// my partner's mug off the far right corner, and my mug in front of the board, near me.
    static let plantPosition = SIMD2<Float>(-6.5, -12)
    static let platePosition = SIMD2<Float>(4.5, -12.5)
    static let partnerMugPosition = SIMD2<Float>(10, -8.5)
    static let myMugPosition = SIMD2<Float>(3, 11)
    /// Two croissants lie side by side on the plate, this far from its middle and this
    /// high above the table, in cells.
    static let croissantSpacing: Float = 1.05
    static let croissantLift: Float = 0.3
    /// A chunky stoneware mug, made in code: its size in cells, how thick its wall and
    /// floor are, and its handle, a half ring on its side.
    static let mugRadius: Float = 1.15
    static let mugHeight: Float = 2.3
    static let mugWall: Float = 0.16
    static let mugFloor: Float = 0.3
    static let mugHandleRadius: Float = 0.6
    static let mugHandleThickness: Float = 0.15
    /// Each of us has a mug in a soft color of our own, glazed like the pieces.
    static let myMugHex: UInt32 = 0xDF7DBC
    static let partnerMugHex: UInt32 = 0x9F8CE0
    /// Hot chocolate in each mug: how far up the inside it comes, and how high it climbs
    /// the wall at its edge. It is darkest in the middle and turns milky toward the
    /// wall, and its surface is wet: almost no roughness, under a full clearcoat.
    static let cocoaLevel: Float = 0.82
    static let cocoaMeniscus: Float = 0.1
    static let cocoaMiddleHex: UInt32 = 0x4F3326
    static let cocoaEdgeHex: UInt32 = 0xB89478
    static let cocoaRoughness: Float = 0.08

    // MARK: Pawn

    /// Chunky pawns, 1.4 times the first version, so they read on a phone.
    static let pawnHeight: Float = 1.29
    static let pawnBaseRadius: Float = 0.49
    static let pawnWaistRadius: Float = 0.18
    static let pawnHeadRadius: Float = 0.42
    /// The flat top that carries the mark.
    static let pawnTopRadius: Float = 0.32
    /// Radial segments of a turned shape. More is rounder and costs more triangles.
    static let turnedSegments = 28
    /// Extra points between the profile points of a pawn and the dome.
    static let profileSamples = 3
    /// The mark disc floats this far above the flat top, to avoid flicker.
    static let markLift: Float = 0.004
    /// Flip this if the initial or the mark shows upside down on the pawn top.
    static let flipsMarkVertically = false
    /// Width of the mark picture in pixels.
    static let markTextureSide = 256
    /// How dark the disc behind the mark is compared with the pawn, 0 to 1.
    static let markBackgroundShade: CGFloat = 0.62
    /// The mark takes this share of the disc width.
    static let markScale: CGFloat = 0.86

    // MARK: Peony on safe squares

    /// Asset name of the peony painted on the six safe squares that are not start squares.
    static let peonyAsset = "LudoPeonyTop"
    /// Width and height of the picture are in this ratio.
    static let peonyAspect: Float = 1.008
    static let peonyWidth: Float = 0.7
    static let peonySquares: [Int] = [8, 13, 21, 34, 39, 47]

    // MARK: Die

    static let dieSize: Float = 1.3
    static let dieCornerRadius: Float = 0.23
    /// A pip is a small heart. Its point faces the viewer on the top face.
    static let pipWidth: Float = 0.27
    static let pipHeight: Float = 0.04
    static let pipRings = 5
    /// Distance of the outer pips from the face center.
    static let pipSpread: Float = 0.33
    /// The die rests in the roller's base yard, beside the two pawn slots. This is
    /// its place in a yard laid out for corner 0, as (row, column) of the board grid.
    static let dieSpotRow: Double = 4.1
    static let dieSpotColumn: Double = 2.5
    /// The two pawn slots of a yard, also for corner 0. They sit in the yard's outer
    /// row, so the die has the rest of the yard.
    static let slotRow: Double = 1.5
    /// The landed die is turned by this angle around the vertical axis, so it looks placed, not aligned.
    static let dieLandingYawRadians: Float = 0.38

    // MARK: Colors (hex RGB)

    /// The glaze of the slab, seen round the edge and in the middle.
    static let slabHex: UInt32 = 0xF4DCE6
    /// Squares nobody owns.
    static let trackTileHex: UInt32 = 0xFFF8FB
    /// The two corners nobody plays: quiet gold and sky blue, calmer than the players' colors.
    static let goldCornerHex: UInt32 = 0xE9CF98
    static let skyCornerHex: UInt32 = 0xA9C6E6
    /// Dice body and pips.
    static let dieHex: UInt32 = 0xFFF8FB
    static let pipHex: UInt32 = 0x4F203A
    /// The mark on a pawn top.
    static let markInkHex: UInt32 = 0xFFFFFF
    /// How much a yard or a home column square mixes in white. 0 is the full color.
    static let yardLightening: CGFloat = 0.10
    static let slotDarkening: CGFloat = 0.12

    // MARK: Material

    /// Roughness and clearcoat by part: a soft satin glaze, not a gloss. The pieces you
    /// touch have a little more sheen than the board.
    /// The slab and its painted top. Rough enough that the lamp leaves no glare on it.
    static let boardRoughness: Float = 0.85
    static let boardClearcoat: Float = 0.03
    static let pawnRoughness: Float = 0.55
    static let pawnClearcoat: Float = 0.15
    static let dieRoughness: Float = 0.55
    static let dieClearcoat: Float = 0.15
    static let pipRoughness: Float = 0.5
    /// A broad, soft sheen from the clearcoat instead of a small sharp highlight.
    static let clearcoatRoughness: Float = 0.4
    static let specular: Float = 0.35
    /// Share of a material's own color it gives off itself. It lifts the shadows from
    /// pure black. Kept low, because the studio picture lights the shaded sides and a
    /// strong self fill makes every surface look flat.
    static let selfFill: CGFloat = 0.02
    /// How strongly a movable pawn or the winner's home glows, and how much white the
    /// glow mixes in. A glow of the pawn's own color barely shows on a lit pawn.
    static let glowIntensity: Float = 0.8
    static let glowLightening: CGFloat = 0.15

    // MARK: Lights and background

    /// The light is a soft golden white, like a lamp in a living room in the evening. A
    /// deep orange looked like an old film. The main light is a wide lamp high over the
    /// far left, so the whole board is lit evenly with no bright pool. It is the only
    /// light that casts shadows, and its size makes them soft.
    static let lampHex: UInt32 = 0xFFC48A
    static let lampLumens: Float = 5_500_000
    static let lampPosition = SIMD3<Float>(-9, 20, -7)
    /// The cone of the lamp's light, and the share of it that is at full strength.
    static let lampConeDegrees: Float = 120
    static let lampFullShare: Float = 0.8
    static let lampReach: Float = 80
    /// How big the lamp is. Bigger makes the shadows softer, and also grainier.
    static let lampSize: Float = 0.7
    /// A warm light from high on the right, so the faces turned from the lamp keep
    /// their color. No shadows.
    static let keyLightHex: UInt32 = 0xFFD6B0
    static let keyLightIntensity: Float = 700
    static let keyLightPosition = SIMD3<Float>(7, 14, 1.5)
    /// A warm fill from the front left, low and soft, so no side of a piece goes dark. No shadows.
    static let fillLightHex: UInt32 = 0xFFD0B0
    static let fillLightIntensity: Float = 900
    static let fillLightPosition = SIMD3<Float>(-8, 9, 7)
    /// A soft peach rim light low and behind on the right. It grazes the right edges of
    /// the pieces and adds little to the flat board.
    static let rimLightHex: UInt32 = 0xFFA08A
    static let rimLightIntensity: Float = 1_500
    static let rimLightPosition = SIMD3<Float>(12, 2.5, -6)
    /// The studio picture that lights the scene (see `LudoBackdrop`). At 0 its brightness
    /// matches the old painted sky. Each step up doubles it. It is turned up a little, so
    /// the shadows stay soft and never go black.
    static let environmentExposure: Float = 0.3
    /// Turn this on if pink lands on the right side of the pieces and lavender on the left.
    static let mirrorsSky = false

    // MARK: Camera

    /// Looking down at the board by this angle from level, and turned this far round it,
    /// as someone seated at the table at the corner by their own base. The lower, turned
    /// view shows the props standing up round the board.
    static let cameraPitchDegrees: Double = 50
    static let cameraYawDegrees: Double = -18
    /// Vertical field of view.
    static let cameraFieldOfViewDegrees: Double = 30
    /// The camera draws from this near distance to this far one. The far distance
    /// reaches past the far corners of the table at the farthest zoom. The depth test's
    /// precision comes from the near distance, so the peonies and the marks that lie a
    /// hair above their surfaces still never flicker through them.
    static let cameraNear: Float = 1
    static let cameraFar: Float = 250
    /// Width divided by height of the board view. A tilted board is wider than tall,
    /// and this is the shape where the width and the height of the view both fit snugly.
    static let viewAspect: Double = 1.4
    /// Space kept free above and below the board, as a share of half the view.
    static let cameraMargin: Double = 0.03
    /// The props the default camera keeps in the space between the rows, as their spot
    /// on the table and their height in cells: the plant to the tips of its leaves, the
    /// croissants and the two mugs. Each reaches `framedPropReach` cells round its spot.
    static var framedProps: [(spot: SIMD2<Float>, height: Float)] {
        [(plantPosition, 7), (platePosition, 2), (partnerMugPosition, mugHeight), (myMugPosition, mugHeight)]
    }
    static let framedPropReach: Float = 1.6
    /// Pinch limits, as a share of the default distance.
    static let zoomRange: ClosedRange<Double> = 0.55...1.35
    /// A two-finger twist turns the board only past this many radians, about 7 degrees,
    /// and then follows the fingers from there.
    static let twistDeadZone: Double = 0.12
    /// At the closest zoom the camera may look this many cells from the middle of the
    /// board each way, enough to center a base yard. The reach shrinks to none at zoom 1.
    static let panReach: Double = 4.5
    /// The double tap glides back to the default view in this time.
    static let cameraResetDuration: Double = 0.5
    /// Pawns and the die rise above the slab by about this much. The camera keeps them in view.
    static let cameraExtraHeight: Double = 1.6

    // MARK: Die throw

    /// A drag that starts on the ready die picks it up this high above where it rests.
    static let dieHoldLift: Float = 1.1
    /// A die that is not in the hand, such as my partner's or one thrown with a tap,
    /// rises into the throw over this time.
    static let tossPickUpTime: Double = 0.15
    /// A die the finger let go flies on with its throw until the roll arrives, then
    /// eases onto the simulated flight over this time.
    static let tossCatchUpTime: Double = 0.1
    /// Speed along the floor in cells a second. A slower flick throws at the smallest speed.
    static let tossMinimumSpeed: Float = 4
    static let tossMaximumSpeed: Float = 9
    /// How fast the die rises as it leaves the hand.
    static let tossRise: Float = 6
    /// Forward roll for each cell a second of speed, in radians a second.
    static let tossRollPerSpeed: Float = 5
    /// How much the spin of each try varies, in radians a second, and how many tries
    /// the simulation makes to land on the rolled number. With these settings a throw
    /// turns about two times and changes its top face about 7 times, and fewer than 1
    /// in 100 throws needs its faces swapped round to show the number.
    static let tossSpinJitter: Float = 12
    static let tossAttempts = 120
    /// A try that is still moving after this many seconds does not count. The die then
    /// eases flat over `tossSetDownTime`. Together they are the longest a throw lasts.
    /// Most throws settle in about 1.4 seconds.
    static let tossSettleLimit: Double = 1.8
    static let tossSetDownTime: Double = 0.1
    /// Stronger than real gravity at this scale, so a throw is over in under two seconds.
    static let tossGravity: Float = 50
    /// How quickly the die slows down, per second, on the floor and in the air. The
    /// floor slows the spin only a little, so the die keeps tumbling after it lands.
    static let tossFloorDrag: Float = 2
    static let tossAirDrag: Float = 0.2
    static let tossFloorSpinDrag: Float = 1.5
    static let tossAirSpinDrag: Float = 0.6
    /// A hit faster than `tossBounceSpeed` bounces back with `tossRestitution` of its speed.
    static let tossBounceSpeed: Float = 1
    static let tossRestitution: Float = 0.45
    static let tossFriction: Float = 0.5
    /// A hit faster than this taps the phone.
    static let tossKnockSpeed: Float = 2
    /// Extra room around a waiting pawn, because the die's sides are flat and the
    /// simulation only feels its rounded corners.
    static let tossPawnClearance: Float = 0.15
    /// The longest throw, with the rise into it. The screen waits this long before the person picks a pawn.
    static let tumbleDuration: Double = tossPickUpTime + tossSettleLimit + tossSetDownTime

    // MARK: Motion

    /// One hop from square to square.
    static let hopDuration: Double = 0.16
    static let hopArc: Float = 0.42
    /// A pawn walking past another steps this far to the side, into the next lane.
    static let detourDistance: Float = 1
    /// Pause between the die landing and the partner's pawn moving.
    static let partnerPause: Double = 0.25
    /// A die changing yards hops over this time.
    static let trayHopDuration: Double = 0.42
    static let trayHopArc: Float = 1.2
    static let dieBobHeight: Float = 0.1
    static let dieBobPeriod: Double = 1.5
    static let dieBobYaw: Float = 0.08
    /// Movable pawns lift by this much and bob.
    static let pawnLift: Float = 0.34
    static let pawnBobHeight: Float = 0.05
    static let pawnBobPeriod: Double = 1.2
    static let shakeDuration: Double = 0.32
    static let shakeDistance: Float = 0.12
    /// A pawn sent home pops up, arcs back to its base and settles.
    static let sendHomeDuration: Double = 0.62
    static let sendHomeArc: Float = 2
    static let homePulseDuration: Double = 0.7
    /// Reduce Motion: a pawn fades out and in over this time instead of hopping.
    static let fadeDuration: Double = 0.24
    /// Other pawns dim to this opacity when the game ends.
    static let dimmedOpacity: Float = 0.4
    /// Seconds from the start of the result to the petal bloom.
    static let bloomDelay: Double = 0.55
    static let outcomeGlowDuration: Double = 0.3

    // MARK: Helpers

    static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

nonisolated extension UIColor {
    /// This color mixed with `other`. `amount` 0 is this color and 1 is `other`.
    func ludoMixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (r2, g2, b2, a2) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let weight = min(max(amount, 0), 1)
        return UIColor(
            red: r1 + (r2 - r1) * weight,
            green: g1 + (g2 - g1) * weight,
            blue: b1 + (b2 - b1) * weight,
            alpha: 1
        )
    }

    func ludoLightened(_ amount: CGFloat) -> UIColor {
        ludoMixed(with: .white, amount: amount)
    }

    func ludoDarkened(_ amount: CGFloat) -> UIColor {
        ludoMixed(with: .black, amount: amount)
    }
}
