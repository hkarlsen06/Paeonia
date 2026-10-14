import Foundation
import Testing
@testable import PaeoniaApp

/// A small seeded generator (SplitMix64), so random games repeat on every run.
struct BoardGameTestRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Plays one random game per seed from the empty board to the end. Checks that
/// every game ends with an outcome inside `maxMoves` moves and that replaying
/// its moves gives the same board. `maxMoves` is the longest game the board
/// allows, which is not `moveLimit` for Connect Four (7 columns, 42 discs).
/// Returns the finished boards for game-specific checks.
@discardableResult
func playRandomGames<Game: BoardGameRules>(
    _ type: Game.Type,
    maxMoves: Int,
    seeds: Range<UInt64> = 0..<50
) -> [Game] {
    var finished: [Game] = []
    for seed in seeds {
        var random = BoardGameTestRandom(seed: seed)
        var board = Game.initial
        var moves: [Int] = []
        while board.outcome == nil {
            let legal = (0..<Game.moveLimit).filter { board.isLegal($0) }
            guard let move = legal.randomElement(using: &random), let after = board.applying(move) else { break }
            board = after
            moves.append(move)
        }
        #expect(board.outcome != nil, "seed \(seed) ran out of legal moves without an outcome")
        #expect(moves.count <= maxMoves, "seed \(seed) played more than \(maxMoves) moves")
        #expect(Game.replay(moves) == board, "seed \(seed) did not replay to the same board")
        #expect(Game.movers(moves)?.count == moves.count, "seed \(seed) lost track of who moved")
        finished.append(board)
    }
    return finished
}

struct BoardGameRulesTests {
    @Test func theOtherPlayerIsTheOpponent() {
        #expect(BoardPlayer.one.other == .two)
        #expect(BoardPlayer.two.other == .one)
    }

    @Test func playersEncodeAsTheNumbersTheServerUses() throws {
        let players = try JSONDecoder().decode([BoardPlayer].self, from: Data("[1,2]".utf8))
        let data = try JSONEncoder().encode([BoardPlayer.two, .one])

        #expect(players == [.one, .two])
        #expect(String(bytes: data, encoding: .utf8) == "[2,1]")
    }

    @Test func replayingNoMovesGivesTheEmptyBoard() {
        #expect(ConnectFourBoard.replay([]) == ConnectFourBoard.initial)
        #expect(DotsAndBoxesBoard.replay([]) == DotsAndBoxesBoard.initial)
        #expect(UltimateTicTacToeBoard.replay([]) == UltimateTicTacToeBoard.initial)
        #expect(ConnectFourBoard.movers([]) == [])
    }

    @Test func replayingAnIllegalSequenceGivesNil() {
        // Seven discs in a six-high column, with nobody winning on the way.
        #expect(ConnectFourBoard.replay([0, 0, 0, 0, 0, 0, 0]) == nil)
        // The same line twice.
        #expect(DotsAndBoxesBoard.replay([3, 3]) == nil)
        // Cell 4 sends player two to board 4, so board 0 is closed to them.
        #expect(UltimateTicTacToeBoard.replay([4, 1]) == nil)
        // A legal start followed by a move off the board.
        #expect(ConnectFourBoard.replay([3, 2, 7]) == nil)
        #expect(ConnectFourBoard.movers([3, 2, 7]) == nil)
    }

    @Test func replayingPastTheEndOfAGameGivesNil() {
        // Player one wins on the seventh disc, so an eighth move is illegal.
        #expect(ConnectFourBoard.replay([0, 0, 1, 1, 2, 2, 3]) != nil)
        #expect(ConnectFourBoard.replay([0, 0, 1, 1, 2, 2, 3, 4]) == nil)
    }

    @Test func isLegalMatchesApplying() {
        let board = ConnectFourBoard.initial

        #expect(board.isLegal(0))
        #expect(!board.isLegal(7))
        #expect(!board.isLegal(-1))
    }

    @Test func moversAlternateWhenEveryMoveHandsOverTheTurn() {
        #expect(ConnectFourBoard.movers([3, 3, 4]) == [.one, .two, .one])
    }

    @Test func moversKeepThePlayerWhoClosedABox() {
        // Player two closes box 0 with line 21 and draws line 22 right after.
        // Line 22 closes nothing, so player one is next.
        let moves = [0, 4, 20, 21, 22, 1]

        #expect(DotsAndBoxesBoard.movers(moves) == [.one, .two, .one, .two, .two, .one])
    }

    @Test func moversAreNilForAnIllegalSequence() {
        #expect(DotsAndBoxesBoard.movers([0, 0]) == nil)
    }
}
