import Foundation

// What each queued Games write carries. The payloads fix every id and operation
// up front, so a retry after a lost response replays the same requests.

/// `games:pick_draw_word`. The round id is chosen on this phone, so the drawing
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
/// size (`DrawAndGuessCanvas.canonicalSide`).
nonisolated struct GameSubmitDrawingPayload: Codable, Equatable, Sendable {
    let gameID: UUID
    let roundID: UUID
    let coupleID: UUID
    let drawingData: Data
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation
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
}

nonisolated struct GameGiveUpPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// Saves a finished round to Memories. The image is the rendered drawing.
nonisolated struct GameSaveRoundPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let coupleID: UUID
    let memoryID: UUID
    let memoryMediaID: UUID
    let imageData: Data
    /// `yyyy-MM-dd`, the day the person said yes.
    let memoryDate: String
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation
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
    var saves: [GameSaveRoundPayload] = []

    static let none = DrawAndGuessPendingWork()

    var isEmpty: Bool {
        pick == nil && drawings.isEmpty && guesses.isEmpty && giveUps.isEmpty && saves.isEmpty
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

    func hasSave(roundID: UUID) -> Bool {
        saves.contains { $0.roundID == roundID }
    }

    /// A move of the turn (not a save) waits to be sent.
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
        func read<Payload: Decodable>(_ kind: SyncPendingOperationKind) async throws -> [Payload] {
            try await store.inFlightOperations(ownerUserID: ownerUserID, kind: kind).compactMap { operation in
                operation.requestData.flatMap { try? decoder.decode(Payload.self, from: $0) }
            }
        }
        do {
            work.pick = try await read(.pickDrawWord).last
            work.drawings = try await read(.submitGameDrawing)
            work.guesses = try await read(.submitGameGuess)
            work.giveUps = try await read(.giveUpGameRound)
            work.saves = try await read(.saveGameRoundToMemories)
        } catch {
            // A failed read keeps the screen as it is. Treating it as an empty
            // queue would make a queued move look lost.
            return nil
        }
        return work
    }
}
