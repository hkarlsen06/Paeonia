import SwiftUI

/// What VoiceOver needs from the screen to describe one small board and pick
/// its cells.
struct UltimateTicTacToeSmallBoardAccess {
    let me: BoardPlayer
    let partnerName: String
    /// True when the next move may use this board and I may play.
    let isUsable: Bool
    /// The empty cells I can play here, as 0 to 8.
    let playableCells: Set<Int>
    /// Picks a cell, 0 to 8. "Lock in" plays it.
    let pick: (Int) -> Void
}

/// One of the nine boards: the surface, the grid, the marks, and once the board
/// is closed, the strike line. The winner's big mark is
/// `UltimateTicTacToeWinnerMarkView`, which the board view draws above the
/// line through the winning boards. Taps are handled by the whole board view,
/// so the cells here only carry VoiceOver.
struct UltimateTicTacToeSmallBoardView: View {
    let index: Int
    /// The side of this small board.
    let side: CGFloat
    let content: UltimateTicTacToeSmallBoardContent
    let emphasis: UltimateTicTacToeEmphasis
    /// The color for `emphasis.glow`. Unused when there is no glow.
    let glowColor: Color
    /// The camera's zoom. The glow shrinks by it, so a zoomed board glows as wide
    /// on screen as an unzoomed one and stays inside the board view's clip.
    let zoomScale: CGFloat
    let styles: BoardPieceStyles
    let pulseCount: Int
    let access: UltimateTicTacToeSmallBoardAccess

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let closedOpacity = 0.3
    private static let positions: [LocalizedStringResource] = [
        .ultimateTicTacToePositionTopLeft, .ultimateTicTacToePositionTop, .ultimateTicTacToePositionTopRight,
        .ultimateTicTacToePositionLeft, .ultimateTicTacToePositionCenter, .ultimateTicTacToePositionRight,
        .ultimateTicTacToePositionBottomLeft, .ultimateTicTacToePositionBottom,
        .ultimateTicTacToePositionBottomRight
    ]

    private var layout: UltimateTicTacToeSmallBoardGeometry {
        UltimateTicTacToeSmallBoardGeometry(side: side)
    }

