import SwiftUI

/// The picture on the welcome screen: the Home Screen drawing widget with a note from a
/// partner on it, laid out like `PaeoniaWidgetEntryView` (the drawing on top, who drew
/// it and when underneath). The note is `WelcomeDoodleInk`, handwritten "miss you" with
/// a heart. On launch the pen writes it once, stroke by stroke, then it holds still.
/// Under Reduce Motion it shows finished.
///
/// The tile grows to the size of a large widget and shrinks on short screens. The
/// whole tile is one image to VoiceOver.
struct WelcomeWidgetDoodle: View {
    /// The tile's side when the screen has room for it.
    private static let maxSide: CGFloat = 280
    /// The smallest it gets before the welcome screen scrolls instead.
    private static let minSide: CGFloat = 150
    /// How long after the screen is revealed the pen lands, so the tile has dropped
    /// into place first.
    private static let writingDelay: TimeInterval = 0.45

    private let ink = WelcomeDoodleInk.current

    @Environment(\.launchContentRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the pen lands. Nil until the screen is revealed.
    @State private var writingStart: Date?
    @State private var isWritten = false

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)

                note
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            footer
        }
        // The system's content margin on a widget.
        .padding(PaeoniaSpacing.space16)
        .aspectRatio(1, contentMode: .fit)
        .homeWidgetCardSurface()
        .frame(minHeight: Self.minSide, idealHeight: Self.minSide, maxHeight: Self.maxSide)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.welcomeDoodleAccessibility))
        .accessibilityAddTraits(.isImage)
        .task(id: revealed) {
            guard revealed, writingStart == nil, !reduceMotion else {
                return
            }
            writingStart = .now.addingTimeInterval(Self.writingDelay)
            try? await Task.sleep(for: .seconds(Self.writingDelay + ink.duration))
            isWritten = true
        }
    }

    /// Redrawn every frame only while the pen is moving.
    private var note: some View {
        TimelineView(.animation(paused: writingStart == nil || isWritten || reduceMotion)) { timeline in
            Canvas { context, size in
                draw(in: &context, side: size.width, elapsed: elapsed(at: timeline.date))
            }
        }
        .clipShape(DrawingCanvasShape())
        .accessibilityHidden(true)
    }

    private func elapsed(at date: Date) -> TimeInterval {
        if isWritten || reduceMotion {
            return .infinity
        }
        guard let writingStart else {
            return 0
        }
        return max(0, date.timeIntervalSince(writingStart))
    }

    /// Draws each stroke as far as the pen has got by `elapsed`, as short segments so
    /// the line can thin where the pen lands and lifts.
    private func draw(in context: inout GraphicsContext, side: CGFloat, elapsed: TimeInterval) {
        let scale = side / WelcomeDoodleInk.canvasSide

        for stroke in ink.strokes where elapsed > stroke.start {
            let time = min(1, (elapsed - stroke.start) / stroke.duration)
            // Quick to start and slowing a little into the end, like a hand.
            let reached = stroke.length * CGFloat(1 - pow(1 - time, 1.6))
            let shading = GraphicsContext.Shading.color(color(of: stroke.ink))

            for index in stroke.points.indices.dropFirst() {
                let startDistance = stroke.distances[index - 1]
                guard startDistance < reached else {
                    break
                }
                let from = stroke.points[index - 1]
                var to = stroke.points[index]
                let endDistance = stroke.distances[index]
                if endDistance > reached, endDistance > startDistance {
                    let part = (reached - startDistance) / (endDistance - startDistance)
                    to = CGPoint(x: from.x + (to.x - from.x) * part, y: from.y + (to.y - from.y) * part)
                }
                let taper = WelcomeDoodleInk.taper(at: endDistance / max(stroke.length, 0.001), length: stroke.length)
                var segment = Path()
                segment.move(to: CGPoint(x: from.x * scale, y: from.y * scale))
                segment.addLine(to: CGPoint(x: to.x * scale, y: to.y * scale))
                context.stroke(
                    segment,
                    with: shading,
                    style: StrokeStyle(lineWidth: stroke.width * taper * scale, lineCap: .round)
                )
            }
        }
    }

    private func color(of ink: WelcomeDoodleInk.Ink) -> Color {
        switch ink {
        case .petal: .paeoniaAccentPrimary
        case .blush: .paeoniaWidgetDrawing
        }
    }

    /// Who wrote it and when, in the widget's own type: the partner's name, then the
    /// time it was saved, which is a moment ago.
    private var footer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(.welcomeDoodleAuthor)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)

            Text(Date.now.formatted(date: .omitted, time: .shortened))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    WelcomeWidgetDoodle()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaeoniaGlowBackground())
        .preferredColorScheme(.dark)
}
#endif
