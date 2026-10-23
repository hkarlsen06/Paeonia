import SwiftUI

/// The Ultimate Tic-Tac-Toe board: nine small boards in a 3 by 3 grid. The
/// whole board shows unless the player pinches into a small board.
///
/// - When I must play in one small board, a tap anywhere in its part of the
///   board picks its nearest cell.
/// - When I may choose, a tap on an open small board picks it and the other
///   open boards stop glowing. A tap on another open board switches, and a tap
///   on a cell of the picked board picks the cell.
/// - A picked cell shows my mark faintly. "Lock in" under the board plays it.
///   The screen owns the pick and the button.
/// - A move draws in on the whole board. Then a spark flies from its cell to
///   the small board the next player is sent to, which lights up and pulses
///   once. When the next player may choose, every open board lights up instead.
/// - A pinch out over a small board zooms into it to look closely. A pinch in,
///   a tap outside it, or a new move zooms back out.
/// - Reduce Motion shows a move at once with no spark, and the glow fades in.
/// - VoiceOver never zooms. Activating a cell picks it.
/// - A replay of a finished game never zooms, and its moves make no sparks,
///   haptics or sounds.
///
/// The screen decides what is on the board. This view animates changes to it.
struct UltimateTicTacToeBoardView: View {
    /// The longest the board grows.
    static let maxSide: CGFloat = 560

    /// How long the board takes to show one move, for the screen's replay. A
    /// move takes as long as its beat, so a move that ends the game is over once
    /// its small board has closed and the outcome follows without a gap.
    static let moveTiming = BoardGameMoveTiming(
        mine: .seconds(UltimateTicTacToeTiming.minePop + UltimateTicTacToeTiming.spark),
        partner: .seconds(UltimateTicTacToeTiming.markDraw + UltimateTicTacToeTiming.spark),
        openLeadIn: UltimateTicTacToeTiming.openLeadIn,
        exact: { event, board in
            (board as? UltimateTicTacToeBoard).map { .seconds(UltimateTicTacToeTiming.beat(of: event, on: $0)) }
        }
    )

    let board: UltimateTicTacToeBoard
    /// The newest move. The board animates it when `number` changes. Moves
    /// already on the board when the view appears just show.
    let lastMove: BoardMoveEvent?
    let styles: BoardPieceStyles
    let me: BoardPlayer
    /// True while it is my turn and the board takes input.
    let canPlay: Bool
    /// What I picked on this turn. The screen resets it when the board or the
    /// turn changes.
    @Binding var pick: UltimateTicTacToePick
    /// Turns true 0.15 s after the last move landed on a finished game. Then
    /// the outcome highlight plays.
    let showsOutcome: Bool
    let bloomSeed: String
    /// My partner's display name, for VoiceOver.
    let partnerName: String
    /// A finished game played again from "Past games".
    let isReplay: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var playback: UltimateTicTacToePlayback

    init(
        board: UltimateTicTacToeBoard,
        lastMove: BoardMoveEvent?,
        styles: BoardPieceStyles,
        me: BoardPlayer,
        canPlay: Bool,
        pick: Binding<UltimateTicTacToePick>,
        showsOutcome: Bool,
        bloomSeed: String,
        partnerName: String = "",
        isReplay: Bool = false
    ) {
        self.board = board
        self.lastMove = lastMove
        self.styles = styles
        self.me = me
        self.canPlay = canPlay
        _pick = pick
        self.showsOutcome = showsOutcome
        self.bloomSeed = bloomSeed
        self.partnerName = partnerName
        self.isReplay = isReplay
        // Moves and an outcome already on screen when the view first appears
        // just show, so the playback starts having seen them.
        _playback = State(initialValue: UltimateTicTacToePlayback(
            UltimateTicTacToePlayback.Input(
                board: board,
                lastMove: lastMove,
                showsOutcome: showsOutcome,
                playsBeats: false,
                reduceMotion: false,
                isReplay: isReplay
            )
        ))
    }

    private var zoomEnabled: Bool {
        !voiceOverEnabled && !isReplay
    }

