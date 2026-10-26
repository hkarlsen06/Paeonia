import Foundation

/// What I have picked on my turn, on its way to my partner's board, so they
/// see where I am about to play before I lock it in. "Lock in" still sends the
/// move through Convex, which stays the record. Nothing in this message is saved.
nonisolated struct UltimateTicTacToeLiveMessage: GameLiveMessage, Equatable {
    static let game = "ultimate_tic_tac_toe"

    /// The position the pick was made on: the game and how many moves it had.
    let gameNumber: Int
    let moveCount: Int
    let pick: UltimateTicTacToePick

    /// The pick as the receiving board may show it. Nothing unless the board
    /// on screen is the position the pick was made on and still allows it.
    func pick(on board: UltimateTicTacToeBoard, gameNumber: Int, moveCount: Int) -> UltimateTicTacToePick {
        guard gameNumber == self.gameNumber, moveCount == self.moveCount else { return .none }
        switch pick {
        case .none:
            return .none
        case .board(let index):
            return board.forced == nil && board.openBoards.contains(index) ? pick : .none
        case .move(let move):
            return board.isLegal(move) ? pick : .none
        }
    }
}

/// Joins one Ultimate Tic-Tac-Toe screen to its relay room while the screen is
/// open. My picks go out as I make them, and again when my partner arrives.
/// My partner's picks go to `onPartnerPick`.
@MainActor
final class UltimateTicTacToeLiveLink {
    private let room: WidgetLiveDrawing
    private let channel: GameLiveChannel<UltimateTicTacToeLiveMessage>
    private var lastSent: UltimateTicTacToeLiveMessage?

    init(room: WidgetLiveDrawing, onPartnerPick: @escaping (UltimateTicTacToeLiveMessage) -> Void) {
        self.room = room
        channel = GameLiveChannel(connection: room.connection)
        channel.onMessage = onPartnerPick
        room.onPartnerArrived = { [weak self] in
            guard let self, let lastSent else { return }
            channel.send(lastSent)
        }
        room.start()
    }

    /// False once my partner has left the game, so a pick they never locked
    /// in stops showing.
    var isPartnerHere: Bool {
        room.partnerActivity != .away
    }

    func send(_ message: UltimateTicTacToeLiveMessage) {
        guard message != lastSent else { return }
        lastSent = message
        channel.send(message)
    }

    func stop() {
        room.onPartnerArrived = nil
        room.stop()
    }
}
