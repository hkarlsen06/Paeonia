import SwiftUI

/// The interactive Dots and Boxes board: 5 by 5 dots, 16 boxes and 40 lines,
/// square and as wide as it is given (at most 560 points).
///
/// Playing. Touch the board and the line you would draw shows at 40% in your
/// color. Slide to change it, lift to draw it. Every point of the board picks
/// one line (see `DotsAndBoxesBoardGeometry.line(at:)`). Sliding off the board
/// before lifting cancels.
///
/// Showing moves. The board animates the newest move when `lastMove.number`
/// changes: the line grows from its middle, its dots pulse, and each box it
/// closed pops in. Moves already on the board when the view appears just show.
///
/// Ending. When `showsOutcome` turns true, a board with a photo lifts the tints
/// and closes the gaps so the photo shows whole. A plain board pulses the
/// winner's boxes and dims the rest. Then the petal bloom bursts. The result
/// haptic belongs to the screen, so the board plays none for the result.
struct DotsAndBoxesBoardView: View {
    let board: DotsAndBoxesBoard
    /// The newest move. The board animates it when `number` changes. Moves
    /// already on the board when the view appears just show.
    let lastMove: BoardMoveEvent?
    let styles: BoardPieceStyles
    let me: BoardPlayer
    /// True while it is my turn and the board takes input.
    let canPlay: Bool
    /// Turns true 0.15 s after the last move landed on a finished game. Then
    /// the outcome reveal plays.
    let showsOutcome: Bool
    let bloomSeed: String
    /// The hidden photo, or nil for plain boxes (no photo, or still loading).
    let photo: UIImage?
    /// The partner's name for VoiceOver. Empty reads as "Your partner".
    let partnerName: String
    let onPlay: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    /// Where the current touch started and where the finger is now.
    @GestureState private var stroke: (start: CGPoint, end: CGPoint)?
    /// The number of the move that was already on the board when the view
    /// appeared. The board does not animate it.
    @State private var baseline: Int
    @State private var dotPulses = Array(repeating: 0, count: DotsAndBoxesBoardGeometry.dotTotal)
    /// 0 while the game is on, 1 once the outcome lifted the tints off the photo.
    @State private var reveal: Double
    @State private var losersDimmed: Bool
    @State private var outcomePlayed: Bool
    @State private var outcomePulse = 0
    @State private var bloomStart: Date?

    init(
        board: DotsAndBoxesBoard,
        lastMove: BoardMoveEvent?,
        styles: BoardPieceStyles,
        me: BoardPlayer,
        canPlay: Bool,
        showsOutcome: Bool,
        bloomSeed: String,
        photo: UIImage?,
        partnerName: String = "",
        onPlay: @escaping (Int) -> Void
    ) {
        self.board = board
        self.lastMove = lastMove
        self.styles = styles
        self.me = me
        self.canPlay = canPlay
        self.showsOutcome = showsOutcome
        self.bloomSeed = bloomSeed
        self.photo = photo
        self.partnerName = partnerName
        self.onPlay = onPlay
        // A board that opens on a finished game shows the settled state without replaying it.
        let settled = showsOutcome && board.outcome != nil
        _baseline = State(initialValue: lastMove?.number ?? 0)
        _reveal = State(initialValue: settled ? 1 : 0)
        _losersDimmed = State(initialValue: settled && board.outcome?.winner != nil)
        _outcomePlayed = State(initialValue: settled)
    }

    // MARK: Derived

    /// The newest move, unless it was already on the board when the view appeared.
    private var animatedMove: BoardMoveEvent? {
        guard let lastMove, lastMove.number != baseline else { return nil }
        return lastMove
    }

    private var outcomeIsShowing: Bool {
        showsOutcome && board.outcome != nil
    }

    private var partnerLabel: String {
        partnerName.isEmpty ? String(localized: .dotsAndBoxesPartnerFallback) : partnerName
    }

    /// With a photo, the lines and dots fade to an outline as the photo shows whole.
    private var chromeOpacity: Double {
        photo == nil ? 1 : 1 - (1 - DotsAndBoxesMotion.restingChrome) * reveal
    }

