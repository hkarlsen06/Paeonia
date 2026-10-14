import SwiftUI

/// A board you can play in Xcode previews. You play player one. When it is
/// player two's turn the preview plays a random move as the partner, so both
/// drop animations show. After a win or a draw it turns `showsOutcome` on once
/// the last disc has landed, as the real screen does.
private struct ConnectFourPlayablePreview: View {
    @State private var board = ConnectFourBoard.initial
    @State private var lastMove: BoardMoveEvent?
    @State private var showsOutcome = false

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            ConnectFourBoardView(
                board: board,
                lastMove: lastMove,
                styles: ConnectFourPreviewStyles.styles,
                me: .one,
                canPlay: board.outcome == nil && board.next == .one,
                showsOutcome: showsOutcome,
                bloomSeed: "preview",
                onPlay: { apply($0, isMine: true) },
                partnerName: "Maja"
            )
            Button {
                board = .initial
                lastMove = nil
                showsOutcome = false
            } label: {
                Text(verbatim: "New game")
            }
            .buttonStyle(.bordered)
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paeoniaBackgroundSecondary)
        .task(id: board.discCount) { await continueGame() }
    }

    private func apply(_ column: Int, isMine: Bool) {
        guard let next = board.applying(column) else { return }
        lastMove = BoardMoveEvent(number: board.discCount + 1, move: column, player: board.next, isMine: isMine)
        board = next
    }

    private func continueGame() async {
        if board.outcome != nil {
            // The last drop takes at most 0.8 seconds. The screen waits 0.15 more.
            try? await Task.sleep(for: .seconds(0.95))
            guard !Task.isCancelled else { return }
            showsOutcome = true
        } else if board.next == .two {
            try? await Task.sleep(for: .seconds(0.9))
            let open = (0..<ConnectFourBoard.moveLimit).filter { board.isLegal($0) }
            guard !Task.isCancelled, let column = open.randomElement() else { return }
            apply(column, isMine: false)
        }
    }
}

/// A finished board with the result already on screen, as when you reopen a game.
private struct ConnectFourFinishedPreview: View {
    let moves: [Int]

    var body: some View {
        ConnectFourBoardView(
            board: ConnectFourBoard.replay(moves) ?? .initial,
            lastMove: nil,
            styles: ConnectFourPreviewStyles.styles,
            me: .one,
            canPlay: false,
            showsOutcome: true,
            bloomSeed: "preview",
            onPlay: { _ in }
        )
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paeoniaBackgroundSecondary)
    }
}

private enum ConnectFourPreviewStyles {
    /// Player one has a drawn mark (a heart). Player two has no mark yet, so their initial shows.
    static let styles = BoardPieceStyles(
        one: BoardPieceStyle(color: .boardGameMine, mark: UIImage(systemName: "heart.fill"), initial: "H"),
        two: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "M")
    )
}

#Preview("Playable") {
    ConnectFourPlayablePreview()
}

#Preview("Won on the bottom row") {
    ConnectFourFinishedPreview(moves: [0, 0, 1, 1, 2, 2, 3])
}

#Preview("Won in a column") {
    ConnectFourFinishedPreview(moves: [3, 4, 3, 4, 3, 4, 3])
}
