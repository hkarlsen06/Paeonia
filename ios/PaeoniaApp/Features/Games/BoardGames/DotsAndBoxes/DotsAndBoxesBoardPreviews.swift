import SwiftUI

/// Sample boards, styles and a photo for the previews.
private enum DotsAndBoxesPreviewData {
    static let styles = BoardPieceStyles(
        one: BoardPieceStyle(color: .boardGameMine, mark: nil, initial: "H"),
        two: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "A")
    )

    /// Three closed boxes: player two has the first two and player one has the third.
    static let partwayMoves = [0, 4, 20, 21, 1, 5, 22, 39, 2, 6, 23]

    static func board(_ moves: [Int]) -> DotsAndBoxesBoard {
        DotsAndBoxesBoard.replay(moves) ?? .initial
    }

    /// A finished game. It plays the lines in a fixed scrambled order.
    static func finishedBoard() -> DotsAndBoxesBoard {
        var board = DotsAndBoxesBoard.initial
        for line in (0..<DotsAndBoxesBoard.moveLimit).map({ ($0 * 17 + 3) % DotsAndBoxesBoard.moveLimit }) {
            if let after = board.applying(line) { board = after }
        }
        return board
    }

    /// A gradient with two shapes, so it is easy to see whether the pieces line up.
    static func samplePhoto() -> UIImage {
        let size = CGSize(width: 900, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cgContext = context.cgContext
            let colors = [
                UIColor.paeoniaInkGold.cgColor,
                UIColor.paeoniaAccentSecondary.cgColor,
                UIColor.paeoniaInkLavender.cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1]) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            UIColor.paeoniaInkBlue.setFill()
            cgContext.fillEllipse(in: CGRect(x: 210, y: 90, width: 230, height: 230))
            UIColor.paeoniaWidgetDrawing.withAlphaComponent(0.9).setFill()
            cgContext.fillEllipse(in: CGRect(x: 430, y: 300, width: 200, height: 200))
        }
    }
}

/// A board you can play in the canvas. Both players move from the one phone, and
/// the turn passes the way the real rules pass it.
private struct DotsAndBoxesInteractivePreview: View {
    let photo: UIImage?
    @State private var board: DotsAndBoxesBoard
    @State private var lastMove: BoardMoveEvent?
    @State private var moveCount: Int
    @State private var showsOutcome = false
    private let startingMoves: [Int]

    init(startingMoves: [Int] = [], photo: UIImage? = nil) {
        self.startingMoves = startingMoves
        self.photo = photo
        _board = State(initialValue: DotsAndBoxesPreviewData.board(startingMoves))
        _moveCount = State(initialValue: startingMoves.count)
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            DotsAndBoxesBoardView(
                board: board,
                lastMove: lastMove,
                styles: DotsAndBoxesPreviewData.styles,
                me: .one,
                canPlay: board.outcome == nil,
                showsOutcome: showsOutcome,
                bloomSeed: "preview",
                photo: photo,
                partnerName: "Anna",
                onPlay: play
            )
            Button(action: restart) {
                Text(verbatim: "Restart")
            }
            .buttonStyle(.bordered)
            .tint(.paeoniaAccentPrimary)
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }

    private func play(_ line: Int) {
        let player = board.next
        guard let after = board.applying(line) else { return }
        moveCount += 1
        lastMove = BoardMoveEvent(number: moveCount, move: line, player: player, isMine: player == .one)
        board = after
        if after.outcome != nil {
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                showsOutcome = true
            }
        }
    }

    private func restart() {
        board = DotsAndBoxesPreviewData.board(startingMoves)
        lastMove = nil
        moveCount = startingMoves.count
        showsOutcome = false
    }
}

/// A finished board, shown settled without playing the reveal.
private struct DotsAndBoxesFinishedPreview: View {
    let photo: UIImage?

    var body: some View {
        DotsAndBoxesBoardView(
            board: DotsAndBoxesPreviewData.finishedBoard(),
            lastMove: nil,
            styles: DotsAndBoxesPreviewData.styles,
            me: .one,
            canPlay: false,
            showsOutcome: true,
            bloomSeed: "preview",
            photo: photo,
            partnerName: "Anna",
            onPlay: { _ in }
        )
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }
}

#Preview("Interactive, plain boxes") {
    DotsAndBoxesInteractivePreview(startingMoves: DotsAndBoxesPreviewData.partwayMoves)
}

#Preview("Interactive, with photo") {
    DotsAndBoxesInteractivePreview(
        startingMoves: DotsAndBoxesPreviewData.partwayMoves,
        photo: DotsAndBoxesPreviewData.samplePhoto()
    )
}

#Preview("Finished, plain boxes") {
    DotsAndBoxesFinishedPreview(photo: nil)
}

#Preview("Finished, with photo") {
    DotsAndBoxesFinishedPreview(photo: DotsAndBoxesPreviewData.samplePhoto())
}