    private var playbackInput: UltimateTicTacToePlayback.Input {
        UltimateTicTacToePlayback.Input(
            board: board,
            lastMove: lastMove,
            showsOutcome: showsOutcome,
            playsBeats: zoomEnabled && !reduceMotion,
            reduceMotion: reduceMotion,
            isReplay: isReplay
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            if side > 0 {
                viewport(UltimateTicTacToeBoardGeometry(side: side))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: Self.maxSide)
        .onChange(of: playbackInput, initial: true) { _, input in
            playback.update(input)
        }
        .onDisappear { playback.stop() }
    }

    // MARK: Viewport

    private func viewport(_ geometry: UltimateTicTacToeBoardGeometry) -> some View {
        let side = geometry.side
        let transform = geometry.transform(focusing: playback.focus)
        return ZStack(alignment: .topLeading) {
            boardLayer(geometry, zoomScale: transform.scale)
                .frame(width: side, height: side)
                .scaleEffect(transform.scale, anchor: .topLeading)
                .offset(transform.translation)
                .frame(width: side, height: side, alignment: .topLeading)
                // A little past the edge, so a glowing or pulsing board at the edge
                // keeps its whole glow. The neighbors of a zoomed board stay hidden.
                .clipShape(Rectangle().inset(by: -geometry.glowBleed))
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    handleTap(at: transform.invert(value.location), geometry: geometry)
                })
                .simultaneousGesture(pinch(transform, geometry: geometry))
            bloom(geometry)
        }
        .frame(width: side, height: side)
    }

    private var look: UltimateTicTacToeLook {
        let pending = UltimateTicTacToeHold.pending(
            lastMove: lastMove,
            handled: playback.handledMoveNumber,
            board: board,
            enabled: zoomEnabled && !reduceMotion
        )
        return UltimateTicTacToeLook(
            board: board,
            hold: pending ?? playback.hold,
            focus: playback.focus,
            playingBoard: pick.playingBoard(on: board),
            glowHeld: playback.glowHeld || pending != nil,
            outcome: playback.outcome
        )
    }

    private func boardLayer(_ geometry: UltimateTicTacToeBoardGeometry, zoomScale: CGFloat) -> some View {
        let look = self.look
        return ZStack(alignment: .topLeading) {
            ForEach(0..<9, id: \.self) { index in
                let rect = geometry.smallRect(index)
                let emphasis = look.emphasis(of: index)
                UltimateTicTacToeSmallBoardView(
                    index: index,
                    side: geometry.smallSide,
                    content: look.content(of: index),
                    emphasis: emphasis,
                    glowColor: glowColor(for: emphasis.glow),
                    zoomScale: zoomScale,
                    styles: styles,
                    pulseCount: playback.pulseCounts[index],
                    access: access(for: index)
                )
                .position(x: rect.midX, y: rect.midY)
            }
            pendingMark(geometry)
            outcomeLines(geometry)
            ForEach(0..<9, id: \.self) { index in
                let rect = geometry.smallRect(index)
                UltimateTicTacToeWinnerMarkView(
                    side: geometry.smallSide,
                    content: look.content(of: index),
                    emphasis: look.emphasis(of: index),
                    styles: styles,
                    pulseCount: playback.pulseCounts[index]
                )
                .position(x: rect.midX, y: rect.midY)
            }
            sparkLayer(geometry)
        }
    }

    private func glowColor(for glow: UltimateTicTacToeEmphasis.Glow) -> Color {
        switch glow {
        case .none: .paeoniaAccentPrimary
        case .next: styles[board.next].color
        case .winner: styles[board.outcome?.winner ?? board.next].color
        }
    }

    /// The spark after a move, in the next player's color.
    @ViewBuilder
    private func sparkLayer(_ geometry: UltimateTicTacToeBoardGeometry) -> some View {
        if let spark = playback.spark {
            UltimateTicTacToeSparkView(spark: spark, geometry: geometry, color: styles[board.next].color)
        }
    }

    /// My mark, faint, in the cell I picked. A new pick fades it in afresh.
    @ViewBuilder
    private func pendingMark(_ geometry: UltimateTicTacToeBoardGeometry) -> some View {
        if canPlay, let move = pick.move(on: board) {
            let rect = geometry.cellRect(board: move / 9, cell: move % 9)
            UltimateTicTacToePendingMark(style: styles[me])
                .frame(width: rect.width * 0.62, height: rect.height * 0.62)
                .position(x: rect.midX, y: rect.midY)
                .id(move)
                .transition(.opacity)
        }
    }
}

extension UltimateTicTacToeBoardView {
    // MARK: Outcome

