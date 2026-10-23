import Observation
import SwiftUI

/// The animations the board plays. The spans match `UltimateTicTacToeTiming`.
enum UltimateTicTacToeMotion {
    static let camera = Animation.spring(duration: 0.45, bounce: 0.08)
    static let markDraw = Animation.spring(duration: UltimateTicTacToeTiming.markDraw, bounce: 0.3)
    static let close = Animation.spring(duration: UltimateTicTacToeTiming.close, bounce: 0.2)
    static let snap = PaeoniaMotion.buttonPress
    static let lightUp = PaeoniaMotion.stateChange
    static let drawLine = PaeoniaMotion.standardCurve(duration: UltimateTicTacToeOutcomeScript.lineDuration)
}

/// Plays the board's beats and owns the one value that says where the camera
/// is. The camera shows the whole board unless the player pinches into a small
/// board, and a new move or the outcome brings it back to the whole board.
///
/// Each beat checks a run id after it sleeps, so a move that arrives while the
/// last one is still playing finishes the old one at once and starts its own.
@MainActor
@Observable
final class UltimateTicTacToePlayback {
    /// Everything the playback reads from the screen.
    struct Input: Equatable {
        var board: UltimateTicTacToeBoard
        var lastMove: BoardMoveEvent?
        var showsOutcome: Bool
        /// A move draws in, closes its small board and sends a spark. Off for
        /// Reduce Motion, VoiceOver and a replay, where a move just shows.
        var playsBeats: Bool
        /// The camera cuts instead of gliding, and the outcome shows settled.
        var reduceMotion: Bool
        /// A finished game played again: moves make no haptics or sounds.
        var isReplay = false
    }

    // MARK: What the board draws

    /// The small board the player pinched into, or nil for the whole board.
    private(set) var focus: Int?
    private(set) var hold = UltimateTicTacToeHold.none
    private(set) var glowHeld = false
    /// The spark in flight, from the cell just played to the board it sends
    /// the next player to.
    private(set) var spark: UltimateTicTacToeSpark?
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

    @ObservationIgnored private var input: Input
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var outcomeRunID = 0
    @ObservationIgnored private var outcomeTask: Task<Void, Never>?
    @ObservationIgnored private var outcomeShown: Bool
    @ObservationIgnored private var outcomeRequested = false

    /// Starts from what is on the screen. Moves already on the board and an
    /// outcome already showing just show, with no beat.
    init(_ input: Input) {
        self.input = input
        handledMoveNumber = input.lastMove?.number
        outcomeShown = input.showsOutcome
        if input.showsOutcome {
            outcome = .settled(for: input.board.outcome)
        }
    }

    // MARK: Entry points

