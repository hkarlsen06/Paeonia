import UIKit
import simd

/// Every number that shapes the look and the motion of the Ludo scene, in one
/// place. The art director tunes this file. Lengths are in world units, and one
/// board cell is 1.0. Angles are in degrees unless the name says radians.
nonisolated enum LudoSceneStyle {
    // MARK: Board

    /// Edge of a tile. Less than 1.0, so a thin gap shows between tiles.
    static let tileSize: Float = 0.92
    /// How far a tile rises above the slab.
    static let tileHeight: Float = 0.18
    /// Rounded like a pillow. RealityKit caps the radius at half the height.
    static let tileCornerRadius: Float = 0.18
    /// The slab ends just past the 15 by 15 cells: a thin rounded lip, no border.
    static let slabMargin: Float = 0.25
    static let slabThickness: Float = 0.7
    static let slabCornerRadius: Float = 0.6
    /// The base yards. A yard is a raised pad a little smaller than its 6 by 6 cells,
    /// so a rim of the slab shows around it and its rounded edge catches the light.
    static let yardSize: Float = 5.6
    static let yardHeight: Float = 0.24
    static let yardCornerRadius: Float = 0.6
    /// The round dent where one pawn waits in its base.
    static let yardSlotRadius: Float = 0.6
    static let yardSlotHeight: Float = 0.03
    /// The center is a low round dome in two halves, mine and my partner's.
    static let domeDiameter: Float = 2.8
    static let domeHeight: Float = 0.26
    /// Height of the dome where the pawns at home stand.
    static let homePadHeight: Float = 0.2
    /// How deep a pawn at home sinks into the dome.
    static let homeSink: Float = 0.3
    /// Pawns that share a square stand this far apart, and shrink to `sharedPawnScale`.
    static let sharedPawnSpacing: Float = 0.5
    static let sharedPawnScale: Float = 0.66
    /// Pawns at home are a little smaller.
    static let homePawnScale: Float = 0.7
    /// The sideways distance between two pawns at home.
    static let homeLaneSpacing: Double = 0.45
    /// How far from the center point a player's home pawns stand, along their column.
    static let homeDistance: Double = 0.78

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

    /// Asset name of the peony picture laid flat on the six safe squares that are not start squares.
    static let peonyAsset = "LudoPeonyTop"
    /// Width and height of the picture are in this ratio.
    static let peonyAspect: Float = 1.008
    static let peonyWidth: Float = 0.7
    static let peonyLift: Float = 0.004
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

    /// The slab under the tiles.
    static let slabHex: UInt32 = 0xF4DCE6
    /// Tiles nobody owns.
    static let trackTileHex: UInt32 = 0xFFF8FB
    /// The two corners nobody plays: quiet gold and sky blue, calmer than the players' colors.
    static let goldCornerHex: UInt32 = 0xE9CF98
    static let skyCornerHex: UInt32 = 0xA9C6E6
    /// Dice body and pips.
    static let dieHex: UInt32 = 0xFFF8FB
    static let pipHex: UInt32 = 0x4F203A
    /// The mark on a pawn top.
    static let markInkHex: UInt32 = 0xFFFFFF
    /// How much a yard plate or a home column tile mixes in white. 0 is the full color.
    static let yardLightening: CGFloat = 0.10
    static let columnLightening: CGFloat = 0.10
    static let slotDarkening: CGFloat = 0.12

    // MARK: Material

    /// Roughness and clearcoat by part. The pieces you touch are glossier than the board.
    static let slabRoughness: Float = 0.6
    static let slabClearcoat: Float = 0.1
    /// Tiles, bases and home columns.
    static let boardRoughness: Float = 0.45
    static let boardClearcoat: Float = 0.2
    static let domeRoughness: Float = 0.3
    static let domeClearcoat: Float = 0.6
    static let pawnRoughness: Float = 0.24
    static let pawnClearcoat: Float = 0.9
    static let dieRoughness: Float = 0.26
    static let dieClearcoat: Float = 0.9
    static let pipRoughness: Float = 0.5
    static let decalRoughness: Float = 0.6
    static let clearcoatRoughness: Float = 0.12
    static let specular: Float = 0.5
    /// Share of a material's own color it gives off itself. It lifts the shadows from pure black.
    static let selfFill: CGFloat = 0.06
    /// How strongly a movable pawn or the winner's home glows, and how much white the
    /// glow mixes in. A glow of the pawn's own color barely shows on a lit pawn.
    static let glowIntensity: Float = 0.8
    static let glowLightening: CGFloat = 0.15

    // MARK: Lights and background

    /// Key light from high on the right, a little in front. The tops are lit and the
    /// fronts of the tiles fall into soft shade, so every tile reads as a raised piece.
    static let keyLightHex: UInt32 = 0xFFF0E4
    static let keyLightIntensity: Float = 2_800
    static let keyLightPosition = SIMD3<Float>(7, 14, 1.5)
    /// Pink rim light low and behind on the right. It is low so it grazes the right
    /// edges of the pieces and adds little to the flat board.
    static let rimLightHex: UInt32 = 0xF27EB2
    static let rimLightIntensity: Float = 6_000
    static let rimLightPosition = SIMD3<Float>(12, 2.5, -6)
    static let shadowDistance: Float = 30
    static let shadowDepthBias: Float = 1
    /// The background is an equirectangular picture, so it also lights the scene softly.
    /// The sky carries the two worlds of the hub series: pink on the left of the
    /// horizon, lavender on the right, and a soft zenith above.
    static let skyLeftHex: UInt32 = 0xE88DBA
    static let skyRightHex: UInt32 = 0xA992E6
    static let skyZenithHex: UInt32 = 0xF6DCEA
    /// Turn this on if pink lands on the right side of the pieces and lavender on the left.
    static let mirrorsSky = false
    /// Matches `Color.paeoniaBackgroundSecondary`, so the scene blends into the screen.
    static let groundHex: UInt32 = 0x2A0B1E

    // MARK: Camera

    /// Looking down at the board by this angle from level.
    static let cameraPitchDegrees: Double = 64
    /// Vertical field of view.
    static let cameraFieldOfViewDegrees: Double = 30
    /// Width divided by height of the board view. A tilted board is wider than tall,
    /// and this is the shape where the width and the height of the view both fit snugly.
    static let viewAspect: Double = 1.4
    /// Space kept free above and below the board, as a share of half the view.
    static let cameraMargin: Double = 0.03
    /// How far past the left and right edges of the view the near edge of the board
    /// may run, as a share of half the view. The board fills the screen sideways.
    static let cameraOvershoot: Double = 0.3
    /// The orbit keeps the camera between these angles above the board.
    static let orbitPitchRangeDegrees: ClosedRange<Double> = 35...80
    /// Pinch limits, as a share of the default distance.
    static let zoomRange: ClosedRange<Double> = 0.55...1.35
    /// Radians of yaw and pitch for each point of a one-finger drag.
    static let orbitYawPerPoint: Double = 0.008
    static let orbitPitchPerPoint: Double = 0.006
    /// How quickly the orbit slows down after the finger lifts, per second.
    static let orbitFriction: Double = 3.5
    /// The double tap glides back to the default view in this time.
    static let cameraResetDuration: Double = 0.5
    /// Pawns and the die rise above the slab by about this much. The camera keeps them in view.
    static let cameraExtraHeight: Double = 1.6

    // MARK: Motion

    /// One hop from square to square.
    static let hopDuration: Double = 0.16
    static let hopArc: Float = 0.42
    /// Time the die tumbles. The screen waits the same time before the partner's pawn moves.
    static let tumbleDuration: Double = 0.8
    /// Pause between the die landing and the partner's pawn moving.
    static let partnerPause: Double = 0.25
    /// Full turns the die spins while it tumbles. Keep it a whole number, so the tumble starts without a jump.
    static let tumbleTurns: Double = 2
    static let tumbleAxis = SIMD3<Float>(1, 0.35, 0.6)
    /// Bounces of the tumble as a share of its time, and how high each one goes.
    static let bounceShares: [Double] = [0.42, 0.33, 0.25]
    static let bouncePeaks: [Float] = [1.7, 0.7, 0.2]
    /// The die drifts sideways while it tumbles.
    static let tumbleDriftX: Float = 1.1
    static let tumbleDriftZ: Float = 0.7
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
