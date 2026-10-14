import Observation
import SwiftUI

/// The animations the board plays. The spans match `UltimateTicTacToeTiming`.
enum UltimateTicTacToeMotion {
    static let zoomToMove = Animation.spring(duration: UltimateTicTacToeTiming.zoomToMove, bounce: 0.05)
    static let choose = Animation.spring(duration: 0.45, bounce: 0.08)
    static let regroup = PaeoniaMotion.heroMorph
    static let markDraw = Animation.spring(duration: UltimateTicTacToeTiming.markDraw, bounce: 0.3)
    static let close = Animation.spring(duration: UltimateTicTacToeTiming.close, bounce: 0.2)
    static let snap = PaeoniaMotion.buttonPress
    static let lightUp = PaeoniaMotion.stateChange
    static let drawLine = PaeoniaMotion.standardCurve(duration: UltimateTicTacToeOutcomeScript.lineDuration)
}

/// Plays the board's beats and owns the one value that says where the camera
/// is. Every zoom goes through `focus`, so a partner's move, my own move, the
/// player's taps and the outcome never fight over it.
///
/// Each beat checks a run id after it sleeps, so a move that arrives while the
/// last one is still playing finishes the old one at once and starts its own.
/// The playback never zooms while the player is pinching. It remembers where
/// the camera should go and moves there when the fingers lift.
@MainActor
@Observable
final class UltimateTicTacToePlayback {
    /// Everything the playback reads from the screen.
    struct Input: Equatable {
        var board: UltimateTicTacToeBoard
        var lastMove: BoardMoveEvent?
        var canPlay: Bool
        var showsOutcome: Bool
        /// False for Reduce Motion and VoiceOver, which never zoom.
        var zoomEnabled: Bool
        var reduceMotion: Bool
    }

    private struct DeferredFocus {
        let board: Int?
        let animation: Animation
    }

    // MARK: What the board draws

    /// The small board that fills the view, or nil for the whole board.
    private(set) var focus: Int?
    private(set) var hold = UltimateTicTacToeHold.none
    private(set) var glowHeld = false
    /// How often each small board has pulsed.
    private(set) var pulseCounts = Array(repeating: 0, count: 9)
    private(set) var outcome = UltimateTicTacToeOutcomeState.idle
    private(set) var bloomStart: Date?
    /// The newest move whose beat has started. The view holds back a move newer
    /// than this until the playback picks it up.
    private(set) var handledMoveNumber: Int?
    /// True while a move's beat plays. A tap then skips to the end of it.
    private(set) var isBusy = false
    private(set) var isPlayingOutcome = false

    // MARK: Internals

    @ObservationIgnored private(set) var zoom: UltimateTicTacToeZoom
    @ObservationIgnored private var input: Input
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var outcomeRunID = 0
    @ObservationIgnored private var outcomeTask: Task<Void, Never>?
    @ObservationIgnored private var outcomeShown: Bool
    @ObservationIgnored private var outcomeRequested = false
    @ObservationIgnored private var isGliding = false
    @ObservationIgnored private var isUserGesturing = false
    @ObservationIgnored private var deferredFocus: DeferredFocus?

    /// Starts from what is on the screen. Moves already on the board and an
    /// outcome already showing just show, with no beat.
    init(_ input: Input) {
        self.input = input
        zoom = UltimateTicTacToeZoom(board: input.board, canPlay: input.canPlay, zoomEnabled: input.zoomEnabled)
        handledMoveNumber = input.lastMove?.number
        outcomeShown = input.showsOutcome
        if input.showsOutcome {
            outcome = .settled(for: input.board.outcome)
        }
    }

    // MARK: Entry points

    /// Takes the screen's newest state. Call it whenever any part changes.
    func update(_ new: Input) {
        input = new
        syncZoom()
        if !hasStarted {
            hasStarted = true
            startIntro()
        }
        if let move = new.lastMove {
            if move.number != handledMoveNumber {
                handle(move)
            }
        } else if handledMoveNumber != nil {
            handledMoveNumber = nil
            skip()
        }
        updateOutcome()
        if !isBusy || isGliding {
            settleFocus()
        }
    }

    /// The player picked a zoom: a board to play in, or the whole board.
    func choose(_ choice: UltimateTicTacToeZoom.Choice) {
        zoom.choice = choice
        applyFocus(zoom.restingFocus, animation: UltimateTicTacToeMotion.choose)
    }

    /// A tap while a move plays: show the end of it now.
    func skip() {
        guard isBusy else { return }
        cancelSequence()
        withAnimation(UltimateTicTacToeMotion.snap) {
            hold = .none
            glowHeld = false
        }
        settleFocus()
        if outcomeRequested {
            startOutcome()
        }
    }

