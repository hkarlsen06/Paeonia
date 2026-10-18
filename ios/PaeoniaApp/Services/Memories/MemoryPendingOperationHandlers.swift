import Foundation

// Every handler ends a queued memory write in one of four ways:
// - The server accepted it: pull the server copy so the local record is clean again.
// - The partner changed the memory first (revision conflict): rebase the write on the
//   server copy and send it again, keeping the partner's change for anything this
//   write didn't touch.
// - The server refused it because the memory is gone (the partner deleted it): show
//   the server copy on this device and stop retrying.
// - A server check refused it (`23514`, such as a title that is too long): stop
//   retrying and keep the text on this phone, so newer edits are not held up.
// Any other failure is thrown, so the outbox retries later. Nothing is marked as a
// conflict, because a conflicted record would never take server updates again.

struct CreateMemoryPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createMemory

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing create memory payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(CreateMemoryOperationPayload.self, from: requestData)
        _ = try await gateway.createMemory(payload, operation: operation.operation)
        return try await MemoryPendingOperationRefresh.succeeded(
            operation,
            gateway: gateway,
            memoryStore: memoryStore,
            context: context
        )
    }
}

struct UpdateMemoryPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateMemory

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing update memory payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(UpdateMemoryOperationPayload.self, from: requestData)
        let refresh = MemoryPendingOperationRefresh.self
        if let older = try await refresh.olderPendingWrite(
            before: operation,
            memoryID: payload.memoryID,
            context: context,
            memoryIDIn: { try? JSONDecoder().decode(UpdateMemoryOperationPayload.self, from: $0).memoryID }
        ) {
            return .retry(after: refresh.retryDate(after: older))
        }

        do {
            _ = try await gateway.updateMemory(payload, operation: operation.operation)
        } catch where refresh.isMemoryConflict(error) {
            guard let row = try await refresh.serverRow(memoryID: payload.memoryID, gateway: gateway) else {
                throw error
            }
            guard row.isVisibleMemory else {
                return try await refresh.acceptRemoval(row, operation, memoryStore: memoryStore)
            }

            let rebased = payload.rebased(onto: row)
            if rebased.title != row.title || rebased.memoryDate != row.memoryDate {
                _ = try await gateway.updateMemory(rebased, operation: operation.operation)
            }
        } catch {
            return try await refresh.settleRejectedWrite(
                error,
                memoryID: payload.memoryID,
                operation,
                gateway: gateway,
                memoryStore: memoryStore,
                context: context
            )
        }

        return try await refresh.succeeded(operation, gateway: gateway, memoryStore: memoryStore, context: context)
    }
}

struct SetMemoryPlacePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .setMemoryPlace

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing set memory place payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(SetMemoryPlaceOperationPayload.self, from: requestData)
        let refresh = MemoryPendingOperationRefresh.self
        // The server keeps the last place it receives, so an older place still waiting
        // to retry must land first.
        if let older = try await refresh.olderPendingWrite(
            before: operation,
            memoryID: payload.memoryID,
            context: context,
            memoryIDIn: { try? JSONDecoder().decode(SetMemoryPlaceOperationPayload.self, from: $0).memoryID }
        ) {
            return .retry(after: refresh.retryDate(after: older))
        }

        do {
            _ = try await gateway.setMemoryPlace(payload, operation: operation.operation)
        } catch {
            return try await refresh.settleRejectedWrite(
                error,
                memoryID: payload.memoryID,
                operation,
                gateway: gateway,
                memoryStore: memoryStore,
                context: context
            )
        }
        return try await refresh.succeeded(operation, gateway: gateway, memoryStore: memoryStore, context: context)
    }
}

struct HideMemoryPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .hideMemory

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing hide memory payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(HideMemoryOperationPayload.self, from: requestData)
        let refresh = MemoryPendingOperationRefresh.self

        do {
            _ = try await gateway.hideMemory(payload, operation: operation.operation)
        } catch {
            // The person confirmed the delete, so it wins over an edit the partner made
            // in the meantime. If the memory is already gone, the delete is done.
            guard refresh.isServerRejection(error),
                  let row = try await refresh.serverRow(memoryID: payload.memoryID, gateway: gateway)
            else {
                throw error
            }
            guard row.isVisibleMemory else {
                try await memoryStore.saveRemote(
                    [row],
                    ownerUserID: operation.ownerUserID,
                    mergePolicy: .overwriteLocalChanges
                )
                return .succeeded
            }
            guard refresh.isMemoryConflict(error) else { throw error }
            _ = try await gateway.hideMemory(
                HideMemoryOperationPayload(memoryID: payload.memoryID, expectedRevision: row.revision),
                operation: operation.operation
            )
        }

        return try await refresh.succeeded(operation, gateway: gateway, memoryStore: memoryStore, context: context)
    }
}

