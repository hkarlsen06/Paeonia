import Foundation
@testable import PaeoniaApp

/// The phone's pending operations, which outlive a force quit like the SwiftData
/// store does. It forwards to the in-memory repository and keeps a ledger of
/// every write the phone queued and how it ended, so the driver can tell a move
/// that landed from one that was dropped.
actor SimPendingStore: PendingSyncOperationPersisting {
    struct Entry: Sendable {
        let operationID: UUID
        let kind: SyncPendingOperationKind
        let requestData: Data?
        let createdAt: Date
        var outcome: Outcome = .inFlight
    }

    enum Outcome: Equatable, Sendable {
        case inFlight
        case succeeded
        case terminal(String)
    }

    private let base = InMemoryPendingSyncOperationRepository()
    /// The kinds of write the game queues, for the queue counts.
    private let gameKinds: [SyncPendingOperationKind]
    /// Told about every new write, for the action log.
    private var onEnqueue: (@Sendable (SyncPendingOperationKind, Data?) -> Void)?

    init(gameKinds: [SyncPendingOperationKind] = SimPendingStore.gameKinds) {
        self.gameKinds = gameKinds
    }

    func setOnEnqueue(_ handler: @escaping @Sendable (SyncPendingOperationKind, Data?) -> Void) {
        onEnqueue = handler
    }
    private(set) var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []

    var ledger: [Entry] {
        order.compactMap { entries[$0] }
    }

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        if entries[request.operation.id] == nil {
            entries[request.operation.id] = Entry(
                operationID: request.operation.id,
                kind: request.operationKind,
                requestData: request.requestData,
                createdAt: request.operation.localCreatedAt
            )
            order.append(request.operation.id)
            onEnqueue?(request.operationKind, request.requestData)
        }
        try await base.enqueue(request)
    }

    func readyOperations(ownerUserID: UUID, limit: Int, now: Date) async throws -> [PendingSyncOperationSnapshot] {
        try await base.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
        try await base.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        try await base.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }

    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSending(clientOperationID: clientOperationID, at: date)
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSucceeded(clientOperationID: clientOperationID, at: date)
        entries[clientOperationID]?.outcome = .succeeded
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) async throws {
        try await base.markRetryableFailure(
            clientOperationID: clientOperationID,
            errorDescription: errorDescription,
            nextRetryAt: nextRetryAt,
            at: date
        )
    }

    func markTerminalFailure(clientOperationID: UUID, errorDescription: String, at date: Date) async throws {
        try await base.markTerminalFailure(
            clientOperationID: clientOperationID,
            errorDescription: errorDescription,
            at: date
        )
        entries[clientOperationID]?.outcome = .terminal(errorDescription)
    }

    func deleteCompleted(ownerUserID: UUID) async throws {
        try await base.deleteCompleted(ownerUserID: ownerUserID)
    }

    func resetInFlight(ownerUserID: UUID) async throws {
        try await base.resetInFlight(ownerUserID: ownerUserID)
    }

    /// Every write still waiting, of any game kind.
    func inFlightCount(ownerUserID: UUID) async -> Int {
        var count = 0
        for kind in gameKinds {
            count += (try? await base.inFlightOperations(ownerUserID: ownerUserID, kind: kind).count) ?? 0
        }
        return count
    }

    /// The status of each waiting write, so the driver can tell when the queue stopped changing.
    func fingerprint(ownerUserID: UUID) async -> String {
        var parts: [String] = []
        for kind in gameKinds {
            let operations = (try? await base.inFlightOperations(ownerUserID: ownerUserID, kind: kind)) ?? []
            parts += operations.map {
                "\($0.operation.id.uuidString.prefix(6)):\($0.status.rawValue):\($0.attemptCount)"
            }
        }
        return parts.joined(separator: ",") + "#\(order.count)"
    }

    /// The Draw & Guess kinds, which a store uses unless it is given others.
    static let gameKinds: [SyncPendingOperationKind] = [
        .pickDrawWord, .submitGameDrawing, .submitGameGuess, .giveUpGameRound,
        .markGameRoundResultSeen,
    ]
}
