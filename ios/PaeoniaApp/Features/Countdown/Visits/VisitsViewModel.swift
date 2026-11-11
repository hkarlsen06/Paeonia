import Foundation
import Observation

/// The couple's visits and their list for the Us tab card, the visit screen and the dates
/// timeline. The app puts one in the environment.
///
/// `state` is the cached server state with this phone's queued writes laid over it, so an
/// edit shows at once, survives a relaunch while offline, and either partner's change arrives
/// through the live feed. Every write goes through the pending operations. A write the server
/// refuses for good comes back as `error`, and a refused list item goes back into `itemDraft`.
/// The refusal stays in the cache until the person dismisses the message that names it.
@Observable
final class VisitsViewModel {
    private(set) var state = CoupleVisits()
    private(set) var error: VisitsError?
    /// `state` holds this person's cached visits, so no visits means there are none.
    private(set) var hasLoaded = false
    /// The text in the visit screen's add field. A refused add leaves it there.
    var itemDraft = ""
    /// An error about the list while the visit screen shows it. The screen draws it under the
    /// add field, where a banner would cover the text the field keeps.
    private(set) var listError: VisitsError?
    /// Set by the visit screen while it shows the list.
    @ObservationIgnored var isListShown = false
    /// The day the "When do you meet next?" card comes back after the person hid it.
    private(set) var promptReturnDay: LockScreenCalendarDate?

    @ObservationIgnored private let cache: any VisitsCaching
    @ObservationIgnored private let pendingOperationStore: any PendingSyncOperationPersisting
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private var syncAfterLocalChange: @MainActor () async -> Void = {}
    @ObservationIgnored private var ownerUserID: UUID?
    /// The server's state and this phone's queued writes, which `state` lays over it.
    @ObservationIgnored private var server = CoupleVisits()
    @ObservationIgnored private var pending: [VisitsWrite] = []
    /// Whether the app is on screen. Refusals wait in the cache until it is, so the banner
    /// and the refilled add field don't come while nobody can see them.
    @ObservationIgnored private var isActive = false
    /// The refusals the banner names, and the ones the visit screen's list error names. They
    /// stay in the cache until the person dismisses that message. A message for a later refusal
    /// names these again, because a new banner takes the place of the one on screen.
    @ObservationIgnored private var bannerRefusals: [VisitsRefusal] = []
    @ObservationIgnored private var listRefusals: [VisitsRefusal] = []
    /// Drops a reload that finished after a newer one started or the account changed.
    @ObservationIgnored private var reloadGeneration = 0

