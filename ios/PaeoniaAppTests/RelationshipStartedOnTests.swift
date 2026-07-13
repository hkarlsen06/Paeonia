import Foundation
import Testing
@testable import PaeoniaApp

struct RelationshipStartedOnDataServiceTests {
    @Test func storageDateRemainsGregorianWithNonGregorianPreferredCalendar() throws {
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let selectedDate = try #require(
            gregorianCalendar.date(from: DateComponents(year: 2_026, month: 7, day: 10))
        )
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = gregorianCalendar.timeZone

        let storedDate = PairingStartDate(date: selectedDate, calendar: buddhistCalendar)
        let restoredDate = try #require(storedDate.date(calendar: buddhistCalendar))
        let restoredComponents = gregorianCalendar.dateComponents(
            [.year, .month, .day],
            from: restoredDate
        )

        #expect(storedDate.rawValue == "2026-07-10")
        #expect(restoredComponents.year == 2_026)
        #expect(restoredComponents.month == 7)
        #expect(restoredComponents.day == 10)
    }

    @Test func localWriteIsImmediatelyReadableAndDurablyQueued() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let accessStore = InMemoryAccessSyncSnapshotRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = RelationshipStartedOnDataService(
            accessSnapshotStore: accessStore,
            pendingOperationStore: pendingStore
        )
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 4,
            localCreatedAt: Date(timeIntervalSince1970: 40)
        )
        let startedOn = try PairingStartDate(rawValue: "2024-02-29")

        try await accessStore.save(
            AccessSyncSnapshot(
                ownerUserID: ownerUserID,
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: try relationshipState(startedOn: nil)
            )
        )

        try await service.setStartedOn(
            startedOn,
            ownerUserID: ownerUserID,
            operation: operation
        )

        let loaded = try await service.loadStartedOn(ownerUserID: ownerUserID)
        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .setRelationshipStartedOn
        )
        let cached = try await accessStore.load(ownerUserID: ownerUserID)

        #expect(loaded.startedOn == "2024-02-29")
        #expect(loaded.hasPendingChange)
        #expect(cached?.relationshipState?.startedOn == "2024-02-29")
        #expect(queued.count == 1)
        #expect(queued.first?.operation == operation)
    }

    // swiftlint:disable:next function_body_length
    @Test func pendingHandlerConfirmsDateInAccessSnapshot() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 4,
            localCreatedAt: Date(timeIntervalSince1970: 40)
        )
        let payload = SetRelationshipStartedOnOperationPayload(startedOn: "2024-02-29")
        let accessStore = InMemoryAccessSyncSnapshotRepository()
        let gateway = RelationshipStartedOnGatewaySpy()
        let handler = RelationshipDatePendingOperationHandler(
            gateway: gateway,
            accessSnapshotStore: accessStore
        )

        try await accessStore.save(
            AccessSyncSnapshot(
                ownerUserID: ownerUserID,
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: try relationshipState(startedOn: nil)
            )
        )

        let result = try await handler.send(
            PendingSyncOperationSnapshot(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .setRelationshipStartedOn,
                idempotencyScope: "couple:started_on",
                requestHash: nil,
                requestData: try JSONEncoder().encode(payload),
                status: .queued,
                attemptCount: 0,
                lastAttemptAt: nil,
                nextRetryAt: nil,
                lastError: nil,
                completedAt: nil
            ),
            context: SyncContext(
                session: SyncSession(userID: ownerUserID),
                reason: .localChange,
                stateStore: InMemorySyncStateRepository(),
                pendingOperationStore: InMemoryPendingSyncOperationRepository()
            )
        )

        let cached = try await accessStore.load(ownerUserID: ownerUserID)
        #expect(result == .succeeded)
        #expect(await gateway.receivedStartedOn?.rawValue == "2024-02-29")
        #expect(await gateway.receivedOperation == operation)
        #expect(cached?.relationshipState?.startedOn == "2024-02-29")
    }

    @Test func partnerAccessPullReceivesChangedDate() async throws {
        let partnerUserID = try #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))
        let accessStore = InMemoryAccessSyncSnapshotRepository()
        let gateway = RelationshipStartedOnAccessGateway(
            snapshot: SupabaseAccessSnapshot(
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: try relationshipState(startedOn: "2024-02-29")
            )
        )
        let stream = AccessSyncStream(gateway: gateway, snapshotStore: accessStore)

        _ = try await stream.pull(
            context: SyncContext(
                session: SyncSession(userID: partnerUserID),
                reason: .foreground,
                stateStore: InMemorySyncStateRepository(),
                pendingOperationStore: InMemoryPendingSyncOperationRepository()
            )
        )

        #expect(
            try await accessStore.load(ownerUserID: partnerUserID)?
                .relationshipState?
                .startedOn == "2024-02-29"
        )
    }

    private func relationshipState(startedOn: String?) throws -> SupabaseRelationshipState {
        SupabaseRelationshipState(
            coupleID: try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444")),
            pairID: try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
            relationshipStatus: .active,
            memberStatus: .active,
            partnerUserID: UUID(uuidString: "66666666-6666-6666-6666-666666666666"),
            partnerDisplayName: "Alex",
            partnerProfilePhotoAssetID: nil,
            startedOn: startedOn,
            endedAt: nil,
            deleteAfter: nil,
            endedNoticeSeenAt: nil
        )
    }
}

