import SwiftUI

/// The Ultimate Tic-Tac-Toe board: nine small boards in a 3 by 3 grid, with a
/// camera that zooms into the small board being played.
///
/// - When I must play in one small board, the camera zooms into it and a tap
///   on a cell plays it.
/// - When I may choose, the whole board shows. A tap on a small board zooms in.
///   A tap outside it, a pinch in, or the "Whole board" button zooms out.
/// - My partner's move zooms to the board they played, draws their mark in,
///   rests, and then moves to the board I play in next.
/// - Reduce Motion still zooms, so the cells stay large enough to tap, but the
///   camera cuts instead of gliding and skips the trip to my partner's move.
/// - VoiceOver never zooms. A tap on any cell plays it.
///
/// The screen decides what is on the board. This view animates changes to it.
struct UltimateTicTacToeBoardView: View {
    /// The longest the board grows.
    static let maxSide: CGFloat = 560

    /// How long the board takes to show one move, for the screen's replay.
    static let moveTiming = BoardGameMoveTiming(
        mine: UltimateTicTacToeTiming.mine,
        partner: UltimateTicTacToeTiming.partner
    )

    let board: UltimateTicTacToeBoard
    /// The newest move. The board animates it when `number` changes. Moves
    /// already on the board when the view appears just show.
    let lastMove: BoardMoveEvent?
    let styles: BoardPieceStyles
    let me: BoardPlayer
    /// True while it is my turn and the board takes input.
    let canPlay: Bool
    /// Turns true 0.15 s after the last move landed on a finished game. Then
    /// the outcome highlight plays.
    let showsOutcome: Bool
    let bloomSeed: String
    /// My partner's display name, for VoiceOver.
    let partnerName: String
    let onPlay: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var playback: UltimateTicTacToePlayback
    /// True while the player's fingers pinch. It resets itself when the system
    /// cancels the gesture, so the camera never stays frozen.
    @GestureState private var isPinching = false

    init(
        board: UltimateTicTacToeBoard,
        lastMove: BoardMoveEvent?,
        styles: BoardPieceStyles,
        me: BoardPlayer,
        canPlay: Bool,
        showsOutcome: Bool,
        bloomSeed: String,
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
        self.partnerName = partnerName
        self.onPlay = onPlay
        // Moves and an outcome already on screen when the view first appears
        // just show, so the playback starts having seen them.
        _playback = State(initialValue: UltimateTicTacToePlayback(
            UltimateTicTacToePlayback.Input(
                board: board,
                lastMove: lastMove,
                canPlay: canPlay,
                showsOutcome: showsOutcome,
                zoomEnabled: false,
                reduceMotion: false
            )
        ))
    }

    private var zoomEnabled: Bool {
        !voiceOverEnabled
    }

    /// The beats of a move: zoom to it, hold it back, draw it in. Reduce Motion
    /// shows the move at once.
    private var playsMoveBeats: Bool {
        zoomEnabled && !reduceMotion
    }

    private var playbackInput: UltimateTicTacToePlayback.Input {
        UltimateTicTacToePlayback.Input(
            board: board,
            lastMove: lastMove,
            canPlay: canPlay,
            showsOutcome: showsOutcome,
            zoomEnabled: zoomEnabled,
            reduceMotion: reduceMotion
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
        .onChange(of: isPinching) { _, active in
            playback.setUserGesture(active: active)
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
                .simultaneousGesture(pinch)
            bloom(geometry)
            wholeBoardButton
        }
        .frame(width: side, height: side)
    }

    private var look: UltimateTicTacToeLook {
        let pending = UltimateTicTacToeHold.pending(
            lastMove: lastMove,
            handled: playback.handledMoveNumber,
            board: board,
            enabled: playsMoveBeats
        )
        return UltimateTicTacToeLook(
            board: board,
            hold: pending ?? playback.hold,
            focus: playback.focus,
            glowHeld: playback.glowHeld || (pending != nil && lastMove?.isMine == false),
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
            outcomeLines(geometry)
        }
    }

    private func glowColor(for glow: UltimateTicTacToeEmphasis.Glow) -> Color {
        switch glow {
        case .none: .paeoniaAccentPrimary
        case .next: styles[board.next].color
        case .winner: styles[board.outcome?.winner ?? board.next].color
        }
    }
}

extension UltimateTicTacToeBoardView {
    // MARK: Outcome

    /// The thick glowing line through the winning boards' centers.
    @ViewBuilder
    private func outcomeLines(_ geometry: UltimateTicTacToeBoardGeometry) -> some View {
        if let result = board.outcome, let winner = result.winner {
            let color = styles[winner].color
            ForEach(UltimateTicTacToeOutcomeState.winningRows(of: result), id: \.self) { row in
                if let ends = geometry.lineEnds(through: row) {
                    UltimateTicTacToeStrikeShape(
                        start: ends.start,
                        end: ends.end,
                        progress: playback.outcome.lineProgress
                    )
                    .stroke(color, style: StrokeStyle(lineWidth: geometry.smallSide * 0.07, lineCap: .round))
                    .shadow(color: color.opacity(0.9), radius: geometry.smallSide * 0.1)
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
        switch playback.zoom.tap(at: point, geometry: geometry, focus: playback.focus) {
        case .focus(let target):
            PaeoniaHaptics.selection()
            playback.choose(.board(target))
        case .play(let move):
            PaeoniaHaptics.selection()
            onPlay(move)
        case .zoomOut:
            playback.choose(.wholeBoard)
        case .ignore:
            break
        }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .updating($isPinching) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if UltimateTicTacToeZoom.isZoomOutPinch(value.magnification),
                   playback.focus != nil,
                   !playback.isBusy {
                    playback.choose(.wholeBoard)
                }
            }
    }

    private var showsWholeBoardButton: Bool {
        playback.focus != nil && canPlay && !playback.isBusy
    }

    /// The button lives in its own view so its fade does not take over the
    /// zoom, which changes in the same update.
    private var wholeBoardButton: some View {
        ZStack {
            if showsWholeBoardButton {
                Button {
                    playback.choose(.wholeBoard)
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.ultimateTicTacToeWholeBoardA11Y))
                .accessibilityIdentifier("ultimateTicTacToe.wholeBoard")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(PaeoniaMotion.stateChange, value: showsWholeBoardButton)
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
            play: { cell in playFromAccessibility(index * 9 + cell) }
        )
    }

    private func playFromAccessibility(_ move: Int) {
        guard canPlay, board.isLegal(move) else { return }
        PaeoniaHaptics.selection()
        onPlay(move)
    }
}
