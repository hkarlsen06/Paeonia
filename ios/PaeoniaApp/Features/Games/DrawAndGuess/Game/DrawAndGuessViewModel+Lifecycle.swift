import Foundation
import QuartzCore

// Starting and stopping: the screen appeared or went away, and the app moved to
// the background.
extension DrawAndGuessViewModel {
    // MARK: - Lifecycle

    /// The game screen appeared. Reads the cache, follows changes, and tells the
    /// partner this screen is open.
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        isActive = true
        await reload()
        // The screen may have gone away, or the app to the background, while the
        // cache was read. Opening presence and sockets now would leave them open.
        guard isRunning, !Task.isCancelled else { return }
        beginObserving()
        beginTicking()
        if isActive {
            beginHeartbeat()
            startLive()
        }
        // The live feed keeps the cache current. This read covers a build without
        // it and the first launch, when the cache is empty.
        await refresh()
    }

    /// The game screen went away.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelTasks()
        endHeartbeat()
        stopLive()
        saveDraftNow()
    }

    /// The app moved to the background or came back while the screen is open.
    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            beginHeartbeat()
            startLive()
            Task { await refresh() }
        } else {
            heartbeatTask?.cancel()
            heartbeatTask = nil
            sendPresence(false)
            stopLive()
            saveDraftNow()
        }
    }

    func cancelTasks() {
        for task in [observationTask, tickTask, wrongGuessTask, draftTask, startTask] {
            task?.cancel()
        }
        cancelDrawingLoad()
        observationTask = nil
        tickTask = nil
        wrongGuessTask = nil
        draftTask = nil
        startTask = nil
    }

    func beginObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await change in LocalStoreChanges.changes(in: .games, .pendingOperations) {
                guard !Task.isCancelled, let self else { return }
                guard change.ownerUserID == nil || change.ownerUserID == currentUserID else { continue }
                await reload()
            }
        }
    }

    func beginTicking() {
        tickTask?.cancel()
        let interval = tickInterval
        let sleep = sleep
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await sleep(interval)
                guard !Task.isCancelled, let self else { return }
                now = dependencies.now()
                recompute()
            }
        }
    }

    func resetForNewIdentity() {
        state = nil
        pending = .none
        acknowledgedRoundIDs = []
        phase = .loading
        round = nil
        live?.stop()
        live = nil
        tilesRoundID = nil
        boardRoundID = nil
        board.reset()
        resetReplay()
    }
}
