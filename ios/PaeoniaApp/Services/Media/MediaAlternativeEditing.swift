import Foundation

nonisolated enum MediaAlternativeTarget: Codable, Hashable, Sendable {
    case chat(messageID: UUID, mediaAssetID: UUID)
    case daily(answerID: UUID)
    case story(storyID: UUID)
    case guessMySpot(roundID: UUID)
    case drawAndGuess(roundID: UUID)
    case exquisiteCorpse(partID: UUID)
    case widgetDrawing(revisionID: UUID)

    var maximumLength: Int { if case .widgetDrawing = self { 500 } else { 10_000 } }

    var scope: String {
        switch self {
        case let .chat(_, assetID): "media-alternative:\(assetID.uuidString.lowercased())"
        case let .daily(answerID): "answer-alternative:\(answerID.uuidString.lowercased())"
        case let .story(storyID): "story-alternative:\(storyID.uuidString.lowercased())"
        case let .guessMySpot(roundID): "guess-my-spot-alternative:\(roundID.uuidString.lowercased())"
        case let .drawAndGuess(roundID): "draw-and-guess-alternative:\(roundID.uuidString.lowercased())"
        case let .exquisiteCorpse(partID): "exquisite-corpse-alternative:\(partID.uuidString.lowercased())"
        case let .widgetDrawing(revisionID): "widget-drawing-alternative:\(revisionID.uuidString.lowercased())"
        }
    }
}

nonisolated struct MediaAlternativeEdit: Codable, Equatable, Sendable {
    let coupleID: UUID
    let target: MediaAlternativeTarget
    let text: String
}

nonisolated struct PendingMediaAlternative: Equatable, Sendable {
    let operationID: UUID
    let text: String
    let hasFailedAttempt: Bool
}

nonisolated enum MediaAlternativeEditingError: Error {
    case tooLong
    case privacyChanged
}

/// Queued text is the durable local overlay while a live read still holds the previous alternative.
nonisolated struct MediaAlternativeEditingService: Sendable {
    let pending: any PendingSyncOperationPersisting
    let cache: MediaAlternativeCacheUpdater

    @MainActor
    static func live() -> Self {
        Self(
            pending: SwiftDataPendingSyncOperationRepository(container: PaeoniaLocalStore.shared.container),
            cache: .live
        )
    }

    func pendingEdit(ownerUserID: UUID, coupleID: UUID, target: MediaAlternativeTarget) async throws
        -> PendingMediaAlternative? {
        let queued = try await pending.inFlightOperations(ownerUserID: ownerUserID, kind: .updateMediaAlternative)
        return queued.compactMap { operation -> (PendingSyncOperationSnapshot, MediaAlternativeEdit)? in
            guard let bytes = operation.requestData,
                  let edit = try? JSONDecoder().decode(MediaAlternativeEdit.self, from: bytes),
                  edit.coupleID == coupleID, edit.target == target else { return nil }
            return (operation, edit)
        }.max { first, second in
            if first.0.operation.clientID == second.0.operation.clientID {
                return first.0.operation.clientSequence < second.0.operation.clientSequence
            }
            return (first.0.operation.localCreatedAt, first.0.operation.clientSequence)
                < (second.0.operation.localCreatedAt, second.0.operation.clientSequence)
        }.map { operation, edit in
            PendingMediaAlternative(operationID: operation.operation.id, text: edit.text,
                                    hasFailedAttempt: operation.hasFailedAttempt)
        }
    }

    func queue(
        _ edit: MediaAlternativeEdit,
        ownerUserID: UUID,
        operation: SyncClientOperation,
        stamp: MediaAlternativeCacheUpdater.Stamp
    ) async throws {
        guard edit.text.unicodeScalars.count <= edit.target.maximumLength else {
            throw MediaAlternativeEditingError.tooLong
        }
        guard await cache.isCurrent(stamp) else { throw MediaAlternativeEditingError.privacyChanged }
        try Task.checkCancellation()
        try await pending.enqueue(PendingSyncOperationRequest(
            ownerUserID: ownerUserID, operation: operation, operationKind: .updateMediaAlternative,
            idempotencyScope: edit.target.scope, requestData: try JSONEncoder().encode(edit),
            privacyToken: stamp.privacy
        ))
        guard await cache.isCurrent(stamp) else {
            _ = try? await pending.discardUnsent(clientOperationID: operation.id)
            throw MediaAlternativeEditingError.privacyChanged
        }
        try await cache.apply(edit, ownerUserID: ownerUserID, operation: operation, stamp: stamp)
    }
}
