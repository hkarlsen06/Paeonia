import Foundation

/// Sends one queued visit or list write, then writes what the server stored into the cache,
/// so the screen doesn't flash the old state between the send and the live feed. One handler
/// type serves the five write kinds. A write the server refuses for good is kept in the cache
/// until a screen tells the person.
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
            await cache.confirm(confirmed, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.visits, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError where CoupleDatesRejection.isPermanent(error) {
            if let refusal = write.refusal {
                await cache.recordRefusal(refusal, ownerUserID: operation.ownerUserID)
            }
            return .terminalFailure(error.description)
        }
    }

    /// The row as the server stored it. A nil row means it is gone, so the cache drops it too.
    private func send(_ write: VisitsWrite, operation: SyncClientOperation) async throws -> VisitsConfirmation {
        switch write {
        case let .saveVisit(visit):
            let stored = try await gateway.saveVisit(visit, operation: operation)
            return stored.map(VisitsConfirmation.visit) ?? .visitGone(visit.id)
        case let .deleteVisit(id):
            try await gateway.deleteVisit(id: id, operation: operation)
            return .visitGone(id)
        case let .saveItem(payload):
            let stored = try await gateway.saveItem(payload, operation: operation)
            return stored.map { .item($0.item) } ?? .itemGone(payload.id)
        case let .setItemDone(payload):
            let stored = try await gateway.setItemDone(payload, operation: operation)
            return stored.map { .item($0.item) } ?? .itemGone(payload.id)
        case let .deleteItem(id):
            try await gateway.deleteItem(id: id, operation: operation)
            return .itemGone(id)
        }
    }
}
