import Foundation

/// One queued write, decoded from its pending operation.
nonisolated enum VisitsWrite: Equatable, Sendable {
    case saveVisit(SaveVisitPayload)
    case deleteVisit(UUID)
    case saveItem(SaveTogetherItemPayload)
    case setItemDone(SetTogetherItemDonePayload)
    case deleteItem(UUID)

    init?(_ operation: PendingSyncOperationSnapshot) {
        guard let data = operation.requestData, let kind = operation.operationKind else { return nil }
        let write: Self? = switch kind {
        case .saveVisit: Self.decode(SaveVisitPayload.self, data).map(Self.saveVisit)
        case .deleteVisit: Self.decode(VisitIDPayload.self, data).map { .deleteVisit($0.id) }
        case .saveTogetherItem: Self.decode(SaveTogetherItemPayload.self, data).map(Self.saveItem)
        case .setTogetherItemDone: Self.decode(SetTogetherItemDonePayload.self, data).map(Self.setItemDone)
        case .deleteTogetherItem: Self.decode(VisitIDPayload.self, data).map { .deleteItem($0.id) }
        default: nil
        }
        guard let write else { return nil }
        self = write
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    static let operationKinds: [SyncPendingOperationKind] = [
        .saveVisit, .deleteVisit, .saveTogetherItem, .setTogetherItemDone, .deleteTogetherItem,
    ]

    /// The list item this write adds when the server doesn't have it yet.
    var addedItemID: UUID? {
        switch self {
        case let .saveItem(payload): payload.id
        case let .setItemDone(payload): payload.id
        case .saveVisit, .deleteVisit, .deleteItem: nil
        }
    }

    /// What the person loses when the server refuses this write for good. Nil for a delete.
    var refusal: VisitsRefusal? {
        switch self {
        case let .saveVisit(payload): .visit(payload.visit)
        case let .saveItem(payload): .item(title: payload.title)
        case let .setItemDone(payload): .item(title: payload.title)
        case .deleteVisit, .deleteItem: nil
        }
    }
}

/// A visit field an edit may change.
nonisolated enum VisitField: String, Codable, Sendable {
    case startDate
    case endDate
    case place
}

/// `visits:save_visit`. A new visit sends every field. An edit sends only `changes`, so a
/// field the partner changed in the meantime keeps their change.
nonisolated struct SaveVisitPayload: Codable, Equatable, Sendable {
    /// The visit as this phone shows it after the save.
    let visit: Visit
    let changes: Set<VisitField>

    /// The save of `visit`. Its changes are the fields that differ from `server`, the
    /// server's copy, and the fields a save still in `pending` changes, which this save
    /// replaces when it arrives first.
    init(_ visit: Visit, server: Visit?, pending: [VisitsWrite]) {
        self.visit = visit
        guard let server else {
            changes = [.startDate, .endDate, .place]
            return
        }
        var changes = Set<VisitField>()
        if visit.startDate != server.startDate { changes.insert(.startDate) }
        if visit.endDate != server.endDate { changes.insert(.endDate) }
        if visit.place != server.place { changes.insert(.place) }
        for case let .saveVisit(queued) in pending where queued.visit.id == visit.id {
            changes.formUnion(queued.changes)
        }
        self.changes = changes
    }

    /// `visit` with this save's changes.
    func applied(to visit: Visit) -> Visit {
        var visit = visit
        if changes.contains(.startDate) { visit.startDate = self.visit.startDate }
        if changes.contains(.endDate) { visit.endDate = self.visit.endDate }
        if changes.contains(.place) { visit.place = self.visit.place }
        return visit
    }
}

/// `visits:delete_visit` and `visits:delete_together_item`.
nonisolated struct VisitIDPayload: Codable, Equatable, Sendable {
    let id: UUID
}

/// `visits:save_together_item`.
nonisolated struct SaveTogetherItemPayload: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
}

/// `visits:set_together_item_done`. It carries the title, because it adds the item when it
/// reaches the server before the item's add.
nonisolated struct SetTogetherItemDonePayload: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let isDone: Bool
}
