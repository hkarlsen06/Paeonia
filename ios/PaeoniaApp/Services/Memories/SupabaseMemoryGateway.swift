import Foundation
import Supabase

protocol SupabaseMemoryGateway: Actor {
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

actor LiveSupabaseMemoryGateway: SupabaseMemoryGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadMemories(
        updatedAfter: Date?,
        cursorMemoryID: UUID?,
        limit: Int
    ) async throws -> [MemoryRemoteRow] {
        try await client
            .rpc(
                "get_memories",
                params: GetMemoriesRequest(
                    updatedAfter: updatedAfter,
                    cursorMemoryID: cursorMemoryID,
                    limit: limit
                )
            )
            .execute()
            .value
    }

    func createMemory(
        _ payload: CreateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID {
        _ = try await client.auth.session

        return try await client
            .rpc(
                "create_memory",
                params: CreateMemoryRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
    }

    func updateMemory(
        _ payload: UpdateMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse? {
        _ = try await client.auth.session

        let rows: [MemoryRevisionResponse] = try await client
            .rpc(
                "update_memory",
                params: UpdateMemoryRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
        return rows.first
    }

    func hideMemory(
        _ payload: HideMemoryOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryRevisionResponse? {
        _ = try await client.auth.session

        let rows: [MemoryRevisionResponse] = try await client
            .rpc(
                "hide_memory",
                params: HideMemoryRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
        return rows.first
    }

    func upsertMemoryNote(
        _ payload: UpsertMemoryNoteOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryNoteRevisionResponse? {
        _ = try await client.auth.session

        let rows: [MemoryNoteRevisionResponse] = try await client
            .rpc(
                "upsert_memory_note",
                params: UpsertMemoryNoteRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
        return rows.first
    }

    func attachMemoryMedia(
        _ payload: AttachMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> [UUID] {
        _ = try await client.auth.session

        return try await client
            .rpc(
                "attach_memory_media",
                params: AttachMemoryMediaRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
    }

    func removeMemoryMedia(
        _ payload: RemoveMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) async throws -> UUID {
        _ = try await client.auth.session

        return try await client
            .rpc(
                "remove_memory_media",
                params: RemoveMemoryMediaRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
    }

    func createMemoryThreadWithMessage(
        _ payload: CreateMemoryThreadMessageOperationPayload,
        operation: SyncClientOperation
    ) async throws -> MemoryThreadMessageResponse? {
        _ = try await client.auth.session

        let rows: [MemoryThreadMessageResponse] = try await client
            .rpc(
                "create_memory_thread_with_message",
                params: CreateMemoryThreadMessageRequest(payload: payload, operation: operation)
            )
            .execute()
            .value
        return rows.first
    }
}
