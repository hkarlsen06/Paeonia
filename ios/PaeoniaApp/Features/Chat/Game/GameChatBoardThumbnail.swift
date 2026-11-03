import SwiftUI

/// Static boards reuse the rules and board views without a replay, controls or outcome effects.
struct GameChatBoardThumbnail: View {
    let kind: GameKind
    let moves: [Int]
    let me: BoardPlayer
    var colors = LudoColorPair.standard

    var body: some View {
        switch kind {
        case .connectFour:
            if let board = ConnectFourBoard.replay(moves) {
                BoardGameReplayBoards.connectFour(replay(board))
            }
        case .dotsAndBoxes:
            if let board = DotsAndBoxesBoard.replay(moves) {
                BoardGameReplayBoards.dotsAndBoxes(replay(board))
            }
        case .ultimateTicTacToe:
            if let board = UltimateTicTacToeBoard.replay(moves) {
                UltimateTicTacToeBoardView(
                    board: board, lastMove: nil, styles: Self.styles(me: me), me: me,
                    canPlay: false, pick: .constant(.none), showsOutcome: false,
                    bloomSeed: "", partnerName: "", isReplay: true)
            }
        case .ludo:
            if let board = LudoBoard.replay(moves) { ludo(board) }
        default: EmptyView()
        }
    }

    static func styles(me: BoardPlayer) -> BoardPieceStyles {
        BoardPieceStyles(
            one: .init(color: me == .one ? .boardGameMine : .boardGamePartner, mark: nil, initial: "", owner: .one),
            two: .init(color: me == .two ? .boardGameMine : .boardGamePartner, mark: nil, initial: "", owner: .two))
    }

    private func replay<Board: BoardGameRules>(_ board: Board) -> BoardGameReplayBoard<Board> {
        .init(
            board: board, lastMove: nil, styles: Self.styles(me: me), me: me,
            showsOutcome: false, bloomSeed: "", partnerName: "")
    }

    /// Uses the scene's actual board coordinates without starting a RealityKit scene in every row.
    private func ludo(_ board: LudoBoard) -> some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 15
            func rect(_ point: LudoGridPoint, diameter: CGFloat = 0.8) -> CGRect {
                CGRect(
                    x: (point.column + 0.5 - diameter / 2) * unit,
                    y: (point.row + 0.5 - diameter / 2) * unit,
                    width: diameter * unit, height: diameter * unit)
            }
            for index in 0..<LudoBoard.trackLength {
                let point = LudoBoardGeometry.point(of: .track(index), viewer: me)
                context.fill(
                    Path(roundedRect: rect(point), cornerRadius: unit * 0.15), with: .color(.paeoniaSurfaceHighlight))
            }
            for player in [BoardPlayer.one, .two] {
                let color = player == me ? colors.mine.color : colors.partner.color
                let yard = LudoBoardGeometry.yardCenter(corner: LudoBoardGeometry.corner(of: player), viewer: me)
                context.fill(
                    Path(roundedRect: rect(yard, diameter: 5), cornerRadius: unit), with: .color(color.opacity(0.3)))
                for progress in 52...57 {
                    let square = LudoBoard.square(player: player, pawn: 0, progress: progress)
                    context.fill(
                        Path(ellipseIn: rect(LudoBoardGeometry.point(of: square, viewer: me))),
                        with: .color(color.opacity(0.5)))
                }
            }
            for (index, placement) in LudoBoardGeometry.placements(board: board, viewer: me).enumerated() {
                let player: BoardPlayer = index < LudoBoard.pawnsPerPlayer ? .one : .two
                context.fill(
                    Path(ellipseIn: rect(placement.point, diameter: 1.35)),
                    with: .color(player == me ? colors.mine.color : colors.partner.color))
            }
        }
    }
}
