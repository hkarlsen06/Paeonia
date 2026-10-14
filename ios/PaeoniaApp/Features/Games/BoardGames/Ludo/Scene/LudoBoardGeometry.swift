import CoreGraphics
import Foundation
import simd

/// A point on the 15 by 15 board grid. The center of cell (row, column) is the
/// point (row, column), so a point can sit between cells. Row 0 is the far edge
/// and row 14 is the edge nearest the viewer.
nonisolated struct LudoGridPoint: Equatable, Sendable {
    var row: Double
    var column: Double

    /// Distance in cells.
    func distance(to other: LudoGridPoint) -> Double {
        ((row - other.row) * (row - other.row) + (column - other.column) * (column - other.column)).squareRoot()
    }
}

/// Where one pawn stands and how big it is.
nonisolated struct LudoPlacement: Equatable, Sendable {
    let square: LudoSquare
    let point: LudoGridPoint
    let scale: Double
}

/// Maps every `LudoSquare` to a place on the board grid. Pure, so it is testable.
///
/// The board is worked out first in a fixed frame: player one's base is in the
/// top left corner and pawns walk clockwise. Corner 0 is the top left, 1 the top
/// right, 2 the bottom right and 3 the bottom left. Player one owns corner 0 and
/// player two owns corner 2, opposite. Start squares are 13 apart, so the track
/// square 13 * corner is the start of that corner.
///
/// Then the whole board turns so that `viewer`'s corner is the bottom left, which
/// is nearest the viewer on the left.
nonisolated enum LudoBoardGeometry {
    static let cells = 15
    static let middle = 7.0
    /// The track squares of the top left quarter in walking order. The other three
    /// quarters are this quarter turned. A step from the end of an arm to the top
    /// of the next, such as (6, 5) to (5, 6), is diagonal, as on a real board.
    private static let firstQuarter: [(row: Int, column: Int)] = [
        (6, 1), (6, 2), (6, 3), (6, 4), (6, 5),
        (5, 6), (4, 6), (3, 6), (2, 6), (1, 6), (0, 6),
        (0, 7), (0, 8)
    ]
    static let squaresPerQuarter = firstQuarter.count

    // MARK: Corners

    /// The corner that holds this player's base, in the fixed frame.
    static func corner(of player: BoardPlayer) -> Int {
        player == .one ? 0 : 2
    }

    /// Quarter turns clockwise that put the viewer's corner at the bottom left (corner 3).
    static func viewerTurns(_ viewer: BoardPlayer) -> Int {
        (3 - corner(of: viewer) + 4) % 4
    }

    /// Where a fixed-frame corner ends up on screen after the board turns for `viewer`.
    static func screenCorner(ofCorner corner: Int, viewer: BoardPlayer) -> Int {
        (corner + viewerTurns(viewer)) % 4
    }

    /// One quarter turn clockwise per step, around the middle of the board.
    static func rotated(_ point: LudoGridPoint, turns: Int) -> LudoGridPoint {
        var result = point
        for _ in 0..<(((turns % 4) + 4) % 4) {
            result = LudoGridPoint(row: result.column, column: Double(cells - 1) - result.row)
        }
        return result
    }

    // MARK: Squares

    /// The point of a track square in the fixed frame.
    static func fixedTrackPoint(_ index: Int) -> LudoGridPoint {
        let wrapped = ((index % LudoBoard.trackLength) + LudoBoard.trackLength) % LudoBoard.trackLength
        let cell = firstQuarter[wrapped % squaresPerQuarter]
        let point = LudoGridPoint(row: Double(cell.row), column: Double(cell.column))
        return rotated(point, turns: wrapped / squaresPerQuarter)
    }

    // MARK: Corner pieces

    /// The center of a corner's base yard in the fixed frame, turned for `viewer`.
    static func yardCenter(corner: Int, viewer: BoardPlayer) -> LudoGridPoint {
        turned(LudoGridPoint(row: 2.5, column: 2.5), corner: corner, viewer: viewer)
    }

    /// One of the two places in a corner's yard.
    static func slotPoint(corner: Int, slot: Int, viewer: BoardPlayer) -> LudoGridPoint {
        turned(
            LudoGridPoint(row: LudoSceneStyle.slotRow, column: 1.5 + 2 * Double(slot)),
            corner: corner,
            viewer: viewer
        )
    }

    /// Where the die rests in a corner's yard, in the free space beside the two pawn slots.
    static func dieSpot(corner: Int, viewer: BoardPlayer) -> LudoGridPoint {
        turned(
            LudoGridPoint(row: LudoSceneStyle.dieSpotRow, column: LudoSceneStyle.dieSpotColumn),
            corner: corner,
            viewer: viewer
        )
    }

    /// A square of a corner's home column, step 1 to 5.
    static func columnPoint(corner: Int, step: Int, viewer: BoardPlayer) -> LudoGridPoint {
        turned(LudoGridPoint(row: middle, column: Double(step)), corner: corner, viewer: viewer)
    }

    /// Where a corner's pawns stand at home, on its half of the center dome. `lane`
    /// shifts it sideways by a pawn's place: -1, 0 or 1 pawn lanes.
    static func padPoint(corner: Int, lane: Double = 0, viewer: BoardPlayer) -> LudoGridPoint {
        let point = LudoGridPoint(
            row: middle + lane * LudoSceneStyle.homeLaneSpacing,
            column: middle - LudoSceneStyle.homeDistance
        )
        return turned(point, corner: corner, viewer: viewer)
    }

    private static func turned(_ point: LudoGridPoint, corner: Int, viewer: BoardPlayer) -> LudoGridPoint {
        rotated(point, turns: corner + viewerTurns(viewer))
    }

    /// Where a square is, for this viewer. `homeLane` tells two pawns at home
    /// apart: it is the pawn's number, 0 or 1.
    static func point(of square: LudoSquare, homeLane: Int = 0, viewer: BoardPlayer) -> LudoGridPoint {
        switch square {
        case let .base(player, slot):
            slotPoint(corner: corner(of: player), slot: slot, viewer: viewer)
        case let .homeColumn(player, step):
            columnPoint(corner: corner(of: player), step: step, viewer: viewer)
        case let .home(player):
            padPoint(corner: corner(of: player), lane: homeLane == 0 ? -1 : 1, viewer: viewer)
        case let .track(index):
            rotated(fixedTrackPoint(index), turns: viewerTurns(viewer))
        }
    }

    /// Where every pawn stands on `board`. Pawns on one shared square stand side by side.
    static func placements(board: LudoBoard, viewer: BoardPlayer) -> [LudoPlacement] {
        let squares = (0..<(LudoBoard.pawnsPerPlayer * 2)).map { board.square(ofPawn: $0) }
        return squares.indices.map { index in
            let square = squares[index]
            var point = Self.point(of: square, homeLane: index % LudoBoard.pawnsPerPlayer, viewer: viewer)
            var scale = 1.0
            switch square {
            case .base:
                break
            case .home:
                scale = Double(LudoSceneStyle.homePawnScale)
            case .track, .homeColumn:
                let sharing = squares.indices.filter { squares[$0] == square }
                if sharing.count > 1 {
                    let rank = sharing.firstIndex(of: index) ?? 0
                    let offset = Double(rank) - Double(sharing.count - 1) / 2
                    point.column += offset * Double(LudoSceneStyle.sharedPawnSpacing)
                    scale = Double(LudoSceneStyle.sharedPawnScale)
                }
            }
            return LudoPlacement(square: square, point: point, scale: scale)
        }
    }

    // MARK: Colors by corner

    /// The kinds of corner color on screen: mine at the bottom left, the partner's at the top right.
    nonisolated enum CornerRole: Equatable, Sendable {
        case mine
        case partner
        case gold
        case sky
    }

    /// Which color a fixed-frame corner gets for this viewer. The two unused
    /// corners keep their place on screen: gold at the top left, sky blue at the bottom right.
    static func role(ofCorner corner: Int, viewer: BoardPlayer) -> CornerRole {
        switch screenCorner(ofCorner: corner, viewer: viewer) {
        case 3: .mine
        case 1: .partner
        case 0: .gold
        default: .sky
        }
    }
}

