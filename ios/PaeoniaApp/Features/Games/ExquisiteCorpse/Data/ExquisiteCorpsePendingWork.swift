import Foundation

// What each queued Exquisite corpse write carries. The payloads fix every id and
// operation up front, so a retry after a lost response replays the same requests.

/// A file waiting to be uploaded for a part, with the client operations of its
/// two upload steps.
nonisolated struct ExquisiteCorpseQueuedUpload: Codable, Equatable, Sendable {
    /// A `PKDrawing` at the canonical canvas size (`GameCanvas.canonicalSide`).
    let data: Data
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation
}

/// `exquisiteCorpse:submit_exquisite_corpse_part`. The figure and part ids are
/// made on this phone (`ExquisiteCorpseIDs`), so a later move can name them
/// before the server has seen them. The submit call uses the queued operation's
/// own client operation.
nonisolated struct ExquisiteCorpseSubmitPartPayload: Codable, Equatable, Sendable {
    let gameID: UUID
    let figureID: UUID
    let partID: UUID
    /// 0 for the head, 1 for the body and 2 for the legs.
    let partIndex: Int
    let coupleID: UUID
    /// The whole part.
    let drawing: ExquisiteCorpseQueuedUpload
    /// The part clipped to the strip (`ExquisiteCorpseFold`). Set for the head and
    /// the body and nil for the legs.
    let strip: ExquisiteCorpseQueuedUpload?
    /// The idea on the chip when the drawer tapped Done. It stays with the part.
    let idea: RemoteExquisiteCorpseIdea?
    let createdAt: Date
    /// When the part was queued again because an upload was gone.
    var renewedAt: Date?
}

nonisolated extension ExquisiteCorpseSubmitPartPayload {
    /// The same part with new operations for its uploads, so the kept drawings
    /// upload again instead of replaying a reservation the server deleted.
    func withNewUploads(renewedAt date: Date) -> ExquisiteCorpseSubmitPartPayload {
        ExquisiteCorpseSubmitPartPayload(
            gameID: gameID,
            figureID: figureID,
            partID: partID,
            partIndex: partIndex,
            coupleID: coupleID,
            drawing: drawing.withNewOperations(),
            strip: strip?.withNewOperations(),
            idea: idea,
            createdAt: createdAt,
            renewedAt: date
        )
    }
}

nonisolated extension ExquisiteCorpseQueuedUpload {
    fileprivate func withNewOperations() -> ExquisiteCorpseQueuedUpload {
        func renewed(_ old: SyncClientOperation) -> SyncClientOperation {
            SyncClientOperation(clientID: old.clientID, clientSequence: old.clientSequence)
        }
        return ExquisiteCorpseQueuedUpload(
            data: data,
            reserveOperation: renewed(reserveOperation),
            finalizeOperation: renewed(finalizeOperation)
        )
    }
}

/// This person moved past the reveal of a finished figure.
nonisolated struct ExquisiteCorpseRevealSeenPayload: Codable, Equatable, Sendable {
    let figureID: UUID
    let createdAt: Date
}

/// The queued Exquisite corpse writes of one person that have not reached the
/// server, as the screens need them. A write refused for good is no longer in
/// flight, so it drops out of this value and the screen falls back to the
/// server's state.
nonisolated struct ExquisiteCorpsePendingWork: Equatable, Sendable {
    /// Parts waiting to be sent, oldest first.
    var parts: [ExquisiteCorpseSubmitPartPayload] = []
    var revealsSeen: [ExquisiteCorpseRevealSeenPayload] = []
    /// A waiting part was tried again and the attempt failed for a reason other
    /// than having no connection, such as the server refusing it. The waiting
    /// screen then says so instead of "saved on this phone".
    var lastSendFailedWhileOnline = false
    /// A waiting part has had a try that did not get through, for any reason.
    /// Until then the part is on its first send, and the screen says nothing about
    /// it being on this phone, so a normal send never flashes that line.
    var hasFailedMoveAttempt = false

    static let none = ExquisiteCorpsePendingWork()

    var isEmpty: Bool {
        parts.isEmpty && revealsSeen.isEmpty
    }

    /// A part (not a reveal seen mark) waits to be sent.
    var hasMoveWaiting: Bool {
        !parts.isEmpty
    }

    func hasRevealSeen(figureID: UUID) -> Bool {
        revealsSeen.contains { $0.figureID == figureID }
    }

    /// Reads the queue. Payloads that fail to decode are skipped.
    static func load(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> ExquisiteCorpsePendingWork? {
        var work = ExquisiteCorpsePendingWork()
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
            work.parts = try await read(.exquisiteCorpseSubmitPart)
            work.revealsSeen = try await read(.exquisiteCorpseRevealSeen, isMove: false)
        } catch {
            // A failed read keeps the screen as it is. Treating it as an empty
            // queue would make a queued move look lost.
            return nil
        }
        return work
    }
}
