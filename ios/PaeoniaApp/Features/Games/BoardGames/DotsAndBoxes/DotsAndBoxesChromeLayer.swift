import SwiftUI

/// What sits on top of the boxes: the dotted guides, the line the finger is
/// about to draw, the drawn lines and the dots. When the photo shows whole, the
/// board fades this whole layer to a faint outline.
struct DotsAndBoxesChromeLayer: View {
    let board: DotsAndBoxesBoard
    let geometry: DotsAndBoxesBoardGeometry
    let styles: BoardPieceStyles
    let me: BoardPlayer
    /// The move to animate, if there is one. Its line grows from the middle.
    let animatedMove: BoardMoveEvent?
    /// The line under the finger, or nil when no touch is picking one.
    let candidate: Int?
    /// One counter per dot. A dot pulses when its counter goes up.
    let dotPulses: [Int]
    let canPlay: Bool

    private static let guideOpacityWhenWaiting = 0.55
    private static let candidateOpacity = 0.4

    private var drawnLines: [Int] {
        board.lines.indices.filter { board.lines[$0] != nil }
    }

    var body: some View {
        let drawn = drawnLines
        let activeDots = Set(drawn.flatMap { DotsAndBoxesBoardGeometry.dotIndices(of: $0) })
        ZStack(alignment: .topLeading) {
            DotsAndBoxesGuideLayer(geometry: geometry, drawn: Set(drawn))
                .opacity(canPlay ? 1 : Self.guideOpacityWhenWaiting)
                .animation(PaeoniaMotion.stateChange, value: canPlay)
            candidateLine
            ForEach(drawn, id: \.self) { line in
                lineView(line)
            }
            ForEach(0..<DotsAndBoxesBoardGeometry.dotTotal, id: \.self) { index in
                DotsAndBoxesDotView(
                    position: geometry.dotPosition(index: index),
                    diameter: activeDots.contains(index) ? geometry.activeDotDiameter : geometry.dotDiameter,
                    pulse: dotPulses[index]
                )
            }
        }
        .compositingGroup()
    }

    @ViewBuilder
    private func lineView(_ line: Int) -> some View {
        if let segment = geometry.segment(of: line), let owner = board.lines[line] {
            DotsAndBoxesLineView(
                segment: segment,
                frame: geometry.frame(of: segment),
                thickness: geometry.lineThickness,
                color: styles[owner].color,
                animates: animatedMove?.move == line
            )
        }
    }

    /// The press highlight: the line the player would draw by lifting the finger.
    private var candidateLine: some View {
        ZStack {
            if let candidate, let segment = geometry.segment(of: candidate) {
                let frame = geometry.frame(of: segment)
                DotsAndBoxesLineShape(
                    isHorizontal: segment.isHorizontal,
                    length: segment.length,
                    thickness: geometry.lineThickness,
                    progress: 1
                )
                .fill(styles[me].color.opacity(Self.candidateOpacity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .transition(.opacity)
            }
        }
        .animation(DotsAndBoxesMotion.fade, value: candidate)
        .allowsHitTesting(false)
    }
}
