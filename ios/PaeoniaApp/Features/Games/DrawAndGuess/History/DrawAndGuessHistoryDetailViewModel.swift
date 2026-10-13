import Observation
import PencilKit
import QuartzCore

/// One drawing from "Our drawings": it plays back once at the pace it was drawn,
/// with the word, who drew it, how the round went, and the person's own star.
@MainActor
@Observable
final class DrawAndGuessHistoryDetailViewModel {
    enum DrawingState: Equatable {
        case loading
        case failed
        case ready
    }

    let round: RemoteDrawAndGuessHistoryRound
    let stars: DrawAndGuessStars
    private(set) var drawingState: DrawingState = .loading
    private(set) var isFastForwarding = false

    @ObservationIgnored private let participants: DrawAndGuessParticipants
    @ObservationIgnored private let drawings: DrawAndGuessHistoryDrawings
    @ObservationIgnored private let monotonicNow: @Sendable () -> TimeInterval
    @ObservationIgnored private var timeline: DrawAndGuessReplayTimeline?
    @ObservationIgnored private var clock: DrawAndGuessReplayClock?

    init(
        round: RemoteDrawAndGuessHistoryRound,
        participants: DrawAndGuessParticipants,
        stars: DrawAndGuessStars,
        drawings: DrawAndGuessHistoryDrawings,
        monotonicNow: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        self.round = round
        self.participants = participants
        self.stars = stars
        self.drawings = drawings
        self.monotonicNow = monotonicNow
    }

    // MARK: - What the screen shows

    var word: String {
        DrawAndGuessAnswer.display(round.word)
    }

    var isStarred: Bool {
        stars.isStarred(round.id)
    }

    /// The partner's name, or "you" in lowercase for use after "by".
    var drawerName: String {
        round.drawerUserID == participants.currentUserID
            ? String(localized: .gamesDrawAndGuessHistoryWhoYou)
            : participants.partnerName
    }

    /// The guesser's name, or "You" for use at the start of a sentence.
    private var guesserName: String {
        round.guesserUserID == participants.currentUserID
            ? String(localized: .gamesDrawAndGuessRevealYou)
            : participants.partnerName
    }

    /// "Drawn by Robin · Oct 12".
    var drawnByLine: LocalizedStringResource {
        .gamesDrawAndGuessHistoryDetailDrawnBy(drawerName, round.date.formatted(date: .abbreviated, time: .omitted))
    }

    /// One line about how the round went: "Robin got it in 24 seconds, on the
    /// first try." or "Robin asked for the answer".
    var resultLine: LocalizedStringResource {
        let name = guesserName
        guard round.isSolved else { return .gamesDrawAndGuessResultMissed(name) }
        let tries = round.tries
        switch (round.shownSolveMs, tries) {
        case (let ms?, 1):
            return .gamesDrawAndGuessResultSolvedTimedFirstTry(name, Self.spoken(ms))
        case (let ms?, _):
            return .gamesDrawAndGuessResultSolvedTimedTries(name, Self.spoken(ms), tries)
        case (nil, 1):
            return .gamesDrawAndGuessResultSolvedFirstTry(name)
        case (nil, _):
            return .gamesDrawAndGuessResultSolvedTries(name, tries)
        }
    }

    /// The guesser's reaction, if they left one.
    var reaction: (symbol: String, text: LocalizedStringResource)? {
        round.guesserReaction.map { ($0.symbol, $0.drawerLine(partnerName: guesserName)) }
    }

    /// "24 seconds" or "1 minute, 5 seconds".
    static func spoken(_ ms: Int) -> String {
        DrawAndGuessHistoryFormat.duration(ms: ms, width: .wide)
    }

    // MARK: - Star

    func toggleStar() async {
        await stars.toggle(roundID: round.id)
    }

    // MARK: - Replay

    /// Loads the drawing and plays it once. With `showsAtOnce` (Reduce Motion) the
    /// finished drawing shows and "Play again" plays it on request.
    func load(showsAtOnce: Bool) async {
        guard drawingState != .ready else { return }
        drawingState = .loading
        guard let drawing = await drawings.drawing(for: round.drawingMediaAssetID) else {
            if !Task.isCancelled {
                drawingState = .failed
            }
            return
        }
        guard !Task.isCancelled else { return }
        timeline = DrawAndGuessReplayTimeline(drawing: drawing)
        drawingState = .ready
        startReplay(showsAtOnce: showsAtOnce)
    }

    func retryLoading(showsAtOnce: Bool) async {
        await load(showsAtOnce: showsAtOnce)
    }

    /// "Play again".
    func replay() {
        startReplay(showsAtOnce: false)
    }

    private func startReplay(showsAtOnce: Bool) {
        guard let timeline else { return }
        let wall = monotonicNow()
        var fresh = DrawAndGuessReplayClock(duration: timeline.duration, startingAt: wall)
        if showsAtOnce {
            fresh.finish(at: wall)
        }
        clock = fresh
        isFastForwarding = false
    }

    /// Hold to speed up, release to go back to the drawn pace.
    func setFastForward(_ isOn: Bool) {
        guard var clock, isFastForwarding != isOn else { return }
        clock.setRate(isOn ? DrawAndGuessReplayClock.fastForwardRate : 1, at: monotonicNow())
        self.clock = clock
        isFastForwarding = isOn
    }

    /// "Show the whole drawing" for VoiceOver.
    func showWholeDrawing() {
        guard var clock else { return }
        clock.finish(at: monotonicNow())
        self.clock = clock
        isFastForwarding = false
    }

    /// What `DrawAndGuessReplaySurface` draws on each screen frame.
    var frames: DrawAndGuessReplayFrames {
        DrawAndGuessReplayFrames(
            drawing: { [weak self] wall, side in
                guard let self, let timeline, let clock else { return nil }
                let drawing = timeline.drawing(at: clock.replayTime(at: wall))
                return DrawAndGuessCanvas.fitted(drawing, toSide: side)
            },
            isFinished: { [weak self] wall in self?.clock?.isFinished(at: wall) ?? false }
        )
    }
}
