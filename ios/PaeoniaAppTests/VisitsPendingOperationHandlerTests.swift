import Foundation
import Testing
@testable import PaeoniaApp

/// Covers what happens to an item's queued writes when the server refuses one of them for good.
struct VisitsPendingOperationHandlerTests {
    @Test func aRefusedAddTakesItsQueuedTickWithIt() async throws {
        let owner = UUID()
        let store = InMemoryPendingSyncOperationRepository()
        let cache = InMemoryVisitsCache()
        let item = UUID()
        let add = SaveTogetherItemPayload(id: item, title: "Ice skating")
        let tick = SetTogetherItemDonePayload(id: item, title: "Ice skating", isDone: true)
        try await enqueue(.saveTogetherItem, add, 1, owner, store)
        try await enqueue(.setTogetherItemDone, tick, 2, owner, store)

        let drain = PendingSyncOperationDrainStream(handlers: VisitsPendingOperationHandler.all(
            gateway: FullListGateway(), cache: cache
        ))
        try await drain.push(context: SyncContext(
            session: SyncSession(userID: owner), reason: .manualRefresh, pendingOperationStore: store
        ))

        #expect(await cache.state(ownerUserID: owner).refusals == [.item(title: "Ice skating")])
        #expect(try await store.inFlightOperations(ownerUserID: owner, kind: .setTogetherItemDone).isEmpty)
    }

    @Test func aHideWaitsForItsVisitsSaveSoTheServerKeepsIt() async throws {
        let owner = UUID()
        let store = InMemoryPendingSyncOperationRepository()
        let server = OnceFailingVisitsServer()
        let visit = Visit(id: UUID(), startDate: "2026-10-01", endDate: "2026-10-05")
        try await enqueue(.saveVisit, SaveVisitPayload(visit, server: nil, pending: []), 1, owner, store)
        try await enqueue(.dismissVisitMemoryPrompt, VisitIDPayload(id: visit.id), 2, owner, store)
        let drain = PendingSyncOperationDrainStream(handlers: VisitsPendingOperationHandler.all(
            gateway: server, cache: InMemoryVisitsCache()
        ))
        let context = SyncContext(
            session: SyncSession(userID: owner), reason: .manualRefresh, pendingOperationStore: store
        )

        try await drain.push(context: context)
        try await drain.push(context: context)

        #expect(await server.hidden == [visit.id])
        #expect(try await store.inFlightOperations(ownerUserID: owner, kind: .dismissVisitMemoryPrompt).isEmpty)
    }

    private func enqueue(
        _ kind: SyncPendingOperationKind,
        _ payload: some Encodable,
        _ sequence: Int64,
        _ owner: UUID,
        _ store: InMemoryPendingSyncOperationRepository
    ) async throws {
        try await store.enqueue(PendingSyncOperationRequest(
            ownerUserID: owner,
            operation: SyncClientOperation(
                id: UUID(), clientID: UUID(), clientSequence: sequence, localCreatedAt: Date()
            ),
            operationKind: kind,
            idempotencyScope: "visits",
            requestData: try JSONEncoder().encode(payload)
        ))
    }
}

/// A server whose list is full.
private struct FullListGateway: VisitsGateway {
    private var full: PaeoniaConvexError {
        .server(code: "23514", message: "a couple can have at most 100 list items")
    }

    func saveVisit(_: SaveVisitPayload, operation _: SyncClientOperation) throws -> Visit? { nil }
    func deleteVisit(id _: UUID, operation _: SyncClientOperation) throws {}
    func dismissMemoryPrompt(visitID _: UUID, operation _: SyncClientOperation) throws -> Visit? { nil }
    func saveItem(_: SaveTogetherItemPayload, operation _: SyncClientOperation) throws -> RemoteTogetherItem? {
        throw full
    }

    func setItemDone(
        _: SetTogetherItemDonePayload, operation _: SyncClientOperation
    ) throws -> RemoteTogetherItem? {
        throw full
    }

    func deleteItem(id _: UUID, operation _: SyncClientOperation) throws {}
}

private actor OnceFailingVisitsServer: VisitsGateway {
    private struct TimedOut: Error {}

    private var failsNextSave = true
    private var saved: Set<UUID> = []
    private(set) var hidden: [UUID] = []

    func saveVisit(_ payload: SaveVisitPayload, operation _: SyncClientOperation) throws -> Visit? {
        if failsNextSave {
            failsNextSave = false
            throw TimedOut()
        }
        saved.insert(payload.visit.id)
        return payload.visit
    }

    func dismissMemoryPrompt(visitID: UUID, operation _: SyncClientOperation) -> Visit? {
        guard saved.contains(visitID) else { return nil }
        hidden.append(visitID)
        return Visit(id: visitID, startDate: "2026-10-01", endDate: "2026-10-05", memoryPromptDismissed: true)
    }

    func deleteVisit(id _: UUID, operation _: SyncClientOperation) {}
    func saveItem(_: SaveTogetherItemPayload, operation _: SyncClientOperation) -> RemoteTogetherItem? { nil }
    func setItemDone(_: SetTogetherItemDonePayload, operation _: SyncClientOperation) -> RemoteTogetherItem? { nil }
    func deleteItem(id _: UUID, operation _: SyncClientOperation) {}
}
