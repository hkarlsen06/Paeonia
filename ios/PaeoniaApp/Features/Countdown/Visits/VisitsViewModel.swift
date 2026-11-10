import Foundation
import Observation

/// The couple's visits and their list for the Us tab card, the visit screen and the dates
/// timeline. The app puts one in the environment.
///
/// `state` is the cached server state with this phone's queued writes laid over it, so an
/// edit shows at once, survives a relaunch while offline, and either partner's change arrives
/// through the live feed. Every write goes through the pending operations.
@Observable
final class VisitsViewModel {
    private(set) var state = CoupleVisits()
    private(set) var error: VisitsError?
    /// `state` holds this person's cached visits, so no visits means there are none.
    private(set) var hasLoaded = false

    @ObservationIgnored private let cache: any VisitsCaching
    @ObservationIgnored private let pendingOperationStore: any PendingSyncOperationPersisting
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private var syncAfterLocalChange: @MainActor () async -> Void = {}
    @ObservationIgnored private var ownerUserID: UUID?
    /// Drops a reload that finished after a newer one started or the account changed.
    @ObservationIgnored private var reloadGeneration = 0

    init(
        cache: (any VisitsCaching)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.cache = cache ?? FileVisitsCache.shared
        self.pendingOperationStore = pendingOperationStore
            ?? SwiftDataPendingSyncOperationRepository(container: PaeoniaLocalStore.shared.container)
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    func configure(ownerUserID: UUID?) async {
        if self.ownerUserID != ownerUserID {
            state = CoupleVisits()
            hasLoaded = false
        }
        self.ownerUserID = ownerUserID
        await reload()
    }

    func setSyncAfterLocalChange(_ handler: @escaping @MainActor () async -> Void) {
        syncAfterLocalChange = handler
    }

    /// Follows the live feed and the queue: a partner's edit, a confirmed send, or a write
    /// the server refused for good, which then drops out of the overlay.
    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .visits, .pendingOperations) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await reload()
        }
    }

    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        guard let ownerUserID else {
            state = CoupleVisits()
            return
        }
        let server = await cache.visits(ownerUserID: ownerUserID)
        var operations: [PendingSyncOperationSnapshot] = []
        for kind in VisitsWrite.operationKinds {
            let inFlight = try? await pendingOperationStore.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
            operations += inFlight ?? []
        }
        guard generation == reloadGeneration, self.ownerUserID == ownerUserID else { return }
        let writes = operations
            .sorted { $0.operation.clientSequence < $1.operation.clientSequence }
            .compactMap(VisitsWrite.init)
        state = server.applying(writes)
        hasLoaded = true
    }

    /// Plans a visit with `newID` when `id` is nil, otherwise edits that one. The editor
    /// refuses a last day before the first, so this never queues one.
    @discardableResult
    func saveVisit(
        id: UUID?,
        from start: Date,
        to end: Date,
        place: MemoryPlace?,
        calendar: Calendar = .current,
        newID: UUID = UUID()
    ) async -> Bool {
        let startDate = PairingStartDate(date: start, calendar: calendar).rawValue
        let endDate = PairingStartDate(date: end, calendar: calendar).rawValue
        guard endDate >= startDate else { return false }
        // A write the server refuses for good would drop out of the list without a word.
        guard id != nil || state.visits.count < Visit.maxCount else {
            error = .visitLimit
            return false
        }
        let visit = Visit(id: id ?? newID, startDate: startDate, endDate: endDate, place: place)
        return await enqueue(.saveVisit(visit), kind: .saveVisit, payload: visit)
    }

    @discardableResult
    func deleteVisit(id: UUID) async -> Bool {
        await enqueue(.deleteVisit(id), kind: .deleteVisit, payload: VisitIDPayload(id: id))
    }

    @discardableResult
    func addItem(_ title: String, newID: UUID = UUID()) async -> Bool {
        let title = String(
            title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TogetherListItem.maxTitleLength)
        )
        guard !title.isEmpty else { return false }
        guard state.items.count < TogetherListItem.maxCount else {
            error = .listFull
            return false
        }
        let payload = SaveTogetherItemPayload(id: newID, title: title)
        return await enqueue(.saveItem(payload), kind: .saveTogetherItem, payload: payload)
    }

    @discardableResult
    func setItemDone(id: UUID, _ isDone: Bool) async -> Bool {
        let payload = SetTogetherItemDonePayload(id: id, isDone: isDone)
        return await enqueue(.setItemDone(payload), kind: .setTogetherItemDone, payload: payload)
    }

    @discardableResult
    func deleteItem(id: UUID) async -> Bool {
        await enqueue(.deleteItem(id), kind: .deleteTogetherItem, payload: VisitIDPayload(id: id))
    }

    func clearError() {
        error = nil
    }

    private func enqueue(_ write: VisitsWrite, kind: SyncPendingOperationKind, payload: some Encodable) async -> Bool {
        guard let ownerUserID, let data = try? JSONEncoder().encode(payload) else {
            error = .saveFailed
            return false
        }
        do {
            try await pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: ownerUserID,
                    operation: operationProvider.makeOperation(),
                    operationKind: kind,
                    idempotencyScope: "visits",
                    requestData: data
                )
            )
        } catch {
            self.error = .saveFailed
            return false
        }
        state = state.applying([write])
        // Its own task, so closing the editor doesn't cancel the send.
        let sync = syncAfterLocalChange
        Task { await sync() }
        return true
    }
}

nonisolated enum VisitsError: Equatable, Sendable {
    case saveFailed
    case visitLimit
    case listFull

    var message: String {
        switch self {
        case .saveFailed:
            String(localized: .visitErrorSaveFailed)
        case .visitLimit:
            String(localized: .visitErrorVisitLimit(Visit.maxCount.formatted()))
        case .listFull:
            String(localized: .visitErrorListFull(TogetherListItem.maxCount.formatted()))
        }
    }
}