/// Maps board grid points to the 3D scene. The board lies in the x and z plane
/// with its top surface at height 0, row 14 toward the viewer (+z) and column 14
/// on the right (+x). One cell is one unit.
nonisolated enum LudoWorld {
    /// Half the width of the 15 cells.
    static let halfBoard: Float = Float(LudoBoardGeometry.cells) / 2
    /// Half the width of the whole slab.
    static var halfSlab: Float { halfBoard + LudoSceneStyle.slabMargin }

    static func position(_ point: LudoGridPoint, height: Float = 0) -> SIMD3<Float> {
        SIMD3(Float(point.column - LudoBoardGeometry.middle), height, Float(point.row - LudoBoardGeometry.middle))
    }

    /// How high a pawn's feet are on a kind of square.
    static func standingHeight(on square: LudoSquare) -> Float {
        switch square {
        case .base: LudoSceneStyle.yardHeight + LudoSceneStyle.yardSlotHeight
        case .track, .homeColumn: LudoSceneStyle.tileHeight
        case .home: LudoSceneStyle.homePadHeight - LudoSceneStyle.homeSink
        }
    }

    static func position(of placement: LudoPlacement) -> SIMD3<Float> {
        position(placement.point, height: standingHeight(on: placement.square))
    }

    /// The yard the die rests in on screen: my base at the bottom left (near) or my
    /// partner's at the top right (far). The screen always looks the same, so one viewer stands for both.
    static func rollerCorner(isNear: Bool) -> Int {
        LudoBoardGeometry.corner(of: isNear ? .one : .two)
    }

    /// Where the middle of a resting die is, in the roller's base yard.
    static func dieRestPosition(isNear: Bool) -> SIMD3<Float> {
        let point = LudoBoardGeometry.dieSpot(corner: rollerCorner(isNear: isNear), viewer: .one)
        return position(point, height: LudoSceneStyle.yardHeight + LudoSceneStyle.dieSize / 2)
    }
}
