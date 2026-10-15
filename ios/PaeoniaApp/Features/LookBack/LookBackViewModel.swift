import Foundation
import Observation

/// The Home look-back card's state. It shows the last result from the device first, then asks the
/// server, so Home does not gain a card a moment after it opens. A failed read keeps what is on
/// screen. The server picks one item per couple day, so a read when Home appears, when the app
/// returns to the foreground, when the couple's day ends, and when the shown content changes on
/// this phone is enough. There is no live subscription: the content is at least a week old, and the
/// pick depends on the time the app asks at.
@MainActor
@Observable
final class LookBackViewModel {
    private(set) var item: LookBackItem?
    /// When the couple day of the last read ends. Home reads again then.
    private(set) var refreshAt: Date?
    /// Raised when a read is due that no view event caused, such as the couple becoming known.
    private(set) var refreshRequest = 0
    /// Renders drawing thumbnails for the card.
    let thumbnailLoader: any WidgetRevisionThumbnailLoading

    private let service: any LookBackServing
    private let cache: any LookBackCaching
    private let now: @Sendable () -> Date
    /// How long the store must stay quiet before a change causes a read.
    private let storeChangeQuietPeriod: Duration
    private var userID: UUID?
    private var coupleID: UUID?
    /// Numbers each read in the order it started. A read never applies after a newer one has.
    private var readCounter = 0
    private var lastAppliedRead = 0

    init(
        service: any LookBackServing = NoOpLookBackService(),
        cache: any LookBackCaching = FileLookBackCache.shared,
        thumbnailLoader: any WidgetRevisionThumbnailLoading = NoOpWidgetRevisionThumbnailLoader(),
        now: @escaping @Sendable () -> Date = { Date() },
        storeChangeQuietPeriod: Duration = .seconds(2)
    ) {
        self.service = service
        self.cache = cache
        self.thumbnailLoader = thumbnailLoader
        self.now = now
        self.storeChangeQuietPeriod = storeChangeQuietPeriod
    }

    /// Starts for a signed-in user, then reads. Only a different user resets and loads the saved
    /// item. The couple id arrives after launch and goes through `updateCouple`.
    func configure(userID: UUID?, coupleID: UUID?) async {
        self.coupleID = coupleID
        if self.userID != userID {
            self.userID = userID
            item = nil
            refreshAt = nil
            lastAppliedRead = readCounter
            guard let userID else { return }

            let cache = cache
            let cached = await Task.detached(priority: .userInitiated) {
                cache.load(ownerUserID: userID, coupleID: coupleID)
            }.value
            guard self.userID == userID else { return }
            item = cached?.item
        }
        await refresh()
    }

    /// The couple id is known or changed. A card saved for another couple goes away, and a read is due.
    func updateCouple(_ coupleID: UUID?) {
        guard self.coupleID != coupleID else { return }
        self.coupleID = coupleID
        guard let userID, let coupleID else { return }
        if cache.load(ownerUserID: userID, coupleID: coupleID) == nil {
            item = nil
            refreshRequest += 1
        }
    }

    /// Asks the server for the current couple day's item and keeps it. A failed read changes nothing.
    /// The caller's task decides how long the read may run. Cancelling it drops the answer.
    func refresh() async {
        guard let userID else { return }
        readCounter += 1
        let mine = readCounter
        let purgeCount = cache.purgeCount()
        let response: LookBackResponse
        do {
            response = try await service.fetch(now: Self.requestTime(now()))
        } catch {
            return
        }
        // A read that finishes after the user changed, after a newer read, or once the view is gone
        // must not show or save anything.
        guard self.userID == userID, mine > lastAppliedRead, !Task.isCancelled else { return }
        lastAppliedRead = mine
        let saved = cache.save(
            LookBackCacheEntry(coupleID: coupleID, item: response.item),
            ownerUserID: userID,
            unlessPurgedSince: purgeCount
        )
        // The private content was cleared while this read was in flight. Show nothing from it.
        item = saved ? response.item : nil
        refreshAt = saved ? response.endsAt : nil
    }

    /// Reads again when the content the card shows changes on this phone, such as a memory a
    /// partner deleted. A burst of changes makes one read, after the store has been quiet for
    /// `storeChangeQuietPeriod`. Runs until the calling task is cancelled.
    func observeStoreChanges() async {
        var scheduledRead: Task<Void, Never>?
        defer { scheduledRead?.cancel() }
        for await change in LocalStoreChanges.changes(in: .memories, .dailyChallenge) {
            guard change.ownerUserID == userID, let kind = item?.kind else { continue }
            switch (change.domain, kind) {
            case (.memories, .memory), (.dailyChallenge, .question):
                scheduledRead?.cancel()
                let quietPeriod = storeChangeQuietPeriod
                scheduledRead = Task { [weak self] in
                    try? await Task.sleep(for: quietPeriod)
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            default:
                continue
            }
        }
    }

    /// The time the app asks at: now, rounded down to 15 minutes, so repeated asks cache. Time zone
    /// offsets are whole multiples of 15 minutes, so a couple day never ends between two marks.
    static func requestTime(_ date: Date) -> Date {
        let step: TimeInterval = 900
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / step).rounded(.down) * step)
    }
}

extension LookBackViewModel {
    /// The production model: reads through the signed-in Convex client, or shows nothing when none
    /// is configured (previews and tests).
    static func live(thumbnailLoader: any WidgetRevisionThumbnailLoading) -> LookBackViewModel {
        let service: any LookBackServing
        if let client = try? PaeoniaConvexClientProvider.shared.client() {
            service = LiveLookBackService(client: client)
        } else {
            service = NoOpLookBackService()
        }
        return LookBackViewModel(service: service, thumbnailLoader: thumbnailLoader)
    }
}
