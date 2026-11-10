import Foundation

/// Sends one queued visit or list write, then writes what the server stored into the cache,
/// so the screen doesn't flash the old state between the send and the live feed. One handler
/// type serves the five write kinds.
struct VisitsPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind

    let gateway: any VisitsGateway
    let cache: any VisitsCaching

    static func all(gateway: any VisitsGateway, cache: any VisitsCaching) -> [Self] {
        VisitsWrite.operationKinds.map { Self(operationKind: $0, gateway: gateway, cache: cache) }
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let write = VisitsWrite(operation) else {
            return .terminalFailure("Missing visit payload")
        }
        do {
            let confirmed = try await send(write, operation: operation.operation)
            await cache.apply(confirmed, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.visits, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError where CoupleDatesRejection.isPermanent(error) {
            return .terminalFailure(error.description)
        }
    }

    /// The write as the server stored it. A nil row means it was deleted, so the cache drops it too.
    private func send(_ write: VisitsWrite, operation: SyncClientOperation) async throws -> VisitsWrite {
        switch write {
        case let .saveVisit(visit):
            let stored = try await gateway.saveVisit(visit, operation: operation)
            return stored.map(VisitsWrite.saveVisit) ?? .deleteVisit(visit.id)
        case let .deleteVisit(id):
            try await gateway.deleteVisit(id: id, operation: operation)
            return write
        case let .saveItem(payload):
            let stored = try await gateway.saveItem(payload, operation: operation)
            return stored.map { .saveItem(SaveTogetherItemPayload(id: $0.id, title: $0.title)) }
                ?? .deleteItem(payload.id)
        case let .setItemDone(payload):
            let stored = try await gateway.setItemDone(payload, operation: operation)
            return stored.map { .setItemDone(SetTogetherItemDonePayload(id: $0.id, isDone: $0.doneAt != nil)) }
                ?? .deleteItem(payload.id)
        case let .deleteItem(id):
            try await gateway.deleteItem(id: id, operation: operation)
            return write
        }
    }
}