    /// The thick glowing line through the winning boards' centers. It lies
    /// under the winners' big marks in a paler color, so it shows in the gaps.
    @ViewBuilder
    private func outcomeLines(_ geometry: UltimateTicTacToeBoardGeometry) -> some View {
        if let result = board.outcome, let winner = result.winner {
            let color = styles[winner].color
            ForEach(UltimateTicTacToeOutcomeState.winningRows(of: result), id: \.self) { row in
                if let ends = geometry.lineEnds(through: playback.outcome.fromOrigin(row)) {
                    UltimateTicTacToeStrikeShape(
                        start: ends.start,
                        end: ends.end,
                        progress: playback.outcome.lineProgress
                    )
                    .stroke(color, style: StrokeStyle(lineWidth: geometry.smallSide * 0.07, lineCap: .round))
                    .shadow(color: color.opacity(0.6), radius: geometry.smallSide * 0.1)
                    .saturation(UltimateTicTacToeWinnerMarkView.lineSaturation)
                    .opacity(UltimateTicTacToeWinnerMarkView.lineOpacity)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// The petal bloom from the middle of the winning line. It sits in a larger
    /// frame so petals can leave the board.
    @ViewBuilder
    private func bloom(_ geometry: UltimateTicTacToeBoardGeometry) -> some View {
        if let start = playback.bloomStart,
           let result = board.outcome,
           let row = UltimateTicTacToeOutcomeState.winningRows(of: result).first,
           let middle = geometry.lineMidpoint(through: row) {
            let frameSide = geometry.side * 1.5
            GamePetalBloom(
                start: start,
                seed: bloomSeed,
                origin: UnitPoint(
                    x: 0.5 + (middle.x - geometry.side / 2) / frameSide,
                    y: 0.5 + (middle.y - geometry.side / 2) / frameSide
                )
            )
            .frame(width: frameSide, height: frameSide)
            .frame(width: geometry.side, height: geometry.side)
        }
    }

    // MARK: Input

    private func handleTap(at point: CGPoint, geometry: UltimateTicTacToeBoardGeometry) {
        if playback.isPlayingOutcome {
            playback.settleOutcome()
            return
        }
        if playback.isBusy {
            playback.skip()
            return
        }
        switch pick.tap(at: point, on: board, canPlay: canPlay, geometry: geometry, focus: playback.focus) {
        case .pick(let next):
            choose(next)
        case .zoomOut:
            playback.setFocus(nil)
        case .ignore:
            break
        }
    }

    private func choose(_ next: UltimateTicTacToePick) {
        PaeoniaHaptics.selection()
        GameSound.tap.play(volume: 0.6)
        withAnimation(PaeoniaMotion.stateChange) {
            pick = next
        }
    }

    /// A spread over a small board zooms into it, and a pinch in zooms back
    /// out. Nothing zooms while a move plays, so the spark stays in view.
    private func pinch(
        _ transform: UltimateTicTacToeViewTransform,
        geometry: UltimateTicTacToeBoardGeometry
    ) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard zoomEnabled, !playback.isBusy else { return }
                playback.setFocus(UltimateTicTacToeZoom.focus(
                    afterPinch: value.magnification,
                    from: playback.focus,
                    startingAt: transform.invert(value.startLocation),
                    geometry: geometry
                ))
            }
    }

    // MARK: VoiceOver

    private func access(for index: Int) -> UltimateTicTacToeSmallBoardAccess {
        let isUsable = canPlay && board.openBoards.contains(index)
        let playable = (0..<9).filter { board.cells[index * 9 + $0] == nil }
        return UltimateTicTacToeSmallBoardAccess(
            me: me,
            partnerName: partnerName,
            isUsable: isUsable,
            playableCells: isUsable ? Set(playable) : [],
            pick: { cell in pickFromAccessibility(index * 9 + cell) }
        )
    }

    /// One path for everyone: activating a cell picks it, and "Lock in" plays
    /// it. In free choice the cell's small board becomes the picked board too.
    private func pickFromAccessibility(_ move: Int) {
        guard canPlay, board.isLegal(move) else { return }
        choose(.move(move))
        let cell = move % 9
        AccessibilityNotification.Announcement(
            String(localized: .ultimateTicTacToeCellPickedA11Y(cell / 3 + 1, cell % 3 + 1))
        ).post()
    }
}
