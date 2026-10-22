import PencilKit
import QuartzCore
import SwiftUI

// The partner's drawing: fetching it, playing it back, and telling the server
// when the guesser first saw it.
extension DrawAndGuessViewModel {
    // MARK: - Loading

    /// The waits before each new try of a drawing download that failed.
    static let drawingDownloadRetryDelays: [Duration] = [.seconds(1), .seconds(3)]

    /// Fetches the sent drawing file, for the guesser to replay and for the drawer's
    /// own screen after a relaunch. It waits while the screen is closed or the
    /// app is in the background.
    func loadDrawingIfNeeded() {
        guard isActive, !isStopped, let userID = currentUserID, let round, let assetID = round.drawingMediaAssetID,
              loadedAssetID != assetID, loadingAssetID != assetID
        else { return }
        // A guesser who watched the drawing live already has it until the round ends
        // or the drawer leaves and the live canvas empties.
        if !round.isDrawer(userID), !round.isFinished, isWatchingLiveCanvas(of: round) { return }

        loadingAssetID = assetID
        drawingLoadFailed = false
        let store = dependencies.drawingStore
        // A drawing already on the phone shows in the same update, so a reveal
        // that opens directly never starts on an empty square.
        if let cached = store.downloadedDrawing(mediaAssetID: assetID) {
            finishLoading(assetID: assetID, ownerUserID: userID, data: cached, isDownloaded: false)
            return
        }
        isLoadingDrawing = true
        let transfer = dependencies.drawingTransfer
        drawingLoadTask = Task { [weak self, sleep] in
            // A finished round gets no later change that would fetch it again,
            // so a dropped download is tried again here.
            var data = try? await transfer.downloadDrawing(mediaAssetID: assetID)
            for delay in Self.drawingDownloadRetryDelays where data == nil {
                do { try await sleep(delay) } catch { return }
                guard !Task.isCancelled, self?.loadingAssetID == assetID else { return }
                data = try? await transfer.downloadDrawing(mediaAssetID: assetID)
            }
            guard !Task.isCancelled else { return }
            self?.finishLoading(assetID: assetID, ownerUserID: userID, data: data, isDownloaded: true)
        }
    }

    /// The guesser watched this round live, the drawer is still in the live room,
    /// and the room holds all of the drawer's strokes. The live room clears the
    /// canvas when the drawer leaves, and the guesser then needs the sent drawing.
    /// A canvas left over from before a drop can miss strokes, so it counts only
    /// once a snapshot caught it up.
    ///
    /// The drawer stays in the room as `drawing` after tapping Done, but no
    /// longer has a canvas to answer a snapshot request. A guesser who comes
    /// back (a push, or the app returning from the background) joins an empty
    /// room. Without the strokes check that guesser would look at the empty live
    /// canvas and never download the drawing. A replay that is already playing
    /// never goes back to the live canvas.
    func isWatchingLiveCanvas(of round: DrawAndGuessRoundView) -> Bool {
        watchedLiveRoundIDs.contains(round.id)
            && !isReplayReady
            && live?.partnerActivity == .drawing
            && live?.isPartnerCanvasCaughtUp == true
            && live?.partnerCanvasDrawing?.strokes.isEmpty == false
    }

    /// Stops a fetch that is still running, and forgets that it was.
    func cancelDrawingLoad() {
        drawingLoadTask?.cancel()
        drawingLoadTask = nil
        loadingAssetID = nil
        isLoadingDrawing = false
    }

    private func finishLoading(assetID: UUID, ownerUserID: UUID, data: Data?, isDownloaded: Bool) {
        // A fetch that outlived its round, or this person's session, writes nothing.
        guard loadingAssetID == assetID, currentUserID == ownerUserID else { return }
        loadingAssetID = nil
        drawingLoadTask = nil
        isLoadingDrawing = false
        if isDownloaded, let data {
            dependencies.drawingStore.saveDownloadedDrawing(data, mediaAssetID: assetID)
        }
        guard let data, let decoded = try? PKDrawing(data: data) else {
            // Every try failed. "Try again", the screen coming back, or the next
            // state change fetches it again.
            drawingLoadFailed = round?.drawingMediaAssetID == assetID
            return
        }
        drawingLoadFailed = false
        downloadedDrawing = decoded
        loadedAssetID = assetID
        // The drawer's final drawing replaces what the live room showed.
        if let round, round.drawingMediaAssetID == assetID {
            liveSnapshots[round.id] = nil
            dependencies.drawingStore.removeLiveSnapshot(ownerUserID: ownerUserID, roundID: round.id)
        }
        loadedDrawingVersion += 1
        replayTimeline = GameReplayTimeline(drawing: decoded)
        startReplayIfNeeded()
        markSeenIfNeeded()
        // The drawer may already follow the partner's replay, which needed this drawing.
        updatePartnerGuess()
    }