    /// A tap while the outcome plays: show it settled.
    func settleOutcome() {
        guard isPlayingOutcome else { return }
        cancelOutcome()
        bloomStart = nil
        withAnimation(PaeoniaMotion.stateChange) {
            outcome = .settled(for: input.board.outcome)
        }
    }

    /// The player's fingers are on the board, pinching. The camera waits.
    func setUserGesture(active: Bool) {
        isUserGesturing = active
        if !active, let deferred = deferredFocus {
            applyFocus(deferred.board, animation: deferred.animation)
        }
    }

    /// The view is going away. Stops every beat and keeps what was shown.
    func stop() {
        cancelSequence()
        cancelOutcome()
        hold = .none
        glowHeld = false
        bloomStart = nil
        if outcomeShown {
            outcome = .settled(for: input.board.outcome)
        }
    }
}

/// The beats: a move's sequence, the camera and the outcome highlight.
extension UltimateTicTacToePlayback {
    // MARK: Moves

    private func syncZoom() {
        let changed = zoom.board != input.board || zoom.canPlay != input.canPlay
        zoom.board = input.board
        zoom.canPlay = input.canPlay
        zoom.zoomEnabled = input.zoomEnabled
        if changed {
            zoom.choice = .automatic
        }
    }

    private func handle(_ event: BoardMoveEvent) {
        handledMoveNumber = event.number
        cancelSequence()
        guard input.zoomEnabled, let arriving = UltimateTicTacToeHold.arriving(event, on: input.board) else {
            withAnimation(UltimateTicTacToeMotion.snap) {
                hold = .none
                glowHeld = false
            }
            playHaptics(for: event)
            return
        }
        withAnimation(UltimateTicTacToeMotion.snap) {
            hold = arriving
            glowHeld = !event.isMine
        }
        run { [weak self] id in
            if event.isMine {
                await self?.playMine(event, id: id)
            } else {
                await self?.playPartner(event, id: id)
            }
        }
    }

    /// Without the zoom beats, the marks and lines animate on their own. Only the
    /// haptics are left.
    private func playHaptics(for event: BoardMoveEvent) {
        if !event.isMine {
            PaeoniaHaptics.partnerDrawingReceived()
        }
        if closedState(of: event)?.isWon == true {
            PaeoniaHaptics.streakContinued()
        }
    }

    private func closedState(of event: BoardMoveEvent) -> UltimateTicTacToeBoard.SmallBoard? {
        input.board.boards.indices.contains(event.move / 9) ? input.board.boards[event.move / 9] : nil
    }

    /// My partner's move: the camera goes to the board, the mark draws in, the
    /// board rests, then the camera goes where I play next.
    private func playPartner(_ event: BoardMoveEvent, id: Int) async {
        let board = event.move / 9
        requestFocus(board, animation: UltimateTicTacToeMotion.zoomToMove)
        guard await pause(UltimateTicTacToeTiming.zoomToMove, id: id) else { return }
        PaeoniaHaptics.partnerDrawingReceived()
        withAnimation(UltimateTicTacToeMotion.markDraw) {
            hold.hiddenMove = nil
        }
        let rest = input.board.outcome == nil ? UltimateTicTacToeTiming.hold : 0
        guard await pause(UltimateTicTacToeTiming.markDraw + rest, id: id) else { return }
        guard await closeBoard(board, id: id) else { return }
        isGliding = true
        settleFocus()
        if input.board.outcome == nil {
            _ = await pause(UltimateTicTacToeTiming.regroup, id: id)
        }
    }

    /// My move: the mark pops in, the camera pulls back and the board my
    /// partner is sent to pulses once.
    private func playMine(_ event: BoardMoveEvent, id: Int) async {
        guard await pause(UltimateTicTacToeTiming.minePop, id: id) else { return }
        guard await closeBoard(event.move / 9, id: id) else { return }
        isGliding = true
        settleFocus()
        guard input.board.outcome == nil else { return }
        guard await pause(UltimateTicTacToeTiming.pulseDelay, id: id) else { return }
        if let target = input.board.forced {
            pulseCounts[target] += 1
        }
        _ = await pause(UltimateTicTacToeTiming.pulse, id: id)
    }

    /// The closing beat of a small board a move just closed: the strike line
    /// trims in, the cells fade and the big mark scales in. False if cancelled.
    private func closeBoard(_ index: Int, id: Int) async -> Bool {
        guard hold.unclosedBoard == index else { return true }
        withAnimation(UltimateTicTacToeMotion.close) {
            hold.unclosedBoard = nil
        }
        if input.board.boards[index].isWon {
            PaeoniaHaptics.streakContinued()
        }
        return await pause(UltimateTicTacToeTiming.close + UltimateTicTacToeTiming.afterClose, id: id)
    }

