import SwiftUI

/// Every board remains inspectable. Only a legal empty square can change the
/// pending move; the game's existing Lock in button still commits it.
struct UltimateTicTacToeNativeControls: View {
    let board: UltimateTicTacToeBoard
    let me: BoardPlayer
    let partnerName: String
    let canPlay: Bool
    let turn: BoardGameTurnLabel
    let selectedMove: Int?
    let onPick: (Int) -> Void
    @State private var inspectedBoard: Int

    init(
        board: UltimateTicTacToeBoard, me: BoardPlayer, partnerName: String,
        canPlay: Bool, turn: BoardGameTurnLabel, selectedMove: Int?, onPick: @escaping (Int) -> Void
    ) {
        self.board = board
        self.me = me
        self.partnerName = partnerName
        self.canPlay = canPlay
        self.turn = turn
        self.selectedMove = selectedMove
        self.onPick = onPick
        _inspectedBoard = State(initialValue: selectedMove.map { $0 / 9 } ?? board.openBoards.first ?? 0)
    }

    var body: some View {
        Section {
            Text(turn.spoken(partnerName: partnerName) ?? .boardGamesResultTitleDraw)
                .accessibilityAddTraits(.isHeader)
            if board.outcome == nil {
                playableBoards
            }
        }

        Section {
            // Each board remains inspectable in a native scrolling list, including closed boards.
            Picker(selection: $inspectedBoard) {
                ForEach(0..<9) { index in
                    boardLabel(index)
                        .fixedSize(horizontal: false, vertical: true)
                        .tag(index)
                        .accessibilityIdentifier("ultimateTicTacToe.native.board.\(index)")
                }
            } label: {
                Label(.ultimateTicTacToeControlsViewBoard, systemImage: "square.grid.3x3")
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("ultimateTicTacToe.native.board")
        } header: {
            boardLabel(inspectedBoard)
        }

        Section {
            ForEach(0..<9) { cell in
                let move = inspectedBoard * 9 + cell
                Button {
                    guard canPlay, board.isLegal(move) else { return }
                    onPick(move)
                } label: {
                    selectionLabel(cellLabel(move), selected: selectedMove == move)
                        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                }
                .disabled(!canPlay || !board.isLegal(move))
                .accessibilityValue(
                    selectedMove == move ? Text(.ultimateTicTacToeControlsSelected) : Text(verbatim: "")
                )
                .accessibilityAddTraits(selectedMove == move ? .isSelected : [])
                .accessibilityIdentifier("ultimateTicTacToe.native.cell.\(move)")
            }
        } header: {
            Text(.ultimateTicTacToeControlsChooseSquare)
        }
    }

    @ViewBuilder
    private var playableBoards: some View {
        if let forced = board.forced {
            Text(.ultimateTicTacToeControlsForcedBoard(
                forced + 1, String(localized: UltimateTicTacToeSmallBoardView.positions[forced])
            ))
        } else {
            Text(.ultimateTicTacToeControlsOpenBoards(
                ListFormatter.localizedString(byJoining: board.openBoards.map { String($0 + 1) })
            ))
        }
    }

    private func selectionLabel(_ title: Text, selected: Bool) -> some View {
        HStack {
            title
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PaeoniaSpacing.space8)
            if selected {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
    }

    private func boardLabel(_ index: Int) -> Text {
        switch board.boards[index] {
        case .open:
            return Text(.ultimateTicTacToeBoardOpenA11Y(
                index + 1, String(localized: UltimateTicTacToeSmallBoardView.positions[index])
            ))
        case .won(let player):
            if player == me { return Text(.ultimateTicTacToeBoardWonByYouA11Y(index + 1)) }
            return Text(.ultimateTicTacToeBoardWonByPartnerA11Y(index + 1, partnerName))
        case .full:
            return Text(.ultimateTicTacToeBoardFullA11Y(index + 1))
        }
    }

    private func cellLabel(_ move: Int) -> Text {
        let owner = board.cells[move]
        let state = owner == nil ? String(localized: .gamesCellEmpty)
            : owner == me ? String(localized: .gamesCellYours) : partnerName
        return Text(.ultimateTicTacToeBoardCell(inspectedBoard + 1, move % 9 / 3 + 1, move % 3 + 1, state))
    }
}
