import SwiftUI

/// A rounded line between two dots. `progress` 0 is a seed at the middle and 1
/// is the whole line. While it grows the stroke is a little thicker, and the
/// spring's overshoot squeezes it slightly under its resting width, so the line
/// feels like it snaps onto the dots.
struct DotsAndBoxesLineShape: Shape {
    let isHorizontal: Bool
    /// The distance between the two dots.
    let length: CGFloat
    let thickness: CGFloat
    var progress: CGFloat

    private static let growingExtraWidth: CGFloat = 0.4

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let reach = max(length / 2 * min(max(progress, 0), 1), 0.01)
        let width = max(thickness * (1 + Self.growingExtraWidth * (1 - progress)), 0)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var line = Path()
        if isHorizontal {
            line.move(to: CGPoint(x: center.x - reach, y: center.y))
            line.addLine(to: CGPoint(x: center.x + reach, y: center.y))
        } else {
            line.move(to: CGPoint(x: center.x, y: center.y - reach))
            line.addLine(to: CGPoint(x: center.x, y: center.y + reach))
        }
        return line.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// One drawn line in its player's color. A line that just landed grows from its
/// middle to both dots. A line that was already on the board just shows.
struct DotsAndBoxesLineView: View {
    let segment: DotsAndBoxesBoardGeometry.Segment
    let frame: CGRect
    let thickness: CGFloat
    let color: Color

    private let animates: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat
    @State private var opacity: Double

    init(
        segment: DotsAndBoxesBoardGeometry.Segment,
        frame: CGRect,
        thickness: CGFloat,
        color: Color,
        animates: Bool
    ) {
        self.segment = segment
        self.frame = frame
        self.thickness = thickness
        self.color = color
        self.animates = animates
        _progress = State(initialValue: animates ? 0 : 1)
        _opacity = State(initialValue: animates ? 0 : 1)
    }

    var body: some View {
        DotsAndBoxesLineShape(
            isHorizontal: segment.isHorizontal,
            length: segment.length,
            thickness: thickness,
            progress: progress
        )
        .fill(color)
        .frame(width: frame.width, height: frame.height)
        .opacity(opacity)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
        .onAppear { play() }
    }

    private func play() {
        guard animates else { return }
        if reduceMotion {
            progress = 1
            withAnimation(DotsAndBoxesMotion.fade) { opacity = 1 }
        } else {
            opacity = 1
            withAnimation(DotsAndBoxesMotion.lineSnap) { progress = 1 }
        }
    }
}

/// One dot. It grows a little once a line touches it, and pulses when `pulse`
/// goes up, which the board does for both dots of a new line.
struct DotsAndBoxesDotView: View {
    let position: CGPoint
    let diameter: CGFloat
    let pulse: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(.paeoniaTextPrimary.opacity(0.85))
            .frame(width: diameter, height: diameter)
            .keyframeAnimator(initialValue: 1.0, trigger: pulse) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1.0, duration: DotsAndBoxesMotion.dotPulseDelay)
                    CubicKeyframe(1.5, duration: 0.12)
                    CubicKeyframe(1.0, duration: 0.24)
                }
            }
            .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: diameter)
            .position(position)
            .allowsHitTesting(false)
    }
}

/// The faint dotted guides on every line nobody has drawn yet.
struct DotsAndBoxesGuideLayer: View {
    let geometry: DotsAndBoxesBoardGeometry
    let drawn: Set<Int>

    /// Dots per guide. The guide starts and ends on a dot, so the pattern looks
    /// the same at both ends.
    private static let guideDotCount: CGFloat = 10

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            for line in 0..<DotsAndBoxesBoard.moveLimit where !drawn.contains(line) {
                guard let segment = geometry.segment(of: line) else { continue }
                path.move(to: segment.start)
                path.addLine(to: segment.end)
            }
            let style = StrokeStyle(
                lineWidth: geometry.guideThickness,
                lineCap: .round,
                dash: [0.01, geometry.cell / Self.guideDotCount]
            )
            context.stroke(path, with: .color(Color.paeoniaTextTertiary.opacity(0.6)), style: style)
        }
        .allowsHitTesting(false)
    }
}
