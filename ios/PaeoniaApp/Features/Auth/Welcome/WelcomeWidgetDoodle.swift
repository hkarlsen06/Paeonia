import SwiftUI

/// The picture on the welcome screen: the small Home Screen drawing widget with a
/// doodle from a partner on it, laid out like `PaeoniaWidgetEntryView` (the drawing on
/// top, who drew it and when underneath). On launch the doodle draws itself in once,
/// a stroke at a time, then holds still. Under Reduce Motion it shows finished.
///
/// The tile is about the size of a small widget and shrinks on short screens. The
/// whole tile is one image to VoiceOver.
struct WelcomeWidgetDoodle: View {
    /// The tile's side when the screen has room for it.
    private static let maxSide: CGFloat = 220
    /// The smallest it gets before the welcome screen scrolls instead.
    private static let minSide: CGFloat = 150
    /// How long after the screen is revealed the first stroke starts, so the tile
    /// has dropped into place first.
    private static let drawingDelay: TimeInterval = 0.45

    @Environment(\.launchContentRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)

                doodle(side: side)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            footer
        }
        // The system's content margin on a small widget.
        .padding(PaeoniaSpacing.space16)
        .aspectRatio(1, contentMode: .fit)
        .homeWidgetCardSurface()
        .frame(minHeight: Self.minSide, idealHeight: Self.minSide, maxHeight: Self.maxSide)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.welcomeDoodleAccessibility))
        .accessibilityAddTraits(.isImage)
        .task(id: revealed) {
            if revealed {
                isDrawn = true
            }
        }
    }

    private func doodle(side: CGFloat) -> some View {
        ZStack {
            ForEach(WelcomeDoodleStroke.all.indices, id: \.self) { index in
                let stroke = WelcomeDoodleStroke.all[index]

                WelcomeDoodlePath(path: stroke.path)
                    .trim(from: 0, to: isDrawn || reduceMotion ? 1 : 0)
                    .stroke(
                        stroke.color,
                        style: StrokeStyle(
                            lineWidth: stroke.width * side / WelcomeDoodleStroke.canvasSide,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .animation(
                        reduceMotion
                            ? nil
                            : .timingCurve(0.45, 0, 0.35, 1, duration: stroke.duration)
                            .delay(Self.drawingDelay + stroke.start),
                        value: isDrawn
                    )
            }
        }
        .clipShape(DrawingCanvasShape())
        .accessibilityHidden(true)
    }

    /// Who drew it and when, in the widget's own type: the partner's name, then the
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

/// A path drawn on a square canvas `WelcomeDoodleStroke.canvasSide` points wide,
/// scaled to whatever square it is shown in.
private nonisolated struct WelcomeDoodlePath: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(
            x: rect.width / WelcomeDoodleStroke.canvasSide,
            y: rect.height / WelcomeDoodleStroke.canvasSide
        )
        return path.applying(transform)
    }
}

/// One pen stroke of the doodle, in the order it is drawn. The points wobble a little
/// on purpose, so the doodle looks drawn by hand rather than set as an icon.
private nonisolated struct WelcomeDoodleStroke {
    static let canvasSide: CGFloat = 100

    let path: Path
    let color: Color
    /// Line width on the 100-point canvas.
    let width: CGFloat
    /// Seconds after the first stroke starts.
    let start: TimeInterval
    let duration: TimeInterval

    static let all: [WelcomeDoodleStroke] = [
        heart,
        sparkle(x: 12, y: 18, size: 7, tilt: -2, start: 1.0),
        sparkle(x: 88, y: 13, size: 6, tilt: 3, start: 1.25),
        sparkle(x: 90, y: 54, size: 5, tilt: -1, start: 1.5),
        underline,
    ].flatMap { $0 }

    /// One loop from the bottom tip, up and over the left lobe, the dip and the right
    /// lobe, and back down a little past where it began.
    private static let heart = [
        WelcomeDoodleStroke(
            path: Path { path in
                path.move(to: CGPoint(x: 50.5, y: 74))
                path.addCurve(
                    to: CGPoint(x: 23, y: 39),
                    control1: CGPoint(x: 38, y: 64),
                    control2: CGPoint(x: 21.5, y: 51)
                )
                path.addCurve(
                    to: CGPoint(x: 49.5, y: 31.5),
                    control1: CGPoint(x: 24.5, y: 20),
                    control2: CGPoint(x: 45.5, y: 18.5)
                )
                path.addCurve(
                    to: CGPoint(x: 77.5, y: 37),
                    control1: CGPoint(x: 54.5, y: 17),
                    control2: CGPoint(x: 78.5, y: 19.5)
                )
                path.addCurve(
                    to: CGPoint(x: 47.5, y: 76),
                    control1: CGPoint(x: 77, y: 52.5),
                    control2: CGPoint(x: 60, y: 63)
                )
            },
            color: .paeoniaAccentPrimary,
            width: 4.4,
            start: 0,
            duration: 0.9
        ),
    ]

    /// A wavy line under the heart, drawn left to right.
    private static let underline = [
        WelcomeDoodleStroke(
            path: Path { path in
                path.move(to: CGPoint(x: 24, y: 88))
                path.addQuadCurve(to: CGPoint(x: 37, y: 87), control: CGPoint(x: 30.5, y: 83))
                path.addQuadCurve(to: CGPoint(x: 50, y: 87.5), control: CGPoint(x: 43.5, y: 92))
                path.addQuadCurve(to: CGPoint(x: 63, y: 87), control: CGPoint(x: 56.5, y: 82.5))
                path.addQuadCurve(to: CGPoint(x: 76, y: 87.5), control: CGPoint(x: 70, y: 91.5))
            },
            color: .paeoniaWidgetDrawing,
            width: 3.2,
            start: 1.75,
            duration: 0.45
        ),
    ]

    /// A small plus, the down stroke and then the across stroke, each a little off
    /// straight.
    private static func sparkle(
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        tilt: CGFloat,
        start: TimeInterval
    ) -> [WelcomeDoodleStroke] {
        let down = Path { path in
            path.move(to: CGPoint(x: x + tilt * 0.3, y: y - size))
            path.addLine(to: CGPoint(x: x - tilt * 0.3, y: y + size))
        }
        let across = Path { path in
            path.move(to: CGPoint(x: x - size, y: y + tilt * 0.25))
            path.addLine(to: CGPoint(x: x + size, y: y - tilt * 0.25))
        }

        return [
            WelcomeDoodleStroke(
                path: down, color: .paeoniaWidgetDrawing, width: 3.2, start: start, duration: 0.12
            ),
            WelcomeDoodleStroke(
                path: across, color: .paeoniaWidgetDrawing, width: 3.2, start: start + 0.14, duration: 0.12
            ),
        ]
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