    // MARK: - Replay

    /// Starts the replay the first time the guesser can see it. When the guesser
    /// watched the drawing live, the live canvas stays and there is no replay.
    /// It waits while the screen is closed or the app is in the background.
    func startReplayIfNeeded() {
        guard isActive, !isStopped, phase == .guessing, let round else { return }
        if isWatchingLiveCanvas(of: round) {
            guessSource = .live
            isReplayReady = false
            return
        }
        guessSource = .replay
        guard replayClock == nil, let timeline = replayTimeline,
              loadedAssetID == round.drawingMediaAssetID
        else { return }
        replayClock = GameReplayClock(duration: timeline.duration, startingAt: monotonicNow())
        isReplayReady = true
        isFastForwarding = false
    }

    /// "Try again" on the drawing that could not load.
    func retryLoadingDrawing() {
        drawingLoadFailed = false
        loadDrawingIfNeeded()
    }

    /// The round ended, so the rest of the drawing shows at once.
    func finishReplayIfNeeded() {
        guard phase == .reveal, var clock = replayClock, !clock.isFinished(at: monotonicNow()) else { return }
        clock.finish(at: monotonicNow())
        replayClock = clock
        isFastForwarding = false
    }

    /// "Show the whole drawing" for VoiceOver.
    func showWholeDrawing() {
        guard var clock = replayClock else { return }
        clock.finish(at: monotonicNow())
        replayClock = clock
        isFastForwarding = false
    }

    /// How far the replay has come, from 0 to 1, for the progress line.
    func replayProgress(atWall wall: TimeInterval) -> Double {
        guard let clock = replayClock, clock.duration > 0 else { return 0 }
        return min(1, clock.replayTime(at: wall) / clock.duration)
    }

    /// The drawing the guesser sees at `wall` (a steady clock such as
    /// `CACurrentMediaTime()`), scaled to a canvas of `side` points.
    func replayDrawing(atWall wall: TimeInterval, side: CGFloat) -> PKDrawing {
        guard let timeline = replayTimeline, let clock = replayClock else { return PKDrawing() }
        let drawing = timeline.drawing(at: clock.replayTime(at: wall))
        return GameCanvas.fitted(drawing, toSide: side)
    }

    func isReplayFinished(atWall wall: TimeInterval) -> Bool {
        replayClock?.isFinished(at: wall) ?? false
    }

    /// The guesser's replay for `GameReplaySurface`.
    var replayFrames: GameReplayFrames {
        GameReplayFrames(
            playback: { [weak self] wall in
                guard let self, isReplayReady, let timeline = replayTimeline, let clock = replayClock
                else { return nil }
                return .init(timeline: timeline, time: clock.replayTime(at: wall))
            },
            isFinished: { [weak self] wall in self?.isReplayFinished(atWall: wall) ?? false }
        )
    }

    /// Hold to fast-forward, release to go back to the drawn pace.
    func setFastForward(_ isOn: Bool) {
        guard var clock = replayClock, isFastForwarding != isOn else { return }
        clock.setRate(isOn ? GameReplayClock.fastForwardRate : 1, at: monotonicNow())
        replayClock = clock
        isFastForwarding = isOn
    }

    // MARK: - First look

    /// Tells the server when the guesser first saw the drawing. The speed
    /// bonus counts from it. The first call wins on the server. Nothing is
    /// seen while the screen is closed or the app is in the background. A live
    /// canvas counts once the drawer's first stroke is on it, so a drawer who
    /// has not started yet does not use up the guesser's bonus time.
    func markSeenIfNeeded() {
        guard isActive, !isStopped,
              let userID = currentUserID, let round, !round.isFinished, round.guesserUserID == userID,
              round.guesserFirstSeenAt == nil, !markedSeenRoundIDs.contains(round.id)
        else { return }
        switch phase {
        case .watchingLive:
            guard live?.partnerActivity == .drawing, live?.hasPartnerStrokes == true else { return }
            watchedLiveRoundIDs.insert(round.id)
        case .guessing:
            guard isReplayReady || guessSource == .live else { return }
        default:
            return
        }
        markedSeenRoundIDs.insert(round.id)
        // A retry after a failed call keeps the first look, so the bonus window closes on time.
        if localFirstSeenAt[round.id] == nil {
            localFirstSeenAt[round.id] = dependencies.now()
        }
        updateSpeedBonus()
        let gateway = gateway
        let roundID = round.id
        Task { [weak self] in
            do {
                _ = try await gateway.markRoundSeen(roundID: roundID)
            } catch {
                // Try again on the next change.
                self?.markedSeenRoundIDs.remove(roundID)
            }
        }
    }
}
