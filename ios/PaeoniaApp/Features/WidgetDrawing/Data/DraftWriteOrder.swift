import os

/// Keeps draft writes in order when some of them run off the main actor. Each
/// write takes a ticket on the main actor, and a write whose ticket is no longer
/// the latest is skipped, so a later draft or a delete is never undone by an
/// earlier write that finishes late.
nonisolated final class DraftWriteOrder: Sendable {
    private let latest = OSAllocatedUnfairLock(initialState: 0)

    /// Call on the main actor, before starting the background work.
    func nextTicket() -> Int {
        latest.withLock { latest in
            latest += 1
            return latest
        }
    }

    /// Runs `write` unless a later ticket exists. The write holds the lock, so a
    /// later one waits for it.
    func perform(_ ticket: Int, _ write: () -> Void) {
        latest.withLockUnchecked { latest in
            if latest == ticket {
                write()
            }
        }
    }

    /// For a write that happens right away on the calling thread.
    func performNow(_ write: () -> Void) {
        perform(nextTicket(), write)
    }
}