    static let promptHiddenDays = 30

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
            server = CoupleVisits()
            pending = []
            bannerRefusals = []
            listRefusals = []
            hasLoaded = false
            promptReturnDay = nil
            // Text typed by the person who was signed in before.
            if self.ownerUserID != nil { itemDraft = "" }
        }
        self.ownerUserID = ownerUserID
        await reload()
    }

    func setActive(_ isActive: Bool) async {
        self.isActive = isActive
        if isActive { await reload() }
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
            server = CoupleVisits()
            pending = []
            return
        }
        let local = await cache.state(ownerUserID: ownerUserID)
        var operations: [PendingSyncOperationSnapshot] = []
        for kind in VisitsWrite.operationKinds {
            let inFlight = try? await pendingOperationStore.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
            operations += inFlight ?? []
        }
        guard generation == reloadGeneration, self.ownerUserID == ownerUserID else { return }
        let writes = operations
            .sorted { $0.operation.clientSequence < $1.operation.clientSequence }
            .compactMap(VisitsWrite.init)
        server = local.visits
        pending = writes
        state = server.applying(writes)
        promptReturnDay = local.promptReturnDay
        hasLoaded = true
        if isActive { show(local.refusals) }
    }

    func homeCard(on today: LockScreenCalendarDate, streak: StreakPillState) -> HomeVisitCardState {
        guard hasLoaded else { return .hidden }
        return HomeVisitCardState(
            visits: state,
            on: today,
            restsTogether: streak.restsWhileTogether(on: today),
            promptReturnDay: promptReturnDay
        )
    }

    func hidePrompt(now: Date = Date(), calendar: Calendar = .current) async {
        guard let ownerUserID,
              let returnDate = calendar.date(byAdding: .day, value: Self.promptHiddenDays, to: now)
        else { return }
        let returnDay = LockScreenCalendarDate(containing: returnDate, in: calendar)
        promptReturnDay = returnDay
        await cache.setPromptReturnDay(returnDay, ownerUserID: ownerUserID)
    }

    /// Plans a visit with `newID` when `id` is nil, otherwise edits that one. An edit sends
    /// only the fields that changed. The editor refuses a last day before the first, so this
    /// never queues one.
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
        let normalizedPlace: MemoryPlace?
        do {
            normalizedPlace = try MemoryDataService.normalizedPlace(place)
        } catch {
            self.error = .saveFailed
            return false
        }
        let visit = Visit(id: id ?? newID, startDate: startDate, endDate: endDate, place: normalizedPlace)
        // A write the server refuses for good would only come back later, after the editor closed.
        guard !state.isFull(saving: visit, at: Date()) else {
            error = .visitLimit
            return false
        }
        let payload = SaveVisitPayload(visit, server: server.visits.first { $0.id == visit.id }, pending: pending)
        return await enqueue(.saveVisit(payload), kind: .saveVisit, payload: payload)
    }

    @discardableResult
    func deleteVisit(id: UUID) async -> Bool {
        await enqueue(.deleteVisit(id), kind: .deleteVisit, payload: VisitIDPayload(id: id))
    }

    /// Adds `itemDraft` to the list and empties the field. A full list keeps the text in it.
    @discardableResult
    func addItem(newID: UUID = UUID()) async -> Bool {
        let draft = itemDraft
        guard let title = TogetherListItem.title(draft) else { return false }
        guard state.items.count < TogetherListItem.maxCount else {
            report(.listFull)
            return false
        }
        let payload = SaveTogetherItemPayload(id: newID, title: title)
        guard await enqueue(.saveItem(payload), kind: .saveTogetherItem, payload: payload) else { return false }
        if itemDraft == draft { itemDraft = "" }
        // Adding again answers a message about a refused item.
        await clearListError()
        return true
    }

    @discardableResult
    func setItemDone(_ item: TogetherListItem, _ isDone: Bool) async -> Bool {
        let payload = SetTogetherItemDonePayload(id: item.id, title: item.title, isDone: isDone)
        return await enqueue(.setItemDone(payload), kind: .setTogetherItemDone, payload: payload)
    }

    @discardableResult
    func deleteItem(id: UUID) async -> Bool {
        await enqueue(.deleteItem(id), kind: .deleteTogetherItem, payload: VisitIDPayload(id: id))
    }

    func clearError() {
        error = nil
    }

    /// Called when the person types in the add field, adds an item or leaves the visit screen.
    /// The list error goes, and the refusals it named leave the cache.
    func clearListError() async {
        listError = nil
        let named = listRefusals
        listRefusals = []
        await forget(named)
    }

    /// Called when the person dismissed the banner that named refusals, so they leave the cache.
    func refusalBannerDismissed() async {
        let named = bannerRefusals
        bannerRefusals = []
        await forget(named)
    }

    /// Called when another banner took the place of the one that named refusals. Nobody
    /// dismissed it, so they stay in the cache and the next reload shows them again.
    func refusalBannerReplaced() {
        bannerRefusals = []
    }

    private func forget(_ refusals: [VisitsRefusal]) async {
        guard let ownerUserID, !refusals.isEmpty else { return }
        // Drops a reload that read the cache before they left it, which would show them again.
        reloadGeneration &+= 1
        await cache.removeRefusals(refusals, ownerUserID: ownerUserID)
        await reload()
    }

    private func report(_ error: VisitsError) {
        if isListShown, error.isAboutTheList {
            listError = error
        } else {
            self.error = error
        }
    }

    /// Tells the person about every write the server refused that is still in the cache, and
    /// puts a refused item back in the add field when it is empty. While the visit screen is
    /// open, refused items show under its add field and refused visits in the banner. Elsewhere
    /// one banner names both. Nothing new shows while the same refusals are still on screen.
    private func show(_ refusals: [VisitsRefusal]) {
        var titles: [String] = []
        var visits: [Visit] = []
        for refusal in refusals {
            switch refusal {
            case let .item(title): titles.append(title)
            case let .visit(refused): visits.append(refused)
            }
        }
        let forList = isListShown ? titles.map { VisitsRefusal.item(title: $0) } : []
        let forBanner = forList.isEmpty ? refusals : visits.map { VisitsRefusal.visit($0) }
        let listChanged = forList != listRefusals
        let bannerChanged = forBanner != bannerRefusals
        listRefusals = forList
        bannerRefusals = forBanner
        guard listChanged || bannerChanged else { return }
        if let title = titles.first, itemDraft.isEmpty {
            itemDraft = title
        }
        if listChanged, !forList.isEmpty {
            listError = .refused(items: titles, visits: [])
        }
        if bannerChanged, !forBanner.isEmpty {
            error = .refused(items: forList.isEmpty ? titles : [], visits: visits)
        }
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
        pending.append(write)
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
    /// The server refused these for good: list items, which aren't on the list, and visits.
    case refused(items: [String], visits: [Visit])

    /// Whether the message names refused writes, which stay on the phone until the person
    /// dismisses it.
    var namesRefusals: Bool {
        if case .refused = self { true } else { false }
    }

    var isAboutTheList: Bool {
        switch self {
        case .listFull: true
        case let .refused(_, visits): visits.isEmpty
        case .saveFailed, .visitLimit: false
        }
    }

    var message: String {
        switch self {
        case .saveFailed:
            String(localized: .visitErrorSaveFailed)
        case .visitLimit:
            String(localized: .visitErrorVisitLimit(Visit.maxOpenCount.formatted()))
        case .listFull:
            String(localized: .visitErrorListFull(TogetherListItem.maxCount.formatted()))
        case let .refused(items, visits):
            [Self.itemsNotAdded(items), Self.visitsNotSaved(visits)].compactMap(\.self).joined(separator: " ")
        }
    }

    private static func itemsNotAdded(_ titles: [String]) -> String? {
        guard !titles.isEmpty else { return nil }
        return String(localized: .visitErrorItemsNotAdded(titles.formatted(.list(type: .and))))
    }

    private static func visitsNotSaved(_ visits: [Visit]) -> String? {
        let ranges = visits.map { $0.dateRangeText() }
        guard let first = ranges.first else { return nil }
        guard ranges.count > 1 else { return String(localized: .visitErrorVisitNotSaved(first)) }
        return String(localized: .visitErrorVisitsNotSaved(ranges.formatted(.list(type: .and))))
    }
}
