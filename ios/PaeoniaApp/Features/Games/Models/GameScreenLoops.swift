import Foundation

/// The background loops every game screen runs while it is open: the heartbeat
/// that says this screen is open, the follow of local changes, and the clock
/// tick. Each game's view model owns one.
///
/// Presence writes go out one after another. A heartbeat already on its way
/// finishes before the leaving write starts, so "away" is the last word the
/// server hears. The leaving write runs in a background task, so it still goes
/// out when the app moves to the background.
@MainActor
final class GameScreenLoops {
    private let kind: GameKind
    private let gateway: any GamesGateway
    private let heartbeatInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var heartbeatTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    /// The newest presence write. The next one waits for it.
    private var lastPresenceWrite: Task<Void, Never>?

    init(
        kind: GameKind,
        gateway: any GamesGateway,
        heartbeatInterval: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.kind = kind
        self.gateway = gateway
        self.heartbeatInterval = heartbeatInterval
        self.sleep = sleep
    }

    /// A screen that goes away without stopping must not leave loops behind.
    isolated deinit {
        heartbeatTask?.cancel()
        observationTask?.cancel()
        tickTask?.cancel()
    }

    // MARK: - Presence

    /// Says this screen is open now and every `heartbeatInterval` after.
    func beginHeartbeat() {
        heartbeatTask?.cancel()
        let interval = heartbeatInterval
        let sleep = sleep
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let write = self?.enqueuePresence(true) else { return }
                await write.value
                if let kind = self?.kind { await DeliveredNotifications.clearGame(kind) }
                try? await sleep(interval)
            }
        }
    }

    /// Stops the heartbeat and says this screen is closed.
    func endHeartbeat() {
        cancelHeartbeat()
        let background = BackgroundTaskToken(name: "Game presence")
        let write = enqueuePresence(false)
        Task {
            await write.value
            background.end()
        }
    }

    /// Stops the heartbeat without saying anything, like an app that was killed.
    func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func enqueuePresence(_ isPresent: Bool) -> Task<Void, Never> {
        let previous = lastPresenceWrite
        let gateway = gateway
        let kind = kind
        let write = Task {
            await previous?.value
            try? await gateway.setPresence(kind, isPresent: isPresent)
        }
        lastPresenceWrite = write
        return write
    }

    // MARK: - Following the app's data

    /// Runs `reload` after each change to the games data or the pending writes
    /// that belongs to the current person.
    func beginObserving(
        currentUserID: @escaping @MainActor () -> UUID?,
        reload: @escaping @MainActor () async -> Void
    ) {
        observationTask?.cancel()
        observationTask = Task {
            for await change in LocalStoreChanges.changes(in: .games, .pendingOperations) {
                guard !Task.isCancelled else { return }
                guard change.ownerUserID == nil || change.ownerUserID == currentUserID() else { continue }
                await reload()
            }
        }
    }

    /// Runs `tick` every `interval`, so what follows the clock stays current.
    func beginTicking(every interval: Duration, _ tick: @escaping @MainActor () -> Void) {
        tickTask?.cancel()
        let sleep = sleep
        tickTask = Task {
            while !Task.isCancelled {
                try? await sleep(interval)
                guard !Task.isCancelled else { return }
                tick()
            }
        }
    }

    /// Stops following the data and the clock. The heartbeat has its own end.
    func cancelFollowing() {
        observationTask?.cancel()
        observationTask = nil
        tickTask?.cancel()
        tickTask = nil
    }
}
