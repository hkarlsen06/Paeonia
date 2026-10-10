import Foundation

/// Orders the live feed's snapshot writes against the answers of one-shot requests
/// (load, start, shuffle). The live subscription is the source of truth for the
/// couple day it follows. A response that was already in flight when the feed wrote
/// a newer result of the same couple day is older than that result, so it must not
/// replace it. `generated_at` cannot settle this, because two snapshots built in the
/// same millisecond are not ordered by it.
///
/// A request reads `count(ownerUserID:)` before it starts. The feed saves through
/// `recordLiveWrite`. The request then saves through `saveResponse`, which keeps the
/// cached live row when the count moved, unless the response is for a later couple day.
/// One lock covers the count and the file write, so a response never lands between
/// the two.
nonisolated final class DailyChallengeLiveWriteClock: @unchecked Sendable {
    /// One clock for the whole app, because the feed and the service use separate cache objects.
    static let shared = DailyChallengeLiveWriteClock()

    private let lock = NSLock()
    private var counts: [UUID: Int] = [:]

    func count(ownerUserID: UUID) -> Int {
        lock.withLock { counts[ownerUserID, default: 0] }
    }

    /// Saves a row the live feed received and counts it.
    func recordLiveWrite(
        _ row: DailyChallengeRemoteSnapshotRow,
        ownerUserID: UUID,
        cache: any DailyChallengeSnapshotCaching
    ) {
        lock.withLock {
            counts[ownerUserID, default: 0] += 1
            cache.save(row, ownerUserID: ownerUserID)
        }
    }

    /// Saves a request's response unless the feed wrote after `start` and the response
    /// is not for a later couple day. Returns the row the caller should show.
    func saveResponse(
        _ row: DailyChallengeRemoteSnapshotRow,
        ownerUserID: UUID,
        since start: Int,
        cache: any DailyChallengeSnapshotCaching
    ) -> DailyChallengeRemoteSnapshotRow {
        lock.withLock {
            if counts[ownerUserID, default: 0] != start,
               let live = cache.load(ownerUserID: ownerUserID),
               !row.isNewerDay(than: live) {
                return live
            }
            cache.save(row, ownerUserID: ownerUserID)
            return row
        }
    }
}

private extension DailyChallengeRemoteSnapshotRow {
    /// Whether this response moves to a later couple day than `live`. A response
    /// for the same day, an earlier day, or no day at all is older than live data.
    func isNewerDay(than live: Self) -> Bool {
        guard coupleDayID != live.coupleDayID, let endsAt else {
            return false
        }
        guard let liveEndsAt = live.endsAt else {
            return true
        }
        return endsAt > liveEndsAt
    }
}