    var body: some View {
        ZStack {
            surface
            ZStack {
                gridLines
                marks
            }
            .opacity(content.state == .open ? 1 : Self.closedOpacity)
            strike
            accessibilityCells
        }
        .frame(width: side, height: side)
        .opacity(content.state == .full ? Self.closedOpacity : 1)
        .opacity(emphasis.opacity)
        .modifier(UltimateTicTacToePulse(trigger: pulseCount, isEnabled: !reduceMotion))
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : UltimateTicTacToeMotion.markDraw, value: content.cells)
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : UltimateTicTacToeMotion.close, value: content.state)
        .animation(PaeoniaMotion.stateChange, value: emphasis)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(boardLabel)
        .accessibilityHint(access.isUsable ? Text(.ultimateTicTacToeBoardHintA11Y) : Text(verbatim: ""))
        .accessibilityIdentifier("ultimateTicTacToe.board.\(index)")
    }

    // MARK: Drawing

    private var isGlowing: Bool {
        emphasis.glow != .none
    }

    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
        return shape
            .fill(.paeoniaSurfaceSecondary)
            .overlay { shape.fill(glowColor.opacity(isGlowing ? 0.14 : 0)) }
            .overlay {
                shape.strokeBorder(glowColor.opacity(isGlowing ? 0.95 : 0), lineWidth: max(1.5, side * 0.02))
            }
            .shadow(color: glowColor.opacity(isGlowing ? 0.5 : 0), radius: side * 0.06 / zoomScale)
    }

    private var gridLines: some View {
        let layout = self.layout
        return Path { path in
            for step in 1...2 {
                let offset = layout.inset + CGFloat(step) * layout.cellSide
                path.move(to: CGPoint(x: offset, y: layout.inset))
                path.addLine(to: CGPoint(x: offset, y: side - layout.inset))
                path.move(to: CGPoint(x: layout.inset, y: offset))
                path.addLine(to: CGPoint(x: side - layout.inset, y: offset))
            }
        }
        // 0.4 keeps the lines at about 3:1 on the board, so the cells read clearly.
        .stroke(
            Color.paeoniaTextPrimary.opacity(0.4),
            style: StrokeStyle(lineWidth: max(1, side * 0.014), lineCap: .round)
        )
    }

    /// Each mark sits in an overlay on a cell-sized frame, so its transition
    /// scales and opens around the mark and not around the whole small board.
    private var marks: some View {
        ForEach(0..<9, id: \.self) { cell in
            Color.clear
                .frame(width: layout.cellSide, height: layout.cellSide)
                .overlay {
                    if let player = content.cells[cell] {
                        BoardMarkView(style: styles[player], tint: styles[player].color)
                            .frame(width: layout.cellSide * 0.62, height: layout.cellSide * 0.62)
                            .transition(markTransition)
                    }
                }
                .position(layout.cellCenter(cell))
        }
    }

    private var markTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(UltimateTicTacToeInkReveal())
    }

    private var winner: BoardPlayer? {
        if case .won(let player) = content.state { player } else { nil }
    }

    /// The line always exists and only its progress changes, so it trims in
    /// when the board closes instead of appearing whole. It lies under the big
    /// mark in a paler color, so the mark stays clear.
    private var strike: some View {
        let ends = layout.strikeLine(through: content.winningCells)
        let color = winner.map { styles[$0].color } ?? Color.paeoniaAccentPrimary
        return UltimateTicTacToeStrikeShape(
            start: ends?.start ?? .zero,
            end: ends?.end ?? .zero,
            progress: reduceMotion || winner != nil ? 1 : 0
        )
        .stroke(color, style: StrokeStyle(lineWidth: layout.cellSide * 0.14, lineCap: .round))
        .shadow(color: color.opacity(0.4), radius: layout.cellSide * 0.12)
        .saturation(UltimateTicTacToeWinnerMarkView.lineSaturation)
        .opacity(winner == nil ? 0 : UltimateTicTacToeWinnerMarkView.lineOpacity)
    }

    // MARK: VoiceOver

    private var accessibilityCells: some View {
        ForEach(0..<9, id: \.self) { cell in
            let center = layout.hitRect(cell)
            Color.clear
                .frame(width: center.width, height: center.height)
                .position(x: center.midX, y: center.midY)
                .accessibilityElement()
                .accessibilityLabel(cellLabel(cell))
                .accessibilityAddTraits(access.playableCells.contains(cell) ? .isButton : [])
                .accessibilityAction {
                    if access.playableCells.contains(cell) {
                        access.pick(cell)
                    }
                }
                .accessibilityIdentifier("ultimateTicTacToe.cell.\(index * 9 + cell)")
                .allowsHitTesting(false)
        }
    }

    private var boardLabel: Text {
        let number = index + 1
        switch content.state {
        case .open:
            return Text(.ultimateTicTacToeBoardOpenA11Y(number, String(localized: Self.positions[index])))
        case .won(let player):
            if player == access.me {
                return Text(.ultimateTicTacToeBoardWonByYouA11Y(number))
            }
            return Text(.ultimateTicTacToeBoardWonByPartnerA11Y(number, access.partnerName))
        case .full:
            return Text(.ultimateTicTacToeBoardFullA11Y(number))
        }
    }

    private func cellLabel(_ cell: Int) -> Text {
        let row = cell / 3 + 1
        let column = cell % 3 + 1
        guard let player = content.cells[cell] else {
            return Text(.ultimateTicTacToeCellEmptyA11Y(row, column))
        }
        if player == access.me {
            return Text(.ultimateTicTacToeCellYoursA11Y(row, column))
        }
        return Text(.ultimateTicTacToeCellPartnerA11Y(row, column, access.partnerName))
    }
}

/// The winner's big mark over a closed small board. The board view draws all
/// nine above the line through the winning boards, so no line crosses a mark.
struct UltimateTicTacToeWinnerMarkView: View {
    /// Strike lines are paler than the marks they sit under.
    static let lineSaturation = 0.45
    static let lineOpacity = 0.7

    let side: CGFloat
    let content: UltimateTicTacToeSmallBoardContent
    let emphasis: UltimateTicTacToeEmphasis
    let styles: BoardPieceStyles
    let pulseCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if case .won(let winner) = content.state {
                BoardMarkView(style: styles[winner], tint: styles[winner].color)
                    .frame(width: side * 0.7, height: side * 0.7)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: side, height: side)
        .opacity(emphasis.opacity)
        .modifier(UltimateTicTacToePulse(trigger: pulseCount, isEnabled: !reduceMotion))
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : UltimateTicTacToeMotion.close, value: content.state)
        .animation(PaeoniaMotion.stateChange, value: emphasis)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
