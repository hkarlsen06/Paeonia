import Foundation

// What each queued Games write carries. The payloads fix every id and operation
// up front, so a retry after a lost response replays the same requests.

/// `drawAndGuess:pick_draw_word`. The round id is chosen on this phone, so the drawing
/// queued after it can name the round before the server has seen it.
nonisolated struct GamePickWordPayload: Codable, Equatable, Sendable {
    let gameID: UUID
    let roundID: UUID
    let choice: DrawAndGuessDifficulty
    /// The word as the drawer picked it. The server lowercases a custom word.
    let word: String
    /// The offered choice's id. Nil for a custom word.
    let wordID: String?
    let points: Int
    let createdAt: Date
}

/// Sends a finished drawing. The bytes are the drawing at the canonical canvas
/// size (`GameCanvas.canonicalSide`).
nonisolated struct GameSubmitDrawingPayload: Codable, Equatable, Sendable {
    let gameID: UUID
    let roundID: UUID
    let coupleID: UUID
    let drawingData: Data
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation
    /// When the drawing was queued again because its first upload was gone.
    var renewedAt: Date?
}

nonisolated struct GameGuessPayload: Codable, Equatable, Sendable {
    /// Names the guess on this phone until the server's copy replaces it.
    let id: UUID
    let roundID: UUID
    /// The guess in capitals as typed with the tiles. The server lowercases it.
    let guess: String
    /// Whether the guess matched the answer on this phone.
    let isCorrect: Bool
    let createdAt: Date
    /// The speed bonus tier (0, 1 or 2) on screen when the player made the
    /// correct guess, on this phone's clock. The server takes it as it is, so a
    /// guess that waits offline keeps what the player saw. Nil for a wrong guess.
    var speedBonus: Int?
    /// Milliseconds from when the player first saw the drawing to the correct
    /// guess, on this phone's clock. Nil when the player never saw it.
    var solveMs: Int?
    /// How many letters the player's hints showed before the correct guess. Nil
    /// for a wrong guess.
    var hintsUsed: Int?
}

nonisolated struct GameGiveUpPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// `drawAndGuess:set_round_star`. The last one queued for a round wins, and sending
/// the same one twice changes nothing.
nonisolated struct GameStarPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let starred: Bool
    let createdAt: Date
}

/// The guesser's reaction to a finished round. Nil clears it. The last one made
/// is the one the screen shows.
nonisolated struct GameReactionPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let reaction: DrawAndGuessReaction?
    let createdAt: Date
}

/// This person moved past the result of a finished round.
nonisolated struct GameResultSeenPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// The queued Games writes of one person that have not reached the server, as
/// the screens need them. A write refused for good is no longer in flight, so it
/// drops out of this value and the screen falls back to the server's state.
nonisolated struct DrawAndGuessPendingWork: Equatable, Sendable {
    /// The newest word pick that is still waiting.
    var pick: GamePickWordPayload?
    var drawings: [GameSubmitDrawingPayload] = []
    /// Oldest first.
    var guesses: [GameGuessPayload] = []
    var giveUps: [GameGiveUpPayload] = []
    /// Oldest first.
    var reactions: [GameReactionPayload] = []
    var resultsSeen: [GameResultSeenPayload] = []
    /// A waiting move was tried again and the attempt failed for a reason other
    /// than having no connection, such as the server refusing it. The waiting
    /// screen then says so instead of "saved on this phone".
    var lastSendFailedWhileOnline = false
    /// A waiting move has had a try that did not get through, for any reason.
    /// Until then the move is on its first send, and the screen says nothing
    /// about it being on this phone, so a normal send never flashes that line.
    var hasFailedMoveAttempt = false

    static let none = DrawAndGuessPendingWork()

    var isEmpty: Bool {
        pick == nil && drawings.isEmpty && guesses.isEmpty && giveUps.isEmpty && reactions.isEmpty
            && resultsSeen.isEmpty
    }

    func hasDrawing(roundID: UUID) -> Bool {
        drawings.contains { $0.roundID == roundID }
    }

    func guesses(roundID: UUID) -> [GameGuessPayload] {
        guesses.filter { $0.roundID == roundID }
    }

    func hasGiveUp(roundID: UUID) -> Bool {
        giveUps.contains { $0.roundID == roundID }
    }

    /// The reaction this person made last for the round and has not sent yet.
    /// The outer nil means none is waiting. The inner nil is a cleared reaction.
    func reaction(roundID: UUID) -> DrawAndGuessReaction?? {
        reactions.last { $0.roundID == roundID }.map(\.reaction)
    }

    func hasResultSeen(roundID: UUID) -> Bool {
        resultsSeen.contains { $0.roundID == roundID }
    }

    /// A move of the turn (not a reaction or a seen mark) waits to be sent.
    var hasMoveWaiting: Bool {
        pick != nil || !drawings.isEmpty || !guesses.isEmpty || !giveUps.isEmpty
    }

    /// Reads the queue. Payloads that fail to decode are skipped.
    static func load(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> DrawAndGuessPendingWork? {
        var work = DrawAndGuessPendingWork()
        let decoder = JSONDecoder()
        /// The payloads of one kind that are still in flight, oldest first.
        func read<Payload: Decodable>(
            _ kind: SyncPendingOperationKind,
            isMove: Bool = true
        ) async throws -> [Payload] {
            let operations = try await store.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
            if isMove, operations.contains(where: \.failedWhileOnline) {
                work.lastSendFailedWhileOnline = true
            }
            if isMove, operations.contains(where: \.hasFailedAttempt) {
                work.hasFailedMoveAttempt = true
            }
            return operations.compactMap { operation in
                operation.requestData.flatMap { try? decoder.decode(Payload.self, from: $0) }
            }
        }
        do {
            work.pick = try await read(.pickDrawWord).last
            work.drawings = try await read(.submitGameDrawing)
            work.guesses = try await read(.submitGameGuess)
            work.giveUps = try await read(.giveUpGameRound)
            work.reactions = try await read(.setGameRoundReaction, isMove: false)
            work.resultsSeen = try await read(.markGameRoundResultSeen, isMove: false)
        } catch {
            // A failed read keeps the screen as it is. Treating it as an empty
            // queue would make a queued move look lost.
            return nil
        }
        return work
    }
}

extension PendingSyncOperationSnapshot {
    /// The last attempt reached the server or the sign-in and failed there. A
    /// move that waits behind an earlier one and a lost connection do not count.
    /// The drain keeps `String(describing:)` of the error in `lastError`.
    nonisolated var failedWhileOnline: Bool {
        guard let lastError else { return false }
        return lastError != "Retry later" && !lastError.contains("NSURLErrorDomain")
    }
}
