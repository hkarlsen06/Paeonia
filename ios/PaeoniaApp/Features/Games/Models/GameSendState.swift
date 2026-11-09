/// Where this phone's waiting game moves stand. Every game screen reads this one
/// value, so a screen cannot show a failing send for a move that no longer waits.
nonisolated enum GameSendState: Equatable, Sendable {
    /// No move waits to be sent.
    case nothingWaiting
    /// A move waits for its first try. Every write waits a moment, also online,
    /// so screens say nothing yet.
    case sending
    /// A try did not get through. Screens say the move is saved on this phone.
    case heldOnPhone
    /// A try reached the server or the sign-in and failed there. Screens offer a retry.
    case failing

    /// - Parameters:
    ///   - isWaiting: A move of the shown turn waits to be sent.
    ///   - hasFailedAttempt: A waiting move has had a try that did not get through.
    ///   - failedWhileOnline: A waiting move's last try failed for a reason other
    ///     than having no connection (`PendingSyncOperationSnapshot.failedWhileOnline`).
    init(isWaiting: Bool, hasFailedAttempt: Bool, failedWhileOnline: Bool) {
        if !isWaiting {
            self = .nothingWaiting
        } else if failedWhileOnline {
            self = .failing
        } else if hasFailedAttempt {
            self = .heldOnPhone
        } else {
            self = .sending
        }
    }

    /// For a screen where every queued operation counts as a waiting move.
    init(waiting operations: [PendingSyncOperationSnapshot]) {
        self.init(
            isWaiting: !operations.isEmpty,
            hasFailedAttempt: operations.contains(where: \.hasFailedAttempt),
            failedWhileOnline: operations.contains(where: \.failedWhileOnline)
        )
    }

    var isWaiting: Bool { self != .nothingWaiting }
    /// A failing move is still on this phone, so this is true for it too.
    var isHeldOnPhone: Bool { self == .heldOnPhone || self == .failing }
    var isFailing: Bool { self == .failing }
}
