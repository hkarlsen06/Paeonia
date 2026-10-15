import Foundation
import Observation

/// The couple's countdowns and birthdays for the milestones timeline and the Home tile.
///
/// `dates` is the cached server state with this phone's queued writes laid over it, so
/// an edit shows at once, survives a relaunch while offline, and either partner's change
/// arrives through the live feed. Every write goes through the pending operations.
@MainActor
@Observable
final class CoupleDatesViewModel {
    private(set) var dates = CoupleDates()
    private(set) var error: RelationshipMilestoneError?

    @ObservationIgnored private let cache: any CoupleDatesCaching
    @ObservationIgnored private let pendingOperationStore: any PendingSyncOperationPersisting
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private var syncAfterLocalChange: @MainActor () async -> Void = {}
    @ObservationIgnored private var ownerUserID: UUID?
    /// Drops a reload that finished after a newer one started or the account changed.
    @ObservationIgnored private var reloadGeneration = 0

    init(
        cache: (any CoupleDatesCaching)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.cache = cache ?? FileCoupleDatesCache.shared
        self.pendingOperationStore = pendingOperationStore ?? Self.defaultPendingOperationStore()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    func configure(ownerUserID: UUID?) async {
        if self.ownerUserID != ownerUserID {
            dates = CoupleDates()
        }
        self.ownerUserID = ownerUserID
        await reload()
    }

    func setSyncAfterLocalChange(_ handler: @escaping @MainActor () async -> Void) {
        syncAfterLocalChange = handler
    }

    /// Follows the live feed and the queue: a partner's edit, a confirmed send, or a
    /// write the server refused for good, which then drops out of the overlay.
    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .coupleDates, .pendingOperations) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await reload()
        }
    }

    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        guard let ownerUserID else {
            dates = CoupleDates()
            return
        }
        let server = await cache.dates(ownerUserID: ownerUserID)
        var operations: [PendingSyncOperationSnapshot] = []
        for kind in CoupleDatesWrite.operationKinds {
            let inFlight = try? await pendingOperationStore.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
            operations += inFlight ?? []
        }
        guard generation == reloadGeneration, self.ownerUserID == ownerUserID else { return }
        let writes = operations
            .sorted { $0.operation.clientSequence < $1.operation.clientSequence }
            .compactMap(CoupleDatesWrite.init)
        dates = server.applying(writes)
    }

    /// Adds a countdown when `id` is nil, otherwise edits that one.
    @discardableResult
    func saveCountdown(id: UUID?, title: String, on day: Date, calendar: Calendar = .current) async -> Bool {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CustomCountdown.maxTitleLength))
        guard !title.isEmpty else { return false }
        // A write the server refuses for good would drop out of the list without a word.
        guard id != nil || dates.countdowns.count < CustomCountdown.maxCount else {
            error = .countdownLimit
            return false
        }
        let countdown = CustomCountdown(
            id: id ?? UUID(),
            title: title,
            targetDate: PairingStartDate(date: day, calendar: calendar).rawValue
        )
        return await enqueue(.save(countdown), kind: .saveCountdown, payload: countdown)
    }

    @discardableResult
    func deleteCountdown(id: UUID) async -> Bool {
        await enqueue(.delete(id), kind: .deleteCountdown, payload: DeleteCountdownPayload(id: id))
    }

    /// Sets `userID`'s birthday, or removes it when `day` is nil.
    @discardableResult
    func setBirthday(_ day: Date?, for userID: UUID, calendar: Calendar = .current) async -> Bool {
        let payload = SetBirthdayPayload(
            userID: userID,
            birthday: day.map { PairingStartDate(date: $0, calendar: calendar).rawValue }
        )
        return await enqueue(.birthday(payload), kind: .setBirthday, payload: payload)
    }

    func clearError() {
        error = nil
    }

    private func enqueue(
        _ write: CoupleDatesWrite,
        kind: SyncPendingOperationKind,
        payload: some Encodable
    ) async -> Bool {
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
                    idempotencyScope: "couple_dates",
                    requestData: data
                )
            )
        } catch {
            self.error = .saveFailed
            return false
        }
        dates = dates.applying([write])
        // Its own task, so closing the editor doesn't cancel the send.
        let sync = syncAfterLocalChange
        Task { await sync() }
        return true
    }

    private static func defaultPendingOperationStore() -> any PendingSyncOperationPersisting {
        if let localStore = PaeoniaLocalStore.shared {
            return SwiftDataPendingSyncOperationRepository(container: localStore.container)
        }
        return InMemoryPendingSyncOperationRepository()
    }
}
