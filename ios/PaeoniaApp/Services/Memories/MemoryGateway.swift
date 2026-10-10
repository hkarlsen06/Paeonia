import Foundation

protocol MemoryGateway: Actor {
    func loadMemories(
        updatedAfter: Date?,
        cursorMemoryID: UUID?,
        limit: Int
    ) async throws -> [MemoryRemoteRow]
    func createMemory(
        _ payload: CreateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID
    func updateMemory(
        _ payload: UpdateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse?
    func hideMemory(
        _ payload: HideMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse?
    func upsertMemoryNote(
        _ payload: UpsertMemoryNoteOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryNoteRevisionResponse?
    func attachMemoryMedia(
        _ payload: AttachMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> [UUID]
    func removeMemoryMedia(
        _ payload: RemoveMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID
    func createMemoryThreadWithMessage(
        _ payload: CreateMemoryThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryThreadMessageResponse?
}

actor LiveMemoryGateway: MemoryGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func loadMemories(
        updatedAfter: Date?,
        cursorMemoryID: UUID?,
        limit: Int
    ) async throws -> [MemoryRemoteRow] {
        try await client.mutation(
            "memories:get_memories",
            args: GetMemoriesRequest(
                updatedAfter: updatedAfter,
                cursorMemoryID: cursorMemoryID,
                limit: limit
            )
        )
    }

    func createMemory(
        _ payload: CreateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID {
        try await PaeoniaSignedIn.require(isSignedIn)

        return try await client.mutation(
            "memories:create_memory",
            args: CreateMemoryRequest(payload: payload, operation: operation)
        )
    }

    func updateMemory(
        _ payload: UpdateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse? {
        try await PaeoniaSignedIn.require(isSignedIn)

        let rows: [MemoryRevisionResponse] = try await client.mutation(
            "memories:update_memory",
            args: UpdateMemoryRequest(payload: payload, operation: operation)
        )
        return rows.first
    }

    func hideMemory(
        _ payload: HideMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse? {
        try await PaeoniaSignedIn.require(isSignedIn)

        let rows: [MemoryRevisionResponse] = try await client.mutation(
            "memories:hide_memory",
            args: HideMemoryRequest(payload: payload, operation: operation)
        )
        return rows.first
    }

    func upsertMemoryNote(
        _ payload: UpsertMemoryNoteOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryNoteRevisionResponse? {
        try await PaeoniaSignedIn.require(isSignedIn)

        let rows: [MemoryNoteRevisionResponse] = try await client.mutation(
            "memories:upsert_memory_note",
            args: UpsertMemoryNoteRequest(payload: payload, operation: operation)
        )
        return rows.first
    }

    func attachMemoryMedia(
        _ payload: AttachMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> [UUID] {
        try await PaeoniaSignedIn.require(isSignedIn)

        return try await client.mutation(
            "memories:attach_memory_media",
            args: AttachMemoryMediaRequest(payload: payload, operation: operation)
        )
    }

    func removeMemoryMedia(
        _ payload: RemoveMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID {
        try await PaeoniaSignedIn.require(isSignedIn)

        return try await client.mutation(
            "memories:remove_memory_media",
            args: RemoveMemoryMediaRequest(payload: payload, operation: operation)
        )
    }

    func createMemoryThreadWithMessage(
        _ payload: CreateMemoryThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryThreadMessageResponse? {
        try await PaeoniaSignedIn.require(isSignedIn)

        let rows: [MemoryThreadMessageResponse] = try await client.mutation(
            "threads:create_memory_thread_with_message",
            args: CreateMemoryThreadMessageRequest(payload: payload, operation: operation)
        )
        return rows.first
    }
}
