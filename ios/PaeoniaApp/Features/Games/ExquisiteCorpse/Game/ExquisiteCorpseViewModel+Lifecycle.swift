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
        loops.beginObserving(
            currentUserID: { [weak self] in self?.currentUserID },
            reload: { [weak self] in await self?.reload() }
        )
        loops.beginTicking(every: tickInterval) { [weak self] in
            guard let self else { return }
            now = dependencies.now()
            recompute()
        }
        if isActive {
            loops.beginHeartbeat()
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
        attentionCue.reset()
        cancelTasks()
        loops.endHeartbeat()
        stopLive()
        saveDraftNow()
    }

    /// The game screen, or "Our creatures" pushed over it, appeared.
    func screenAppeared() {
        visibleScreens += 1
    }

    /// The game screen, or "Our creatures" pushed over it, went away. Opening
    /// "Our creatures" keeps the game going, so the partner still sees this person
    /// in the game. Leaving both, switching tabs or going back to the hub stops it.
    /// The check waits a moment, in case the other screen is about to appear.
    func screenDisappeared() {
        visibleScreens = max(0, visibleScreens - 1)
        Task { [weak self] in
            guard let self, visibleScreens == 0 else { return }
            stop()
        }
    }

    /// The app moved to the background or came back while the screen is open.
    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            loops.beginHeartbeat()
            startLive()
            // A download that waited for the screen starts now.
            recompute()
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in await self?.refresh() }
        } else {
            loops.endHeartbeat()
            stopLive()
            saveDraftNow()
        }
    }

    func cancelTasks() {
        loops.cancelFollowing()
        for task in [draftTask, startTask, refreshTask] {
            task?.cancel()
        }
        draftTask = nil
        startTask = nil
        refreshTask = nil
        cancelStripLoad()
        cancelRevealLoads()
    }

    func resetForNewIdentity() {
        attentionCue.reset()
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
        liveStroke = nil
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
