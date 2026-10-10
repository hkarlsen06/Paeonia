import Foundation

/// Keeps today's challenge current while the app is open. A partner's answer, a
/// partner's shuffle, and a partner starting the day all arrive as new query
/// results. Each result goes into the snapshot cache, then the view model re-reads.
///
/// The feed follows one of two queries.
/// - With a known couple day it follows `get_daily_challenge_snapshot` for that
///   day. That query depends only on stored data, so it stays correct until the
///   day ends.
/// - Without one it follows `get_today_daily_challenge_snapshot`, which finds the
///   day by the server clock. When the partner starts the day, the rows that query
///   read change and it pushes the new day. The feed then switches to the day query.
///
/// Convex reruns a query only when data it read changes. The clock is not data, so
/// the today query can return a stale result after midnight, even to a new
/// subscription with the same arguments. At `ends_at` the feed therefore opens a
/// new today subscription with a different `p_day_key`. A different key is a
/// different cached query, so it runs again. The feed never starts a day. Starting
/// stays a user action (`start_daily_challenge_snapshot`).
nonisolated struct DailyChallengeLiveFeed: LiveFeed {
    let name = "daily_challenge"

    private struct DayWindow: Sendable {
        let dayID: UUID
        let endsAt: Date

        init?(_ row: DailyChallengeRemoteSnapshotRow) {
            guard let dayID = row.coupleDayID, let endsAt = row.endsAt else { return nil }
            self.dayID = dayID
            self.endsAt = endsAt
        }
    }

    private let cache: any DailyChallengeSnapshotCaching
    private let liveWrites: DailyChallengeLiveWriteClock
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        cache: any DailyChallengeSnapshotCaching,
        liveWrites: DailyChallengeLiveWriteClock = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.cache = cache
        self.liveWrites = liveWrites
        self.now = now
        self.sleep = sleep
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let owner = session.userID
        var window = cache.load(ownerUserID: owner).flatMap(DayWindow.init)
        var dayKey = localDateKey()
        while !Task.isCancelled {
            if let followed = window, followed.endsAt > now() {
                await follow(followed, owner: owner, live: live)
                guard !Task.isCancelled else {
                    return
                }
                // A day that ended gets a key no earlier request used. A day the
                // server rejected (for example another couple's) falls back to today.
                dayKey = now() >= followed.endsAt ? Self.key(endingAt: followed.endsAt) : localDateKey()
                window = nil
            } else {
                window = await followToday(key: dayKey, owner: owner, live: live)
                guard !Task.isCancelled else {
                    return
                }
                if window == nil {
                    dayKey = localDateKey()
                }
            }
        }
    }

    /// Follows one couple day until it ends, or until the server rejects the day
    /// before it sends a result.
    private func follow(_ window: DayWindow, owner: UUID, live: LiveQueryService) async {
        let _: DayWindow? = await first(until: window.endsAt) {
            var receivedResult = false
            let results = live.subscribe(
                "daily:get_daily_challenge_snapshot",
                args: ["p_couple_day_id": window.dayID.uuidString.lowercased()],
                as: [DailyChallengeRemoteSnapshotRow].self
            )
            for await result in results {
                switch result {
                case let .value(rows):
                    receivedResult = true
                    if let row = rows.first {
                        store(row, owner: owner)
                    }
                case let .failure(error):
                    if !receivedResult, error is PaeoniaConvexError {
                        return nil
                    }
                }
            }
            return nil
        }
    }

    /// Follows today's query until it reports a couple day that has not ended, or
    /// until the next local midnight, when the caller opens a new subscription.
    private func followToday(key: String, owner: UUID, live: LiveQueryService) async -> DayWindow? {
        await first(until: nextLocalMidnight()) {
            let results = live.subscribe(
                "daily:get_today_daily_challenge_snapshot",
                args: ["p_day_key": key],
                as: [DailyChallengeRemoteSnapshotRow].self
            )
            for await result in results {
                guard case let .value(rows) = result, let row = rows.first else {
                    continue
                }
                store(row, owner: owner)
                if let window = DayWindow(row), window.endsAt > now() {
                    return window
                }
            }
            return nil
        }
    }

    /// The first value `body` returns, or nil when `deadline` passes first. Either
    /// way the other side is cancelled.
    private func first<Value: Sendable>(
        until deadline: Date,
        _ body: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await sleep(.seconds(max(0, deadline.timeIntervalSince(now()))))
                return nil
            }
            let finished = await group.next()
            group.cancelAll()
            return finished.flatMap { $0 }
        }
    }

    private func store(_ row: DailyChallengeRemoteSnapshotRow, owner: UUID) {
        guard !Task.isCancelled else {
            return
        }
        liveWrites.recordLiveWrite(row, ownerUserID: owner, cache: cache)
        LocalStoreChanges.post(.dailyChallenge, ownerUserID: owner)
    }

    private func localDateKey() -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now())
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func nextLocalMidnight() -> Date {
        Calendar.current.nextDate(
            after: now(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now().addingTimeInterval(86_400)
    }

    private static func key(endingAt date: Date) -> String {
        date.formatted(.iso8601)
    }
}
