import Foundation

// Starting and stopping: the screen appeared or went away, and the app moved to
// the background.
extension MindMeldViewModel {
    /// The game screen appeared. Reads the cache, follows changes, and tells the
    /// partner this screen is open.
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        isStopped = false
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
        // A reveal the person watched to its verdict is seen, as the design says
        // for leaving it with back. The queued marks outlive the screen.
        if phase == .reveal, let id = resolution.round?.id, settledRevealRoundID == id {
            continueFromReveal()
        }
        isRunning = false
        isStopped = true
        cancelTasks()
        endHeartbeat()
        sendTyping(false)
        stopLive()
        showsPartnerRestartedNote = false
    }

    /// The app moved to the background or came back while the screen is open.
    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            beginHeartbeat()
            startLive()
            recompute()
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in await self?.refresh() }
        } else {
            heartbeatTask?.cancel()
            heartbeatTask = nil
            sendPresence(false)
            sendTyping(false)
            stopLive()
        }
    }

    func cancelTasks() {
        for task in [observationTask, tickTask, startTask, refreshTask, typingIdleTask, partnerTypingTask] {
            task?.cancel()
        }
        observationTask = nil
        tickTask = nil
        startTask = nil
        refreshTask = nil
        typingIdleTask = nil
        partnerTypingTask = nil
        partnerTypingRound = nil
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
}
