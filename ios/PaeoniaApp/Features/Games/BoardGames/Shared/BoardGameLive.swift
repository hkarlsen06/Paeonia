import Foundation

/// My move on its way to my partner's board through the game's relay room, so
/// it shows there as soon as I make it. It is the move this phone saved for the
/// sync, sent once the save worked. Convex stays the record. The partner's
/// board puts the move on top of the server's game (`BoardGameResolver`) until
/// the server's game has it, and drops it after `BoardGameViewModel.partnerMoveLifetime`
/// if the server never takes it.
nonisolated struct BoardGameLiveMove: GameLiveMessage, Equatable {
    static let game = "board_game_move"

    let move: BoardGameMovePayload
}

// The game's relay room: it runs while the screen does, sends this phone's moves
// and takes the partner's.
extension BoardGameViewModel {
    /// How long a partner's live move shows without the server's game taking
    /// it. After that the board goes back to the server's game, so a move the
    /// server refused, or one stuck on the partner's phone, never freezes it.
    static var partnerMoveLifetime: Duration { .seconds(15) }

    /// Opens the room for the couple while the screen runs, and closes it when
    /// the screen stops or the couple changes.
    func updateLiveRoom() {
        let coupleID = isRunning ? participants.coupleID : nil
        guard coupleID != liveRoomCoupleID else { return }
        stopLiveRoom()
        guard let coupleID, let room = dependencies.makeBoardGameLive(kind, coupleID) else { return }
        let channel = GameLiveChannel<BoardGameLiveMove>(connection: room.connection)
        channel.onMessage = { [weak self] message in
            self?.receivePartnerMove(message.move)
        }
        room.start()
        liveRoomCoupleID = coupleID
        moveChannel = channel
        liveRoom = room
    }

    func stopLiveRoom() {
        liveRoom?.stop()
        liveRoom = nil
        moveChannel = nil
        liveRoomCoupleID = nil
    }

    /// The partner's move came through the room. It shows at once, the same way
    /// as when the server's game brings it.
    private func receivePartnerMove(_ move: BoardGameMovePayload) {
        guard move.kind == kind else { return }
        partnerMoves.append(move)
        partnerMovesExpiry?.cancel()
        let sleep = sleep
        partnerMovesExpiry = Task { [weak self] in
            try? await sleep(Self.partnerMoveLifetime)
            guard !Task.isCancelled, let self else { return }
            partnerMoves = []
            partnerMovesExpiry = nil
            recompute()
        }
        recompute()
    }

    func clearPartnerMoves() {
        partnerMovesExpiry?.cancel()
        partnerMovesExpiry = nil
        partnerMoves = []
    }
}