struct UpsertMemoryNotePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .upsertMemoryNote

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing upsert memory note payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(UpsertMemoryNoteOperationPayload.self, from: requestData)
        let refresh = MemoryPendingOperationRefresh.self
        if let older = try await refresh.olderPendingWrite(
            before: operation,
            memoryID: payload.memoryID,
            context: context,
            memoryIDIn: { try? JSONDecoder().decode(UpsertMemoryNoteOperationPayload.self, from: $0).memoryID }
        ) {
            return .retry(after: refresh.retryDate(after: older))
        }

        do {
            _ = try await gateway.upsertMemoryNote(payload, operation: operation.operation)
        } catch where refresh.isMemoryConflict(error) {
            // Only this person writes their own note, so a conflict means another of
            // their devices saved first. The newest save wins.
            guard let row = try await refresh.serverRow(memoryID: payload.memoryID, gateway: gateway) else {
                throw error
            }
            guard row.isVisibleMemory else {
                return try await refresh.acceptRemoval(row, operation, memoryStore: memoryStore)
            }
            _ = try await gateway.upsertMemoryNote(
                UpsertMemoryNoteOperationPayload(
                    memoryID: payload.memoryID,
                    expectedRevision: row.ownNoteRevision,
                    body: payload.body
                ),
                operation: operation.operation
            )
        } catch {
            return try await refresh.settleRejectedWrite(
                error, memoryID: payload.memoryID, operation,
                gateway: gateway, memoryStore: memoryStore, context: context
            )
        }

        return try await refresh.succeeded(operation, gateway: gateway, memoryStore: memoryStore, context: context)
    }
}

struct AttachMemoryMediaPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .attachMemoryMedia

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing attach memory media payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(AttachMemoryMediaOperationPayload.self, from: requestData)
        do {
            _ = try await gateway.attachMemoryMedia(payload, operation: operation.operation)
        } catch {
            return try await MemoryPendingOperationRefresh.settleRejectedWrite(
                error,
                memoryID: payload.memoryID,
                operation,
                gateway: gateway,
                memoryStore: memoryStore,
                context: context
            )
        }
        return try await MemoryPendingOperationRefresh.succeeded(
            operation,
            gateway: gateway,
            memoryStore: memoryStore,
            context: context
        )
    }
}

struct RemoveMemoryMediaPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .removeMemoryMedia

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing remove memory media payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(RemoveMemoryMediaOperationPayload.self, from: requestData)
        let refresh = MemoryPendingOperationRefresh.self
        do {
            _ = try await gateway.removeMemoryMedia(payload, operation: operation.operation)
        } catch {
            // A photo that is already gone (removed on another device, or by moderation)
            // needs no more work.
            guard refresh.isServerRejection(error),
                  let row = try await refresh.serverRow(memoryID: payload.memoryID, gateway: gateway),
                  row.isVisibleMemory,
                  !row.memoryMediaIDs.contains(payload.memoryMediaID)
            else {
                return try await refresh.settleRejectedWrite(
                    error,
                    memoryID: payload.memoryID,
                    operation,
                    gateway: gateway,
                    memoryStore: memoryStore,
                    context: context
                )
            }
        }
        return try await refresh.succeeded(operation, gateway: gateway, memoryStore: memoryStore, context: context)
    }
}

// swiftlint:disable:next type_name
struct CreateMemoryThreadMessagePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createMemoryThreadWithMessage

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing memory thread message payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(
            CreateMemoryThreadMessageOperationPayload.self,
            from: requestData
        )
        _ = try await gateway.createMemoryThreadWithMessage(payload, operation: operation.operation)
        return try await MemoryPendingOperationRefresh.succeeded(
            operation,
            gateway: gateway,
            memoryStore: memoryStore,
            context: context
        )
    }
}
