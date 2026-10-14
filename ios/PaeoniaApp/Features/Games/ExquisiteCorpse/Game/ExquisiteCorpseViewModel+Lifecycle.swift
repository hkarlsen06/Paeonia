import Foundation
import PencilKit

// Starting and stopping: the screen appeared or went away, and the app moved to
// the background.
extension ExquisiteCorpseViewModel {
    // MARK: - Lifecycle

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
        isRunning = false
        isStopped = true
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
            // A download that waited for the screen starts now.
            recompute()
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in await self?.refresh() }
        } else {
            heartbeatTask?.cancel()
            heartbeatTask = nil
            sendPresence(false)
            stopLive()
            saveDraftNow()
        }
    }

    func cancelTasks() {
        for task in [observationTask, tickTask, draftTask, startTask, refreshTask] {
            task?.cancel()
        }
        observationTask = nil
        tickTask = nil
        draftTask = nil
        startTask = nil
        refreshTask = nil
        cancelStripLoad()
        cancelRevealLoads()
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
        overview = nil
        pending = .none
        savedIdeaIDs = [:]
        phase = .loading
        part = nil
        figure = nil
        live?.stop()
        live = nil
        channel = nil
        penCanvas = nil
        penSampler = ExquisiteCorpsePenSampler()
        sentStrip = nil
        doneSentPartID = nil
        watchedPartID = nil
        partnerFinishedPartID = nil
        partnerFinishedPart = nil
        partnerPen = nil
        partnerStrip = nil
        lastPartnerPresence = .away
        liveStrips = [:]
        liveStripOrder = []
        boardPartID = nil
        boardSentPartID = nil
        ideaDeck = nil
        idea = nil
        hasIdeas = false
        board.reset()
        cancelStripLoad()
        downloadedStrip = nil
        strip = nil
        resetReveal()
    }
}
