import Testing
@testable import PaeoniaApp

/// Fixture games shared with `backend/convex/lib/ludo.test.ts`. The moves, progress, next and winner match that
/// file. Progress is [player 1 pawn 0, player 1 pawn 1, player 2 pawn 0, player 2 pawn 1].
struct LudoFixture {
    let name: String
    let moves: [Int]
    let progress: [Int]
    let next: BoardPlayer
    let winner: BoardPlayer?

    static func named(_ name: String) throws -> LudoFixture {
        try #require(all.first { $0.name == name })
    }

    static let all: [LudoFixture] = [
        LudoFixture(name: "exitAndWalk", moves: [15, 12, 5], progress: [6, 0, 0, 0], next: .one, winner: nil),
        LudoFixture(
            name: "capture",
            moves: [15, 15, 15, 15, 15, 6, 15, 3, 0],
            progress: [29, 0, 0, 0],
            next: .one,
            winner: nil
        ),
        LudoFixture(
            name: "safeSquare",
            moves: [15, 15, 15, 15, 15, 0, 15, 16, 3, 0],
            progress: [27, 0, 3, 1],
            next: .two,
            winner: nil
        ),
        LudoFixture(
            name: "playerOneWins",
            moves: [
            15, 3, 11, 3, 11, 6, 14, 6, 5, 3, 14, 12, 15, 3, 12, 6, 3, 0, 12, 16, 9, 6,
            0, 0, 16, 4, 9, 15, 0, 13, 9, 13, 12, 16, 4, 6, 5, 13, 2, 13, 14, 10, 14, 15,
            7, 16, 16, 4, 1, 16, 1, 6, 10, 9, 7, 10, 13, 14, 9, 5, 1, 16, 7, 12, 4, 15,
            0, 1, 15, 12, 1, 0, 16, 7, 15, 6, 1, 3, 7, 10, 4, 8, 10, 14, 13, 15, 9, 13,
            9, 13, 6, 10, 0, 13, 12, 4, 0, 17, 4
            ],
            progress: [57, 57, 19, 57],
            next: .one,
            winner: .one
        ),
        LudoFixture(
            name: "playerTwoWins",
            moves: [
            11, 16, 1, 2, 10, 8, 7, 16, 7, 16, 1, 10, 13, 4, 10, 4, 4, 1, 13, 4, 10, 7,
            10, 10, 16, 7, 7, 4, 10, 16, 10, 11, 16, 13, 1, 4, 5, 7, 8, 15, 10, 14, 12, 8,
            7, 5, 0, 5, 6, 15, 6, 9, 9, 16, 1, 11, 9, 8, 15, 4, 15, 9, 9, 15, 9, 3,
            3, 3, 12, 16, 16, 0, 3, 7, 12, 12, 15, 15, 12, 4, 9, 1, 3, 4, 3, 7, 17, 6,
            11, 12, 14, 4, 14, 10, 8, 13, 8, 13, 1
            ],
            progress: [43, 34, 57, 57],
            next: .two,
            winner: .two
        )
    ]
}
