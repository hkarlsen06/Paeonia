import Foundation
import Testing
@testable import PaeoniaApp

/// What the camera does with Reduce Motion on.
@MainActor
struct UltimateTicTacToePlaybackTests {
    private func input(
        _ board: UltimateTicTacToeBoard,
        lastMove: BoardMoveEvent?,
        canPlay: Bool
    ) -> UltimateTicTacToePlayback.Input {
        UltimateTicTacToePlayback.Input(
            board: board,
            lastMove: lastMove,
            canPlay: canPlay,
            showsOutcome: false,
            zoomEnabled: true,
            reduceMotion: true
        )
    }

    @Test func withReduceMotionAPartnersMoveCutsStraightToTheBoardIMustPlayIn() throws {
        let start = UltimateTicTacToeBoard.initial
        let playback = UltimateTicTacToePlayback(input(start, lastMove: nil, canPlay: false))
        playback.update(input(start, lastMove: nil, canPlay: false))
        #expect(playback.focus == nil)

        // Player one opened in the middle, so I must play in board 4.
        let forced = try #require(UltimateTicTacToeBoard.replay([40]))
        let move = BoardMoveEvent(number: 1, move: 40, player: .one, isMine: false)
        playback.update(input(forced, lastMove: move, canPlay: true))

        #expect(playback.isBusy == false)
        #expect(playback.hold == .none)
        #expect(playback.focus == 4)
    }
}
