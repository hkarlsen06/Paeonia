import Foundation

/// Decides which reload's read reaches the screen when reloads overlap.
///
/// A read is dropped only when a reload that started later has already been
/// applied. A later reload that is still reading does not stop it, so a caller
/// that awaits `reload()`, such as `enqueue`, sees its change on screen when it
/// returns.
nonisolated struct GameReloadGate: Sendable {
    /// One reload's place in the order the reloads started.
    struct Ticket: Sendable {
        fileprivate let generation: Int
    }

    private var started = 0
    /// The newest reload whose read is on screen.
    private var applied = 0

    /// Call at the start of `reload()`, before the first `await`.
    mutating func begin() -> Ticket {
        started += 1
        return Ticket(generation: started)
    }

    /// Returns false when a reload that started later was already applied.
    /// Otherwise it records this reload as applied and returns true. Put it last
    /// in a `guard`, after the site's own checks, so a read those checks drop is
    /// never recorded as applied.
    mutating func apply(_ ticket: Ticket) -> Bool {
        guard ticket.generation > applied else { return false }
        applied = ticket.generation
        return true
    }
}
