import Foundation

/// The visit and list backend functions (`backend/convex/visits.ts`). Each write returns the
/// row as stored, or nil when it is gone.
nonisolated protocol VisitsGateway: Sendable {
    func saveVisit(_ visit: Visit, operation: SyncClientOperation) async throws -> Visit?
    func deleteVisit(id: UUID, operation: SyncClientOperation) async throws
    func saveItem(_ payload: SaveTogetherItemPayload, operation: SyncClientOperation) async throws
        -> RemoteTogetherItem?
    func setItemDone(_ payload: SetTogetherItemDonePayload, operation: SyncClientOperation) async throws
        -> RemoteTogetherItem?
    func deleteItem(id: UUID, operation: SyncClientOperation) async throws
}

nonisolated struct LiveVisitsGateway: VisitsGateway {
    let client: PaeoniaConvexClient

    func saveVisit(_ visit: Visit, operation: SyncClientOperation) async throws -> Visit? {
        try await client.mutation("visits:save_visit", args: SaveVisitRequest(visit: visit, operation: operation))
    }

    func deleteVisit(id: UUID, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "visits:delete_visit",
            args: IDRequest(key: "p_visit_id", id: id, operation: operation)
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

nonisolated private struct SaveVisitRequest: Encodable {
    let visit: Visit
    let operation: SyncClientOperation

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArgumentKey.self)
        try container.encode(visit.id, forKey: ArgumentKey("p_visit_id"))
        try container.encode(visit.startDate, forKey: ArgumentKey("p_start_date"))
        try container.encode(visit.endDate, forKey: ArgumentKey("p_end_date"))
        // `null` removes the place, so it is sent rather than left out.
        try container.encode(visit.place, forKey: ArgumentKey("p_place"))
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