struct RelationshipMilestoneViewModelTests {
    @MainActor
    @Test func serverRefreshDuringConfigurationIsNotOverwrittenByStaleInput() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let dataService = SuspendedStartedOnDataService()
        let viewModel = RelationshipMilestoneViewModel(dataService: dataService)

        let configuration = Task {
            await viewModel.configure(ownerUserID: ownerUserID, serverStartedOn: "2020-01-01")
        }
        await dataService.waitUntilLoadStarts()
        viewModel.refreshServerStartedOn("2024-02-29")
        await dataService.finishLoad(
            with: RelationshipStartedOnLocalState(startedOn: nil, hasPendingChange: false)
        )
        await configuration.value

        #expect(viewModel.startedOn == "2024-02-29")
    }

    @MainActor
    @Test func missingDateTransitionsToSavedMilestoneAndRequestsSync() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let dataService = RelationshipStartedOnDataServiceSpy()
        let operation = SyncClientOperation(
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 7
        )
        let viewModel = RelationshipMilestoneViewModel(
            dataService: dataService,
            operationProvider: RelationshipStartedOnOperationProvider(operation: operation)
        )
        var syncCount = 0
        viewModel.setSyncAfterLocalChange { syncCount += 1 }

        await viewModel.configure(ownerUserID: ownerUserID, serverStartedOn: nil)
        #expect(viewModel.startedOn == nil)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(
            calendar.date(from: DateComponents(year: 2_024, month: 2, day: 29))
        )
        let saved = await viewModel.save(startedOn: date, calendar: calendar)
        await Task.yield()

        #expect(saved)
        #expect(viewModel.startedOn == "2024-02-29")
        #expect(viewModel.error == nil)
        #expect(await dataService.savedStartedOn?.rawValue == "2024-02-29")
        #expect(await dataService.savedOwnerUserID == ownerUserID)
        #expect(await dataService.savedOperation == operation)
        #expect(syncCount == 1)

        viewModel.refreshServerStartedOn("2020-01-01")
        #expect(viewModel.startedOn == "2024-02-29")

        await dataService.markPendingChangeCompleted()
        await viewModel.retryPendingChangeIfNeeded()
        viewModel.refreshServerStartedOn("2023-01-01")
        #expect(viewModel.startedOn == "2023-01-01")
    }
}

// swiftlint:disable async_without_await
private actor RelationshipStartedOnGatewaySpy: SupabaseRelationshipStartedOnGateway {
    private(set) var receivedStartedOn: PairingStartDate?
    private(set) var receivedOperation: SyncClientOperation?

    func setStartedOn(
        _ startedOn: PairingStartDate,
        operation: SyncClientOperation
    ) async throws -> String {
        receivedStartedOn = startedOn
        receivedOperation = operation
        return startedOn.rawValue
    }
}

private actor RelationshipStartedOnAccessGateway: SupabaseAccessGateway {
    private let snapshot: SupabaseAccessSnapshot

    init(snapshot: SupabaseAccessSnapshot) {
        self.snapshot = snapshot
    }

    func loadAccessSnapshot() async throws -> SupabaseAccessSnapshot {
        snapshot
    }

    func loadRelationshipSyncEvents(
        after cursor: SyncCursor,
        limit: Int
    ) async throws -> [SupabaseRelationshipSyncEvent] {
        []
    }

    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws {}
}

private actor RelationshipStartedOnDataServiceSpy: RelationshipStartedOnDataServicing {
    private(set) var savedStartedOn: PairingStartDate?
    private(set) var savedOwnerUserID: UUID?
    private(set) var savedOperation: SyncClientOperation?
    private var hasPendingChange = false

    func loadStartedOn(ownerUserID: UUID) async throws -> RelationshipStartedOnLocalState {
        RelationshipStartedOnLocalState(
            startedOn: savedOwnerUserID == ownerUserID ? savedStartedOn?.rawValue : nil,
            hasPendingChange: savedOwnerUserID == ownerUserID && hasPendingChange
        )
    }

    func setStartedOn(
        _ startedOn: PairingStartDate,
        ownerUserID: UUID,
        operation: SyncClientOperation
    ) async throws {
        savedStartedOn = startedOn
        savedOwnerUserID = ownerUserID
        savedOperation = operation
        hasPendingChange = true
    }

    func markPendingChangeCompleted() {
        hasPendingChange = false
    }
}

private actor SuspendedStartedOnDataService: RelationshipStartedOnDataServicing {
    private var loadContinuation: CheckedContinuation<RelationshipStartedOnLocalState, Never>?

    func loadStartedOn(ownerUserID _: UUID) async throws -> RelationshipStartedOnLocalState {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func setStartedOn(
        _: PairingStartDate,
        ownerUserID _: UUID,
        operation _: SyncClientOperation
    ) async throws {}

    func waitUntilLoadStarts() async {
        while loadContinuation == nil {
            await Task.yield()
        }
    }

    func finishLoad(with state: RelationshipStartedOnLocalState) {
        loadContinuation?.resume(returning: state)
        loadContinuation = nil
    }
}
// swiftlint:enable async_without_await

@MainActor
private final class RelationshipStartedOnOperationProvider: PairingClientOperationProviding {
    private let operation: PairingClientOperation

    init(operation: PairingClientOperation) {
        self.operation = operation
    }

    func makeOperation() -> PairingClientOperation {
        operation
    }
}
