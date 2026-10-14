import SwiftUI

/// The 16 boxes under the lines. An open box is a very faint tile. A closed box
/// shows its piece of the photo, or its owner's color.
struct DotsAndBoxesBoxLayer: View {
    let board: DotsAndBoxesBoard
    let geometry: DotsAndBoxesBoardGeometry
    let styles: BoardPieceStyles
    let photo: UIImage?
    /// The move to animate, if there is one. A box it closed appears with a pop.
    let animatedMove: BoardMoveEvent?
    /// 0 while the game is on, 1 once the outcome lifted the tints off the photo.
    let reveal: Double
    /// Without a photo, the boxes the loser closed dim once the game ended.
    let losersDimmed: Bool
    /// Goes up when the outcome pulses the boxes of a plain board.
    let outcomePulse: Int

    private struct ClosedBox: Identifiable {
        let id: Int
        let owner: BoardPlayer
    }

    private static let openOpacity = 0.45

    private var closedBoxes: [ClosedBox] {
        board.boxes.indices.compactMap { box in
            board.boxes[box].map { ClosedBox(id: box, owner: $0) }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<DotsAndBoxesBoard.boxTotal, id: \.self) { box in
                let rect = geometry.boxRect(box).insetBy(dx: geometry.pieceGap, dy: geometry.pieceGap)
                RoundedRectangle(cornerRadius: geometry.pieceCornerRadius, style: .continuous)
                    .fill(.paeoniaSurfaceSecondary.opacity(Self.openOpacity))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            ForEach(closedBoxes) { closed in
                DotsAndBoxesBoxView(
                    box: closed.id,
                    style: styles[closed.owner],
                    geometry: geometry,
                    photo: photo,
                    reveal: reveal,
                    isDimmed: photo == nil && losersDimmed && closed.owner != board.outcome?.winner,
                    pulseTrigger: pulses(closed.id) ? outcomePulse : 0,
                    pulseDelay: pulseDelay(closed.id),
                    entranceDelay: entranceDelay(closed.id)
                )
            }
        }
    }

    /// The boxes that pulse when the game ends on a plain board: the winner's,
    /// or every box after a draw.
    private func pulses(_ box: Int) -> Bool {
        guard let outcome = board.outcome else { return false }
        return outcome.winner == nil || outcome.line.contains(box)
    }

    private func pulseDelay(_ box: Int) -> TimeInterval {
        guard let outcome = board.outcome else { return 0 }
        if outcome.winner == nil {
            return Double(box) * DotsAndBoxesMotion.drawStagger
        }
        return Double(outcome.line.firstIndex(of: box) ?? 0) * DotsAndBoxesMotion.winnerStagger
    }

    /// How long a box waits before it pops in, or nil when it was not closed by
    /// the move being animated.
    private func entranceDelay(_ box: Int) -> TimeInterval? {
        guard let animatedMove else { return nil }
        let closed = Self.closedBoxes(by: animatedMove.move, on: board)
        guard let index = closed.firstIndex(of: box) else { return nil }
        return DotsAndBoxesMotion.firstBoxDelay + Double(index) * DotsAndBoxesMotion.boxStagger
    }

    /// The boxes the newest line closed, in ascending order. A closed box that
    /// touches the newest line was closed by it, because that line was the last
    /// one drawn.
    static func closedBoxes(by line: Int, on board: DotsAndBoxesBoard) -> [Int] {
        DotsAndBoxesBoard.boxes(touching: line).filter { board.boxes[$0] != nil }
    }
}
