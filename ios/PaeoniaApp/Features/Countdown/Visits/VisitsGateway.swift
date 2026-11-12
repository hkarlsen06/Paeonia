import Foundation

/// The visit and list backend functions (`backend/convex/visits.ts`). Each write returns the
/// row as stored, or nil when it is gone.
nonisolated protocol VisitsGateway: Sendable {
    func saveVisit(_ payload: SaveVisitPayload, operation: SyncClientOperation) async throws -> Visit?
    func deleteVisit(id: UUID, operation: SyncClientOperation) async throws
    func dismissMemoryPrompt(visitID: UUID, operation: SyncClientOperation) async throws -> Visit?
    func saveItem(_ payload: SaveTogetherItemPayload, operation: SyncClientOperation) async throws
        -> RemoteTogetherItem?
    func setItemDone(_ payload: SetTogetherItemDonePayload, operation: SyncClientOperation) async throws
        -> RemoteTogetherItem?
    func deleteItem(id: UUID, operation: SyncClientOperation) async throws
}

nonisolated struct LiveVisitsGateway: VisitsGateway {
    let client: PaeoniaConvexClient

    func saveVisit(_ payload: SaveVisitPayload, operation: SyncClientOperation) async throws -> Visit? {
        try await client.mutation("visits:save_visit", args: SaveVisitRequest(payload: payload, operation: operation))
    }

    func deleteVisit(id: UUID, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "visits:delete_visit",
            args: IDRequest(key: "p_visit_id", id: id, operation: operation)
        )
    }

    func dismissMemoryPrompt(visitID: UUID, operation: SyncClientOperation) async throws -> Visit? {
        try await client.mutation(
            "visits:dismiss_visit_memory_prompt",
            args: IDRequest(key: "p_visit_id", id: visitID, operation: operation)
        )
    }

    func saveItem(
        _ payload: SaveTogetherItemPayload,
        operation: SyncClientOperation
    ) async throws -> RemoteTogetherItem? {
        try await client.mutation(
            "visits:save_together_item",
            args: SaveItemRequest(payload: payload, operation: operation)
        )
    }

    func setItemDone(
        _ payload: SetTogetherItemDonePayload,
        operation: SyncClientOperation
    ) async throws -> RemoteTogetherItem? {
        try await client.mutation(
            "visits:set_together_item_done",
            args: SetItemDoneRequest(payload: payload, operation: operation)
        )
    }

    func deleteItem(id: UUID, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "visits:delete_together_item",
            args: IDRequest(key: "p_item_id", id: id, operation: operation)
        )
    }
}

nonisolated private struct ArgumentKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

/// Leaves out the fields the save doesn't change, so the server keeps them.
nonisolated private struct SaveVisitRequest: Encodable {
    let payload: SaveVisitPayload
    let operation: SyncClientOperation

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArgumentKey.self)
        let visit = payload.visit
        try container.encode(visit.id, forKey: ArgumentKey("p_visit_id"))
        if payload.changes.contains(.startDate) {
            try container.encode(visit.startDate, forKey: ArgumentKey("p_start_date"))
        }
        if payload.changes.contains(.endDate) {
            try container.encode(visit.endDate, forKey: ArgumentKey("p_end_date"))
        }
        if payload.changes.contains(.place) {
            // `null` removes the place, and a missing key keeps it.
            try container.encode(visit.place, forKey: ArgumentKey("p_place"))
        }
        try ClientOperationFields(operation).encode(to: encoder)
    }
}

nonisolated private struct SaveItemRequest: Encodable {
    let payload: SaveTogetherItemPayload
    let operation: SyncClientOperation

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArgumentKey.self)
        try container.encode(payload.id, forKey: ArgumentKey("p_item_id"))
        try container.encode(payload.title, forKey: ArgumentKey("p_title"))
        try ClientOperationFields(operation).encode(to: encoder)
    }
}

nonisolated private struct SetItemDoneRequest: Encodable {
    let payload: SetTogetherItemDonePayload
    let operation: SyncClientOperation

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArgumentKey.self)
        try container.encode(payload.id, forKey: ArgumentKey("p_item_id"))
        try container.encode(payload.title, forKey: ArgumentKey("p_title"))
        try container.encode(payload.isDone, forKey: ArgumentKey("p_done"))
        try ClientOperationFields(operation).encode(to: encoder)
    }
}

nonisolated private struct IDRequest: Encodable {
    let key: String
    let id: UUID
    let operation: SyncClientOperation

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArgumentKey.self)
        try container.encode(id, forKey: ArgumentKey(key))
        try ClientOperationFields(operation).encode(to: encoder)
    }
}
