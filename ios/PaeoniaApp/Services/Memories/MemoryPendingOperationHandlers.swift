import Foundation

struct CreateMemoryPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createMemory

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing create memory payload")
        }

        let payload = try JSONDecoder().decode(CreateMemoryOperationPayload.self, from: requestData)

        do {
            _ = try await gateway.createMemory(payload, operation: operation.operation)
            try await MemoryPendingOperationRefresh.refresh(
                gateway: gateway,
                memoryStore: memoryStore,
                ownerUserID: operation.ownerUserID
            )
            return .succeeded
        } catch {
            guard MemoryPendingOperationRefresh.isMemoryConflict(error) else {
                throw error
            }

            try await memoryStore.markConflict(
                ownerUserID: operation.ownerUserID,
                memoryID: payload.memoryID,
                reason: "Memory create conflict"
            )
            return .terminalFailure("Memory create conflict")
        }
    }
}

struct UpdateMemoryPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateMemory

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing update memory payload")
        }

        let payload = try JSONDecoder().decode(UpdateMemoryOperationPayload.self, from: requestData)

        do {
            _ = try await gateway.updateMemory(payload, operation: operation.operation)
            try await MemoryPendingOperationRefresh.refresh(
                gateway: gateway,
                memoryStore: memoryStore,
                ownerUserID: operation.ownerUserID
            )
            return .succeeded
        } catch {
            guard MemoryPendingOperationRefresh.isMemoryConflict(error) else {
                throw error
            }

            try await memoryStore.markConflict(
                ownerUserID: operation.ownerUserID,
                memoryID: payload.memoryID,
                reason: "Memory revision conflict"
            )
            return .terminalFailure("Memory revision conflict")
        }
    }
}

struct HideMemoryPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .hideMemory

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing hide memory payload")
        }

        let payload = try JSONDecoder().decode(HideMemoryOperationPayload.self, from: requestData)

        do {
            _ = try await gateway.hideMemory(payload, operation: operation.operation)
            try await MemoryPendingOperationRefresh.refresh(
                gateway: gateway,
                memoryStore: memoryStore,
                ownerUserID: operation.ownerUserID
            )
            return .succeeded
        } catch {
            guard MemoryPendingOperationRefresh.isMemoryConflict(error) else {
                throw error
            }

            try await memoryStore.markConflict(
                ownerUserID: operation.ownerUserID,
                memoryID: payload.memoryID,
                reason: "Memory revision conflict"
            )
            return .terminalFailure("Memory revision conflict")
        }
    }
}

struct UpsertMemoryNotePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .upsertMemoryNote

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing upsert memory note payload")
        }

        let payload = try JSONDecoder().decode(UpsertMemoryNoteOperationPayload.self, from: requestData)

        do {
            _ = try await gateway.upsertMemoryNote(payload, operation: operation.operation)
            try await MemoryPendingOperationRefresh.refresh(
                gateway: gateway,
                memoryStore: memoryStore,
                ownerUserID: operation.ownerUserID
            )
            return .succeeded
        } catch {
            guard MemoryPendingOperationRefresh.isMemoryConflict(error) else {
                throw error
            }

            try await memoryStore.markConflict(
                ownerUserID: operation.ownerUserID,
                memoryID: payload.memoryID,
                reason: "Memory note revision conflict"
            )
            return .terminalFailure("Memory note revision conflict")
        }
    }
}

struct AttachMemoryMediaPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .attachMemoryMedia

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing attach memory media payload")
        }

        let payload = try JSONDecoder().decode(AttachMemoryMediaOperationPayload.self, from: requestData)
        _ = try await gateway.attachMemoryMedia(payload, operation: operation.operation)
        try await MemoryPendingOperationRefresh.refresh(
            gateway: gateway,
            memoryStore: memoryStore,
            ownerUserID: operation.ownerUserID
        )
        return .succeeded
    }
}

struct RemoveMemoryMediaPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .removeMemoryMedia

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing remove memory media payload")
        }

        let payload = try JSONDecoder().decode(RemoveMemoryMediaOperationPayload.self, from: requestData)
        _ = try await gateway.removeMemoryMedia(payload, operation: operation.operation)
        try await MemoryPendingOperationRefresh.refresh(
            gateway: gateway,
            memoryStore: memoryStore,
            ownerUserID: operation.ownerUserID
        )
        return .succeeded
    }
}

struct CreateMemoryThreadMessagePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createMemoryThreadWithMessage

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing memory thread message payload")
        }

        let payload = try JSONDecoder().decode(CreateMemoryThreadMessageOperationPayload.self, from: requestData)
        _ = try await gateway.createMemoryThreadWithMessage(payload, operation: operation.operation)
        try await MemoryPendingOperationRefresh.refresh(
            gateway: gateway,
            memoryStore: memoryStore,
            ownerUserID: operation.ownerUserID
        )
        return .succeeded
    }
}

private enum MemoryPendingOperationRefresh {
    nonisolated static func refresh(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting,
        ownerUserID: UUID,
        pageSize: Int = 100
    ) async throws {
        var cursor = SyncCursor()

        while true {
            let rows = try await gateway.loadMemories(
                updatedAfter: cursor.updatedAt,
                cursorMemoryID: cursor.tieID,
                limit: pageSize
            )

            guard !rows.isEmpty else {
                return
            }

            try await memoryStore.saveRemote(
                rows,
                ownerUserID: ownerUserID,
                preserveDirtyRecords: false
            )

            guard let last = rows.last, rows.count == pageSize else {
                return
            }

            cursor = SyncCursor(updatedAt: last.syncUpdatedAt, tieID: last.memoryID)
        }
    }

    nonisolated static func isMemoryConflict(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("revision conflict") || description.contains("40001")
    }
}
