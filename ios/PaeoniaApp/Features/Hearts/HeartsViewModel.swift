import Foundation
import Observation
import SwiftUI

/// Sends and receives the hearts on the Home tab.
///
/// Sending: each tap on the map or the heart row calls `tap()`. Taps wait until
/// they stop for `HeartsTapBatcher.quietPeriod`, then go to the pending operations
/// as one write per batch, so a phone that is offline sends them later.
///
/// Receiving: the live feed keeps the partner's totals in `HeartsCaching`. While
/// Home is on screen, unseen hearts play as one burst, the cache records them as
/// shown, and a second write tells the server.
@MainActor
@Observable
final class HeartsViewModel {
    /// The burst that is playing now. The map and the heart row fly hearts for it.
    private(set) var incomingBurst: HeartsBurst?
    /// "Robin sent you 14 hearts" while a burst plays.
    private(set) var incomingLine: String?

    @ObservationIgnored private let cache: any HeartsCaching
    @ObservationIgnored private let pendingOperationStore: any PendingSyncOperationPersisting
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let announceBurst: @MainActor (String) -> Void
    @ObservationIgnored private var syncAfterLocalChange: @MainActor () async -> Void = {}

    @ObservationIgnored private var ownerUserID: UUID?
    @ObservationIgnored private var partnerName = ""
    @ObservationIgnored private var batcher = HeartsTapBatcher()
    @ObservationIgnored private(set) var flushTask: Task<Void, Never>?
    @ObservationIgnored private var burstTask: Task<Void, Never>?
    @ObservationIgnored private var isHomeVisible = false
    @ObservationIgnored private var isScreenReady = false
    @ObservationIgnored private var isPlaying = false

    /// How long the line stays up. The flying hearts take a little longer.
    static let lineDuration: Duration = .seconds(4)

    init(
        cache: (any HeartsCaching)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        announceBurst: @escaping @MainActor (String) -> Void = HeartsViewModel.playFeedback
    ) {
        self.cache = cache ?? FileHeartsCache.shared
        self.pendingOperationStore = pendingOperationStore ?? Self.defaultPendingOperationStore()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.sleep = sleep
        self.announceBurst = announceBurst
    }

    /// The signed-in person and the partner's name for the line. Names arrive after
    /// launch, so this never reloads anything.
    func configure(ownerUserID: UUID?, partnerName: String) {
        if self.ownerUserID != ownerUserID {
            flushTask?.cancel()
            flushTask = nil
            batcher = HeartsTapBatcher()
            stopBurst()
        }
        self.ownerUserID = ownerUserID
        self.partnerName = partnerName
    }

    func setSyncAfterLocalChange(_ handler: @escaping @MainActor () async -> Void) {
        syncAfterLocalChange = handler
    }

    // MARK: - Sending

    /// One heart to send. The caller plays the flight.
    func tap() {
        guard ownerUserID != nil else { return }
        batcher.tap()
        flushTask?.cancel()
        flushTask = Task { [weak self, sleep] in
            do {
                try await sleep(HeartsTapBatcher.quietPeriod)
            } catch {
                return
            }
            await self?.flushTaps()
        }
    }

    /// Writes the waiting taps to the pending operations, one write per batch, and
    /// starts a send. A new tap cancels the wait for the quiet period, never the send.
    func flushTaps() async {
        guard let ownerUserID else { return }
        let batches = batcher.takeBatches()
        guard !batches.isEmpty else { return }
        for count in batches {
            await enqueue(.sendHearts, payload: HeartsSendPayload(count: count), ownerUserID: ownerUserID)
        }
        requestSync()
    }

    /// Sends the waiting taps without waiting for the quiet period.
    private func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        await flushTaps()
    }

    // MARK: - Receiving

    /// Home appeared or disappeared. Leaving sends the waiting taps at once, so
    /// they do not wait for the person to come back.
    func setHomeVisible(_ isVisible: Bool) {
        isHomeVisible = isVisible
        if isVisible {
            Task { await playIfNeeded() }
        } else {
            stopBurst()
            if batcher.hasPendingTaps {
                Task { await flushNow() }
            }
        }
    }

    /// The app is in front and the launch intro is over. Hearts that arrive earlier wait.
    func setScreenReady(_ isReady: Bool) {
        isScreenReady = isReady
        if isReady {
            Task { await playIfNeeded() }
        } else if batcher.hasPendingTaps {
            Task { await flushNow() }
        }
    }

    /// Follows the hearts cache while Home is on screen.
    func observeStoreChanges() async {
        await playIfNeeded()
        for await change in LocalStoreChanges.changes(in: .hearts) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await playIfNeeded()
        }
    }

    /// Plays the unseen hearts if Home is in front and no burst is playing.
    func playIfNeeded() async {
        guard isHomeVisible, isScreenReady, !isPlaying, let ownerUserID else { return }
        isPlaying = true
        // Read first and mark only what is presented. The read suspends, so check
        // again that the person can still see Home. Hearts that find it hidden stay
        // unseen for the next time.
        let pending = await cache.inbox(ownerUserID: ownerUserID).pendingBurst
        guard let shown = pending, !Task.isCancelled, isHomeVisible, isScreenReady,
              self.ownerUserID == ownerUserID
        else {
            isPlaying = false
            return
        }
        let line = String(localized: .heartsIncomingLine(partnerName, String(localized: .heartsCount(shown.count))))
        incomingBurst = HeartsBurst(count: shown.count)
        incomingLine = line
        announceBurst(line)
        await cache.markShown(upTo: shown.total, ownerUserID: ownerUserID)
        await enqueue(.markHeartsSeen, payload: HeartsSeenPayload(seenTotal: shown.total), ownerUserID: ownerUserID)
        requestSync()

        burstTask = Task { [weak self, sleep] in
            do {
                try await sleep(Self.lineDuration)
            } catch {
                return
            }
            await self?.finishBurst()
        }
    }

    private func finishBurst() async {
        incomingBurst = nil
        incomingLine = nil
        isPlaying = false
        burstTask = nil
        // Hearts that arrived while this burst played are the next one.
        await playIfNeeded()
    }

    private func stopBurst() {
        burstTask?.cancel()
        burstTask = nil
        incomingBurst = nil
        incomingLine = nil
        isPlaying = false
    }

    // MARK: - Queue

    /// Starts a send of the waiting writes. It runs on its own task, so the view
    /// leaving or a newer tap does not cancel the request.
    private func requestSync() {
        let sync = syncAfterLocalChange
        Task { await sync() }
    }

    private func enqueue(
        _ kind: SyncPendingOperationKind,
        payload: some Encodable,
        ownerUserID: UUID
    ) async {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // A heart that cannot be saved is not worth a banner. The tap already played.
        try? await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operationProvider.makeOperation(),
                operationKind: kind,
                idempotencyScope: "hearts",
                requestData: data
            )
        )
    }

    private static func defaultPendingOperationStore() -> any PendingSyncOperationPersisting {
        if let localStore = PaeoniaLocalStore.shared {
            return SwiftDataPendingSyncOperationRepository(container: localStore.container)
        }
        return InMemoryPendingSyncOperationRepository()
    }

    static func playFeedback(_ line: String) {
        PaeoniaHaptics.heartsReceived()
        AccessibilityNotification.Announcement(line).post()
    }
}