    /// The camera waits for the opening zoom into the board I must play in, so
    /// the whole board shows for a moment first.
    private func startIntro() {
        guard zoom.restingFocus != nil else { return }
        run { [weak self] id in
            _ = await self?.pause(UltimateTicTacToeTiming.intro, id: id)
        }
    }

    // MARK: Run

    private func run(_ body: @escaping @MainActor (Int) async -> Void) {
        runID += 1
        let id = runID
        isBusy = true
        isGliding = false
        task = Task { [weak self] in
            await body(id)
            self?.sequenceEnded(id: id)
        }
    }

    private func sequenceEnded(id: Int) {
        guard id == runID else { return }
        task = nil
        isBusy = false
        isGliding = false
        if glowHeld {
            withAnimation(PaeoniaMotion.stateChange) {
                glowHeld = false
            }
        }
        settleFocus()
        if outcomeRequested {
            startOutcome()
        }
    }

    private func cancelSequence() {
        runID += 1
        task?.cancel()
        task = nil
        isBusy = false
        isGliding = false
    }

    /// Sleeps, then says whether this run is still the current one.
    private func pause(_ seconds: TimeInterval, id: Int) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return id == runID && !Task.isCancelled
    }

    // MARK: Camera

    private func settleFocus() {
        requestFocus(zoom.restingFocus, animation: UltimateTicTacToeMotion.regroup)
    }

    private func requestFocus(_ target: Int?, animation: Animation) {
        guard !isUserGesturing else {
            deferredFocus = DeferredFocus(board: target, animation: animation)
            return
        }
        applyFocus(target, animation: animation)
    }

    private func applyFocus(_ target: Int?, animation: Animation) {
        deferredFocus = nil
        guard focus != target else { return }
        withAnimation(animation) {
            focus = target
        }
    }

    // MARK: Outcome

    private func updateOutcome() {
        guard input.showsOutcome != outcomeShown else { return }
        outcomeShown = input.showsOutcome
        guard input.showsOutcome, input.board.outcome != nil else {
            resetOutcome()
            return
        }
        if input.reduceMotion || input.lastMove == nil {
            // A tap that jumped to the end, or Reduce Motion: show it settled.
            cancelOutcome()
            bloomStart = nil
            withAnimation(PaeoniaMotion.stateChange) {
                outcome = .settled(for: input.board.outcome)
            }
        } else if isBusy {
            outcomeRequested = true
        } else {
            startOutcome()
        }
    }

    private func resetOutcome() {
        cancelOutcome()
        outcomeRequested = false
        bloomStart = nil
        withAnimation(PaeoniaMotion.stateChange) {
            outcome = .idle
        }
    }

    private func startOutcome() {
        guard let result = input.board.outcome else { return }
        outcomeRequested = false
        cancelOutcome()
        let id = outcomeRunID
        isPlayingOutcome = true
        requestFocus(nil, animation: UltimateTicTacToeMotion.regroup)
        let beats = UltimateTicTacToeOutcomeScript.beats(lineCount: result.line.count, isDraw: result.winner == nil)
        outcomeTask = Task { [weak self] in
            let start = ContinuousClock.now
            for beat in beats {
                try? await Task.sleep(until: start + .seconds(beat.at), clock: .continuous)
                guard let self, id == self.outcomeRunID, !Task.isCancelled else { return }
                apply(beat.event)
            }
            self?.outcomeFinished(id: id)
        }
    }

    private func cancelOutcome() {
        outcomeRunID += 1
        outcomeTask?.cancel()
        outcomeTask = nil
        isPlayingOutcome = false
    }

    private func outcomeFinished(id: Int) {
        guard id == outcomeRunID else { return }
        outcomeTask = nil
        isPlayingOutcome = false
    }

    private func apply(_ event: UltimateTicTacToeOutcomeScript.Event) {
        switch event {
        case .dimRest:
            withAnimation(UltimateTicTacToeMotion.lightUp) { outcome.isDimmed = true }
        case .light(let rank):
            withAnimation(UltimateTicTacToeMotion.lightUp) { outcome.litCount = rank + 1 }
        case .drawLine:
            withAnimation(UltimateTicTacToeMotion.drawLine) { outcome.lineProgress = 1 }
        case .bloom:
            bloomStart = Date()
        case .clearBloom:
            bloomStart = nil
        case .dipDraw:
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)) {
                outcome.drawOpacity = 0.55
            }
        case .settleDraw:
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                outcome.drawOpacity = UltimateTicTacToeOutcomeState.drawSettledOpacity
            }
        }
    }
}
