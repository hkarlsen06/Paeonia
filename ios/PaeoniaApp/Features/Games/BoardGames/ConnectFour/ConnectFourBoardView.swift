import SwiftUI

/// The Connect Four board. It takes the width it is given (up to `maxWidth`) and
/// is as tall as it is wide: the board face plus a lane above it for the
/// hovering disc. It takes no size from the screen.
///
/// Discs sit behind the board face, so a falling disc shows through the holes.
/// When `lastMove.number` changes the board animates that move. Moves already on
/// the board when the view appears just show. The screen around the board owns
/// the turn, the result panel and the timing of `showsOutcome`.
struct ConnectFourBoardView: View {
    let board: ConnectFourBoard
    /// The newest move. The board animates it when `number` changes.
    let lastMove: BoardMoveEvent?
    let styles: BoardPieceStyles
    /// The player this phone plays as.
    let me: BoardPlayer
    /// True while it is my turn and the board takes input.
    let canPlay: Bool
    /// Turns true 0.15 seconds after the last move landed on a finished game.
    /// Then the result highlight plays. If it turns true while a disc is still
    /// falling, the highlight waits for the disc.
    let showsOutcome: Bool
    /// Seeds the petal bloom, for example "<game id>:<game number>".
    let bloomSeed: String
    let onPlay: (Int) -> Void
    /// The partner's name for the VoiceOver announcement "[Name] dropped a disc
    /// in column 3", posted when their move arrives. Leave it nil to announce
    /// nothing, for a screen that announces moves itself.
    var partnerName: String?
    /// The board taps once as the result highlight reaches its peak (a firm tap
    /// for a win, a soft one for a draw). Set it false if the screen plays that tap.
    var playsOutcomeHaptics = true
    /// The widest the board grows, in points. The caller may cap it further.
    var maxWidth = ConnectFourBoardGeometry.defaultMaxWidth

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The newest move number the board has started to show. Nil until the view appears.
    @State private var presentedNumber: Int?
    @State private var falling: [ConnectFourFallingDisc] = []
    /// Nil until the screen asks for a highlight. Then the view follows `showsOutcome`.
    @State private var stage: ConnectFourOutcomeStage?

