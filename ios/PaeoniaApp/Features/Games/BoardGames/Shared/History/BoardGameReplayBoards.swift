import SwiftUI

/// The same read-only boards in past games and in a game's conversation.
enum BoardGameReplayBoards {
    static func connectFour(_ replay: BoardGameReplayBoard<ConnectFourBoard>) -> some View {
        ConnectFourBoardView(
            board: replay.board, lastMove: replay.lastMove, styles: replay.styles, me: replay.me,
            canPlay: false, showsOutcome: replay.showsOutcome, bloomSeed: replay.bloomSeed, onPlay: { _ in },
            playsOutcomeHaptics: false
        )
    }

    static func dotsAndBoxes(_ replay: BoardGameReplayBoard<DotsAndBoxesBoard>) -> some View {
        DotsAndBoxesBoardView(
            board: replay.board, lastMove: replay.lastMove, styles: replay.styles, me: replay.me,
            canPlay: false, showsOutcome: replay.showsOutcome, bloomSeed: replay.bloomSeed, photo: nil,
            partnerName: replay.partnerName, onPlay: { _ in }
        )
    }

    static func ludo(_ replay: BoardGameReplayBoard<LudoBoard>) -> some View {
        LudoBoardView(
            board: replay.board, lastMove: nil, styles: replay.styles, me: replay.me,
            die: .idle(side: replay.me), movableChoices: [], showsOutcome: replay.showsOutcome,
            bloomSeed: replay.bloomSeed,
            partnerName: replay.partnerName, onRoll: { _ in }, onChoose: { _ in }
        )
        .frame(height: 340)
    }
}
