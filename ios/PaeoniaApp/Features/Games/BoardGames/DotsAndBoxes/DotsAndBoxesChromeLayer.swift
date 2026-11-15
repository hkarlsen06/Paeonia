import SwiftUI

/// What sits on top of the boxes: the halo under the partner's last lines, the
/// dotted guides, the line the finger is about to draw, the drawn lines and the
/// dots. When the photo shows whole, the board fades this whole layer to a faint
/// outline.
struct DotsAndBoxesChromeLayer: View {
    let board: DotsAndBoxesBoard
    let geometry: DotsAndBoxesBoardGeometry
    let styles: BoardPieceStyles
    let me: BoardPlayer
    /// The move to animate, if there is one. Its line grows from the middle.
    let animatedMove: BoardMoveEvent?
    /// The lines of the partner's latest turn.
    let lastTurn: Set<Int>
    /// The line under the finger, or nil when no touch is picking one.
    let candidate: Int?
    /// One counter per dot. A dot pulses when its counter goes up.
    let dotPulses: [Int]
    let canPlay: Bool

    private static let guideOpacityWhenWaiting = 0.55
    private static let candidateOpacity = 0.4
    private static let haloOpacity = 0.6
    /// The halo's width as a share of the line's.
    private static let haloWidth: CGFloat = 3.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var drawnLines: [Int] {
        board.lines.indices.filter { board.lines[$0] != nil }
    }

    var body: some View {
        let drawn = drawnLines
        let activeDots = Set(drawn.flatMap { DotsAndBoxesBoardGeometry.dotIndices(of: $0) })
        ZStack(alignment: .topLeading) {
            lastTurnHalos
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

    /// A soft, wider copy of each of the partner's last lines under it. It shows
    /// once the line has reached its dots.
    private var lastTurnHalos: some View {
        ZStack(alignment: .topLeading) {
            ForEach(lastTurn.filter { board.lines.indices.contains($0) }.sorted(), id: \.self) { line in
                if let segment = geometry.segment(of: line), let owner = board.lines[line] {
                    let frame = geometry.frame(of: segment)
                        .insetBy(dx: -geometry.lineThickness, dy: -geometry.lineThickness)
                    DotsAndBoxesLineShape(
                        isHorizontal: segment.isHorizontal,
                        length: segment.length,
                        thickness: geometry.lineThickness * Self.haloWidth,
                        progress: 1
                    )
                    .fill(styles[owner].color.opacity(Self.haloOpacity))
                    .blur(radius: geometry.lineThickness * 0.6)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .boardLastTurnHalo(afterLanding: DotsAndBoxesMotion.lineLanding)
                }
            }
        }
        .animation(BoardLastTurnHalo.fadeOut(reduceMotion: reduceMotion), value: lastTurn)
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
