import Foundation

nonisolated struct SetRelationshipStartedOnOperationPayload: Codable, Equatable, Sendable {
    let startedOn: String
}

nonisolated struct RelationshipStartedOnLocalState: Equatable, Sendable {
    let startedOn: String?
    let hasPendingChange: Bool
}

nonisolated protocol RelationshipStartedOnDataServicing: Actor {
    func loadStartedOn(ownerUserID: UUID) async throws -> RelationshipStartedOnLocalState

    func setStartedOn(
        _ startedOn: PairingStartDate,
        ownerUserID: UUID,
        operation: SyncClientOperation
    ) async throws
}

actor RelationshipStartedOnDataService: RelationshipStartedOnDataServicing {
    private let accessSnapshotStore: any AccessSyncSnapshotPersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        pendingOperationStore: any PendingSyncOperationPersisting
    ) {
        self.accessSnapshotStore = accessSnapshotStore
        self.pendingOperationStore = pendingOperationStore
    }

    func loadStartedOn(ownerUserID: UUID) async throws -> RelationshipStartedOnLocalState {
        let pendingOperations = try await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .setRelationshipStartedOn
        )

        let latestPendingOperation = pendingOperations.max { first, second in
            first.operation.clientSequence < second.operation.clientSequence
        }

        if let requestData = latestPendingOperation?.requestData,
           let payload = try? decoder.decode(
               SetRelationshipStartedOnOperationPayload.self,
               from: requestData
           ) {
            return RelationshipStartedOnLocalState(
                startedOn: payload.startedOn,
                hasPendingChange: true
            )
        }

        let cachedStartedOn = try await accessSnapshotStore.load(ownerUserID: ownerUserID)?
            .relationshipState?
            .startedOn
        return RelationshipStartedOnLocalState(
            startedOn: cachedStartedOn,
            hasPendingChange: false
        )
    }

    func setStartedOn(
        _ startedOn: PairingStartDate,
        ownerUserID: UUID,
        operation: SyncClientOperation
    ) async throws {
        let payload = SetRelationshipStartedOnOperationPayload(startedOn: startedOn.rawValue)

        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .setRelationshipStartedOn,
                idempotencyScope: "couple:started_on",
                requestData: try encoder.encode(payload)
            )
        )

        // The queued payload is the durable source of truth while offline. Updating
        // the access snapshot too makes the chosen date available on the next render
        // even before the retry reaches Supabase.
        try? await accessSnapshotStore.replaceRelationshipStartedOn(
            ownerUserID: ownerUserID,
            startedOn: startedOn.rawValue,
            refreshedAt: operation.localCreatedAt
        )
    }
}

nonisolated enum RelationshipStartedOnDataServiceFactory {
    static func makeDefault() -> any RelationshipStartedOnDataServicing {
        do {
            let localStore = try PaeoniaLocalStore()
            return RelationshipStartedOnDataService(
                accessSnapshotStore: SwiftDataAccessSyncSnapshotRepository(
                    container: localStore.container
                ),
                pendingOperationStore: SwiftDataPendingSyncOperationRepository(
                    container: localStore.container
                )
            )
        } catch {
            return RelationshipStartedOnDataService(
                accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
                pendingOperationStore: InMemoryPendingSyncOperationRepository()
            )
        }
    }
}
