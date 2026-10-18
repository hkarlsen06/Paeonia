import SwiftUI

/// Hands its content the seconds since a start date, every frame. A nil start
/// means the highlight is finished, so the content gets an infinite time and
/// nothing redraws.
struct ConnectFourOutcomeClock<Content: View>: View {
    let start: Date?
    @ViewBuilder let content: (TimeInterval) -> Content

    var body: some View {
        if let start {
            TimelineView(.animation) { timeline in
                content(timeline.date.timeIntervalSince(start))
            }
        } else {
            content(.infinity)
        }
    }
}

/// A dark layer over the discs and under the board face. It dims every disc
/// except the winning ones, which the outcome layer redraws above the face. For
/// a draw it dims the whole board and lets it recover.
struct ConnectFourOutcomeVeil: View {
    let geometry: ConnectFourBoardGeometry
    let isDraw: Bool
    let start: Date?

    var body: some View {
        ConnectFourOutcomeClock(start: start) { elapsed in
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                .fill(Color.paeoniaBackgroundSecondary)
                .opacity(ConnectFourOutcomeTiming.veil(elapsed: elapsed, isDraw: isDraw))
                .placedOnBoard(geometry)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The win, drawn above the board face: the winning discs light up one after
/// another from the disc that won, a glowing line runs from it through each
/// winning run, and a petal bloom bursts from the middle of the line.
struct ConnectFourOutcomeLayer: View {
    /// The winner's pieces.
    let style: BoardPieceStyle
    /// The winning cells, as `BoardOutcome.line` lists them.
    let line: [Int]
    /// The disc that won, where the light starts. Nil lights the line in order.
    let origin: Int?
    let geometry: ConnectFourBoardGeometry
    /// When the highlight started, or nil to show it finished.
    let start: Date?
    let bloomSeed: String

    var body: some View {
        ConnectFourOutcomeClock(start: start) { elapsed in
            ZStack(alignment: .topLeading) {
                runLines(elapsed: elapsed)
                ForEach(Array(litOrder.enumerated()), id: \.element) { rank, index in
                    litDisc(at: index, rank: rank, elapsed: elapsed)
                }
                bloom(elapsed: elapsed)
            }
            .frame(width: geometry.width, height: geometry.totalHeight, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One glowing line through the centers of each run. It lies above the face and
    /// under the lit discs, so it shows in the gaps and never crosses a mark.
    private func runLines(elapsed: TimeInterval) -> some View {
        let progress = ConnectFourOutcomeTiming.lineProgress(elapsed: elapsed)
        let diameter = geometry.discDiameter
        let glowStroke = StrokeStyle(lineWidth: diameter * 0.2, lineCap: .round, lineJoin: .round)
        let coreStroke = StrokeStyle(lineWidth: diameter * 0.07, lineCap: .round, lineJoin: .round)
        let runs = ConnectFourBoardGeometry.runs(in: line).map(fromOrigin)
        return ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
            let path = ConnectFourRunShape(points: run.map { geometry.cellCenter(index: $0) })
                .trim(from: 0, to: CGFloat(progress))
            ZStack {
                path.stroke(style.color, style: glowStroke)
                    .shadow(color: style.color, radius: diameter * 0.3)
                path.stroke(Color.paeoniaTextPrimary.opacity(0.85), style: coreStroke)
            }
            .opacity(progress > 0 ? 1 : 0)
        }
    }

    /// The winning cells, nearest the disc that won first.
    private var litOrder: [Int] {
        guard let origin else { return line }
        return line.sorted { Self.steps($0, origin) < Self.steps($1, origin) }
    }

    /// A run that starts at the end nearer the disc that won.
    private func fromOrigin(_ run: [Int]) -> [Int] {
        guard let origin, let first = run.first, let last = run.last else { return run }
        return Self.steps(last, origin) < Self.steps(first, origin) ? run.reversed() : run
    }

    /// How many cells apart two cells are along a row, a column or a diagonal.
    private static func steps(_ cell: Int, _ other: Int) -> Int {
        let columns = ConnectFourBoardGeometry.columns
        return max(abs(cell / columns - other / columns), abs(cell % columns - other % columns))
    }

    /// A copy of a winning disc above the face. It pulses to 112%, then keeps a
    /// ring and a glow.
    private func litDisc(at index: Int, rank: Int, elapsed: TimeInterval) -> some View {
        let diameter = geometry.discDiameter
        let ring = Color.paeoniaTextPrimary.opacity(0.95)
        return ConnectFourDiscView(style: style, diameter: diameter)
            .overlay {
                Circle().strokeBorder(ring, lineWidth: max(1.5, diameter * 0.05))
            }
            .shadow(color: style.color, radius: diameter * 0.22)
            .scaleEffect(ConnectFourOutcomeTiming.scale(rank: rank, elapsed: elapsed))
            .opacity(ConnectFourOutcomeTiming.glow(rank: rank, elapsed: elapsed))
            .position(geometry.cellCenter(index: index))
    }

    /// The bloom has room to spread past the board's edge.
    @ViewBuilder
    private func bloom(elapsed: TimeInterval) -> some View {
        if let start, elapsed < ConnectFourOutcomeTiming.bloomDelay + GamePetalBloom.duration {
            let margin = geometry.width * 0.1
            GamePetalBloom(
                start: start.addingTimeInterval(ConnectFourOutcomeTiming.bloomDelay),
                seed: bloomSeed,
                origin: bloomOrigin(margin: margin),
                intensity: 0.9
            )
            .padding(-margin)
        }
    }

    /// The middle of the winning line, as a point of the bloom's frame, which is
    /// the board plus `margin` on every side.
    private func bloomOrigin(margin: CGFloat) -> UnitPoint {
        let middle = geometry.middle(of: line)
        return UnitPoint(
            x: (middle.x + margin) / (geometry.width + 2 * margin),
            y: (middle.y + margin) / (geometry.totalHeight + 2 * margin)
        )
    }
}

/// A line through a run's cell centers, in the board view's coordinates.
nonisolated struct ConnectFourRunShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