    private struct RestingDisc: Identifiable {
        let index: Int
        let player: BoardPlayer
        var id: Int { index }
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = ConnectFourBoardGeometry(width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                visuals(geometry)
                    .accessibilityHidden(true)
                ConnectFourInputLayer(
                    geometry: geometry,
                    board: board,
                    myStyle: styles[me],
                    me: me,
                    canPlay: canPlay,
                    moveNumber: lastMove?.number,
                    onPlay: onPlay
                )
            }
            .frame(width: geometry.width, height: geometry.totalHeight, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.connectFourBoardLabel))
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxWidth)
        .onAppear { presentedNumber = lastMove?.number ?? 0 }
        .onChange(of: lastMove?.number) { present() }
        .onChange(of: board) { old, new in
            if new.discCount < old.discCount { reset() }
        }
        .onChange(of: board.outcome) {
            if board.outcome == nil { stage = .idle }
        }
        .onChange(of: showsOutcome) { updateOutcome() }
        .task(id: effectiveStage.startDate) { await playOutcomeBeats() }
    }

    // MARK: Layers

    /// Back to front: the dark panel, resting discs, falling discs, the dimming
    /// veil, the board face, then the winning discs, line and bloom.
    private func visuals(_ geometry: ConnectFourBoardGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            ConnectFourBoardBacking(geometry: geometry)
            restingDiscs(geometry)
            ForEach(falling) { disc in
                ConnectFourFallingDiscView(disc: disc, style: styles[disc.player], geometry: geometry) { id in
                    falling.removeAll { $0.id == id }
                }
            }
            outcomeVeil(geometry)
            ConnectFourBoardFace(geometry: geometry)
            outcomeHighlight(geometry)
        }
    }

    private func restingDiscs(_ geometry: ConnectFourBoardGeometry) -> some View {
        let hidden = hiddenIndexes
        let discs = board.cells.enumerated().compactMap { index, player -> RestingDisc? in
            guard let player, !hidden.contains(index) else { return nil }
            return RestingDisc(index: index, player: player)
        }
        return ForEach(discs) { disc in
            ConnectFourDiscView(style: styles[disc.player], diameter: geometry.discDiameter)
                .position(geometry.cellCenter(index: disc.index))
        }
    }

    @ViewBuilder
    private func outcomeVeil(_ geometry: ConnectFourBoardGeometry) -> some View {
        if let outcome = board.outcome, effectiveStage != .idle {
            ConnectFourOutcomeVeil(geometry: geometry, isDraw: outcome.winner == nil, start: effectiveStage.startDate)
        }
    }

    @ViewBuilder
    private func outcomeHighlight(_ geometry: ConnectFourBoardGeometry) -> some View {
        if let outcome = board.outcome, let winner = outcome.winner, effectiveStage != .idle {
            ConnectFourOutcomeLayer(
                style: styles[winner],
                line: outcome.line,
                origin: lastMove.flatMap { board.topDiscIndex(column: $0.move) },
                geometry: geometry,
                start: effectiveStage.startDate,
                bloomSeed: bloomSeed
            )
        }
    }

    // MARK: Moves

    /// Cells whose disc is not drawn at rest: the discs falling now, and the
    /// disc of a move that has arrived but has not started to fall yet. Without
    /// the second, the disc would show in its cell for one frame first.
    private var hiddenIndexes: Set<Int> {
        var hidden = Set(falling.map(\.index))
        if let lastMove, let presentedNumber, lastMove.number > presentedNumber,
           let index = board.topDiscIndex(column: lastMove.move) {
            hidden.insert(index)
        }
        return hidden
    }

    /// Starts the fall of a move that just arrived.
    private func present() {
        guard let move = lastMove else {
            presentedNumber = 0
            falling = []
            return
        }
        let previous = presentedNumber ?? 0
        presentedNumber = move.number
        guard move.number > previous,
              let index = board.topDiscIndex(column: move.move),
              board.cells[index] == move.player
        else { return }
        let row = index / ConnectFourBoardGeometry.columns
        let motion = ConnectFourDropMotion.forMove(landingRow: row, isMine: move.isMine, reduceMotion: reduceMotion)
        falling.append(ConnectFourFallingDisc(move: move, index: index, start: Date(), motion: motion))
        announce(move)
    }

    private func announce(_ move: BoardMoveEvent) {
        guard !move.isMine, let partnerName, !partnerName.isEmpty else { return }
        AccessibilityNotification.Announcement(
            String(localized: .connectFourPartnerDropped(partnerName, move.move + 1))
        ).post()
    }

    /// A new game starts on the same view.
    private func reset() {
        falling = []
        stage = .idle
    }

    // MARK: Result

    private var effectiveStage: ConnectFourOutcomeStage {
        stage ?? (showsOutcome && board.outcome != nil ? .settled : .idle)
    }

    private func updateOutcome() {
        guard showsOutcome, let outcome = board.outcome else {
            stage = .idle
            return
        }
        guard !reduceMotion else {
            stage = .settled
            if playsOutcomeHaptics { playHaptic(for: outcome) }
            return
        }
        let discsLand = falling.map(\.end).max() ?? .distantPast
        stage = .playing(max(Date(), discsLand))
    }

    /// The tap at the peak, then the move to the settled state.
    private func playOutcomeBeats() async {
        guard let start = effectiveStage.startDate, let outcome = board.outcome else { return }
        await ConnectFourClock.sleep(until: start.addingTimeInterval(ConnectFourOutcomeTiming.bloomDelay))
        guard !Task.isCancelled else { return }
        if playsOutcomeHaptics { playHaptic(for: outcome) }
        let settle = ConnectFourOutcomeTiming.settleTime(
            cellCount: outcome.line.count,
            isDraw: outcome.winner == nil,
            bloomDuration: GamePetalBloom.duration
        )
        await ConnectFourClock.sleep(until: start.addingTimeInterval(settle))
        guard !Task.isCancelled else { return }
        stage = .settled
    }

    private func playHaptic(for outcome: BoardOutcome) {
        if outcome.winner == nil {
            PaeoniaHaptics.partnerDrawingReceived()
        } else {
            PaeoniaHaptics.answerRevealed()
        }
    }

}