    /// Takes the screen's newest state. Call it whenever any part changes.
    func update(_ new: Input) {
        let boardChanged = new.board != input.board
        input = new
        if boardChanged {
            setFocus(nil)
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
    }

    /// Moves the camera to a small board, or to the whole board with nil.
    func setFocus(_ target: Int?) {
        guard focus != target else { return }
        withAnimation(input.reduceMotion ? nil : UltimateTicTacToeMotion.camera) {
            focus = target
        }
    }

    /// A tap while a move plays: show the end of it now.
    func skip() {
        guard isBusy else { return }
        cancelSequence()
        spark = nil
        withAnimation(UltimateTicTacToeMotion.snap) {
            hold = .none
            glowHeld = false
        }
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

    /// The view is going away. Stops every beat and keeps what was shown.
    func stop() {
        cancelSequence()
        cancelOutcome()
        hold = .none
        glowHeld = false
        spark = nil
        bloomStart = nil
        if outcomeShown {
            outcome = .settled(for: input.board.outcome)
        }
    }
}

/// The beats: a move's sequence and the outcome highlight.
extension UltimateTicTacToePlayback {
    // MARK: Moves

    private func handle(_ event: BoardMoveEvent) {
        handledMoveNumber = event.number
        cancelSequence()
        spark = nil
        guard input.playsBeats, let arriving = UltimateTicTacToeHold.arriving(event, on: input.board) else {
            withAnimation(UltimateTicTacToeMotion.snap) {
                hold = .none
                glowHeld = false
            }
            playHaptics(for: event)
            return
        }
        withAnimation(UltimateTicTacToeMotion.snap) {
            hold = arriving
            glowHeld = true
        }
        run { [weak self] id in
            await self?.play(event, id: id)
        }
    }

    /// Without the beats, the marks and lines animate on their own. Only the
    /// haptics are left.
    private func playHaptics(for event: BoardMoveEvent) {
        guard !input.isReplay else { return }
        if !event.isMine {
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.mark.play(volume: 0.85)
        }
        if closedState(of: event)?.isWon == true {
            PaeoniaHaptics.streakContinued()
            GameSound.stamp.play()
        }
    }

    private func closedState(of event: BoardMoveEvent) -> UltimateTicTacToeBoard.SmallBoard? {
        input.board.boards.indices.contains(event.move / 9) ? input.board.boards[event.move / 9] : nil
    }

    /// A move on the whole board: my mark pops in or my partner's draws in, a
    /// small board it closed closes, and a spark flies to the board the next
    /// player is sent to. When they may choose, every open board lights up as
    /// the beat ends instead. `UltimateTicTacToeTiming.beat` adds up the same
    /// steps.
    private func play(_ event: BoardMoveEvent, id: Int) async {
        if event.isMine {
            guard await pause(UltimateTicTacToeTiming.minePop, id: id) else { return }
        } else {
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.mark.play(volume: 0.85)
            withAnimation(UltimateTicTacToeMotion.markDraw) {
                hold.hiddenMove = nil
            }
            guard await pause(UltimateTicTacToeTiming.markDraw, id: id) else { return }
        }
        guard await closeBoard(event.move / 9, id: id) else { return }
        guard input.board.outcome == nil, let target = input.board.forced else { return }
        spark = UltimateTicTacToeSpark(move: event.move, target: target, start: .now)
        guard await pause(UltimateTicTacToeTiming.spark, id: id) else { return }
        spark = nil
        withAnimation(UltimateTicTacToeMotion.lightUp) {
            glowHeld = false
        }
        pulseCounts[target] += 1
    }

    /// The closing beat of a small board a move just closed: the strike line
    /// trims in, the cells fade and the big mark scales in. A move that ends the
    /// game goes straight on to the outcome. False if cancelled.
    private func closeBoard(_ index: Int, id: Int) async -> Bool {
        guard hold.unclosedBoard == index else { return true }
        withAnimation(UltimateTicTacToeMotion.close) {
            hold.unclosedBoard = nil
        }
        if input.board.boards[index].isWon {
            PaeoniaHaptics.streakContinued()
            GameSound.stamp.play()
        }
        let rest = input.board.outcome == nil ? UltimateTicTacToeTiming.afterClose : 0
        return await pause(UltimateTicTacToeTiming.close + rest, id: id)
    }

    // MARK: Run

    private func run(_ body: @escaping @MainActor (Int) async -> Void) {
        runID += 1
        let id = runID
        isBusy = true
        task = Task { [weak self] in
            await body(id)
            self?.sequenceEnded(id: id)
        }
    }

    private func sequenceEnded(id: Int) {
        guard id == runID else { return }
        task = nil
        isBusy = false
        spark = nil
        if glowHeld {
            withAnimation(UltimateTicTacToeMotion.lightUp) {
                glowHeld = false
            }
        }
        if outcomeRequested {
            startOutcome()
        }
    }

    private func cancelSequence() {
        runID += 1
        task?.cancel()
        task = nil
        isBusy = false
    }

    /// Sleeps, then says whether this run is still the current one.
    private func pause(_ seconds: TimeInterval, id: Int) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return id == runID && !Task.isCancelled
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
        outcome.origin = input.lastMove.map { $0.move / 9 }
        setFocus(nil)
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