    // MARK: Body

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            // The overlay sits on the square, not the wider frame, so the frame centers the board.
            .overlay {
                GeometryReader { proxy in
                    content(DotsAndBoxesBoardGeometry(side: min(proxy.size.width, proxy.size.height)))
                }
            }
            .frame(maxWidth: DotsAndBoxesBoardGeometry.maxSide)
            .task(id: lastMove) { await playMove() }
            .task(id: outcomeIsShowing) { await playOutcome() }
    }

    private func content(_ geometry: DotsAndBoxesBoardGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            visuals(geometry)
                .accessibilityHidden(true)
            DotsAndBoxesAccessibilityLayer(
                board: board,
                geometry: geometry,
                me: me,
                partnerName: partnerLabel,
                canPlay: canPlay,
                onPlay: play
            )
            touchLayer(geometry)
            bloomLayer(geometry)
        }
        .frame(width: geometry.side, height: geometry.side)
        .onChange(of: candidate(in: geometry)) { old, new in
            // Sliding from one line to another ticks. The first touch and the lift do not.
            if old != nil, new != nil {
                PaeoniaHaptics.selection()
                GameSound.tick.play(volume: 0.4)
            }
        }
    }

    private func visuals(_ geometry: DotsAndBoxesBoardGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            DotsAndBoxesBoxLayer(
                board: board,
                geometry: geometry,
                styles: styles,
                photo: photo,
                animatedMove: animatedMove,
                reveal: reveal,
                losersDimmed: losersDimmed,
                outcomePulse: outcomePulse
            )
            DotsAndBoxesChromeLayer(
                board: board,
                geometry: geometry,
                styles: styles,
                me: me,
                animatedMove: animatedMove,
                candidate: candidate(in: geometry),
                dotPulses: dotPulses,
                canPlay: canPlay
            )
            .opacity(chromeOpacity)
        }
    }

    // MARK: Input

    /// Takes the touch while it is my turn. VoiceOver draws through the box
    /// actions instead, so a tap that VoiceOver makes up never draws a line.
    private func touchLayer(_ geometry: DotsAndBoxesBoardGeometry) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($stroke) { value, state, _ in
                        state = (value.startLocation, value.location)
                    }
                    .onEnded { value in
                        if let line = pick(from: value.startLocation, to: value.location, geometry) {
                            play(line)
                        }
                    }
            )
            .allowsHitTesting(canPlay && !voiceOverEnabled)
            .accessibilityHidden(true)
    }

    /// The open line a touch from `start` to `end` would draw, if any.
    private func pick(from start: CGPoint, to end: CGPoint, _ geometry: DotsAndBoxesBoardGeometry) -> Int? {
        guard canPlay, geometry.touchBounds.contains(end), let line = geometry.line(from: start, to: end) else {
            return nil
        }
        return board.lines[line] == nil ? line : nil
    }

    private func candidate(in geometry: DotsAndBoxesBoardGeometry) -> Int? {
        stroke.flatMap { pick(from: $0.start, to: $0.end, geometry) }
    }

    private func play(_ line: Int) {
        guard canPlay, board.lines.indices.contains(line), board.lines[line] == nil else { return }
        onPlay(line)
    }

    @ViewBuilder
    private func bloomLayer(_ geometry: DotsAndBoxesBoardGeometry) -> some View {
        if let bloomStart {
            GamePetalBloom(start: bloomStart, seed: bloomSeed)
                .frame(width: geometry.side * 1.3, height: geometry.side * 1.3)
                .frame(width: geometry.side, height: geometry.side)
        }
    }

    // MARK: A new move

    /// The beats of the newest move that are not drawn: the haptics, the dot
    /// pulses and the VoiceOver announcement. The line and the boxes animate
    /// themselves when they appear.
    private func playMove() async {
        guard let move = lastMove else {
            baseline = 0
            return
        }
        guard move.number != baseline else { return }
        if !reduceMotion {
            for index in DotsAndBoxesBoardGeometry.dotIndices(of: move.move) {
                dotPulses[index] += 1
            }
        }
        if move.isMine {
            PaeoniaHaptics.selection()
        } else {
            PaeoniaHaptics.partnerDrawingReceived()
        }
        GameSound.mark.play(volume: move.isMine ? 1 : 0.85)
        let closed = DotsAndBoxesBoxLayer.closedBoxes(by: move.move, on: board)
        announce(closed: closed.count, by: move)
        var elapsed: TimeInterval = 0
        for index in closed.indices {
            let delay = DotsAndBoxesMotion.firstBoxDelay + Double(index) * DotsAndBoxesMotion.boxStagger
            try? await Task.sleep(for: .seconds(delay - elapsed))
            guard !Task.isCancelled else { return }
            PaeoniaHaptics.streakTick(intensity: 0.7)
            GameSound.stamp.play(volume: 0.8)
            elapsed = delay
        }
    }

    /// Tells VoiceOver about closed boxes. The last box of a game is left to the
    /// result, which the screen announces.
    private func announce(closed count: Int, by move: BoardMoveEvent) {
        guard count > 0, board.outcome == nil else { return }
        let message: LocalizedStringResource = switch (move.isMine, count) {
        case (true, 1): .dotsAndBoxesAnnounceMineOne
        case (true, _): .dotsAndBoxesAnnounceMineTwo
        case (false, 1): .dotsAndBoxesAnnouncePartnerOne(partnerLabel)
        case (false, _): .dotsAndBoxesAnnouncePartnerTwo(partnerLabel)
        }
        AccessibilityNotification.Announcement(String(localized: message)).post()
    }

    // MARK: The outcome

    /// Plays the reveal once per finished game. A view that opens on a finished
    /// game starts settled, and a new game clears the reveal.
    private func playOutcome() async {
        guard outcomeIsShowing, let outcome = board.outcome else {
            resetOutcome()
            return
        }
        guard !outcomePlayed else { return }
        outcomePlayed = true
        guard !reduceMotion else {
            withAnimation(DotsAndBoxesMotion.fade) {
                reveal = 1
                losersDimmed = outcome.winner != nil
            }
            return
        }
        withAnimation(DotsAndBoxesMotion.lift) { reveal = 1 }
        // The dimming only shows on a plain board. It is set either way, so a photo
        // that disappears later leaves the same board as one that opens finished.
        withAnimation(DotsAndBoxesMotion.dim) { losersDimmed = outcome.winner != nil }
        if photo == nil {
            outcomePulse += 1
        }
        try? await Task.sleep(for: .seconds(DotsAndBoxesMotion.bloomDelay))
        guard !Task.isCancelled, outcome.winner != nil else { return }
        bloomStart = Date()
        try? await Task.sleep(for: .seconds(GamePetalBloom.duration + 0.1))
        bloomStart = nil
    }

    private func resetOutcome() {
        guard outcomePlayed else { return }
        outcomePlayed = false
        reveal = 0
        losersDimmed = false
        outcomePulse = 0
        bloomStart = nil
    }
}
