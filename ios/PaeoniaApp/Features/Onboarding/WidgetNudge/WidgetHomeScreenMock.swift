import SwiftUI
import UIKit

/// A small picture of an iPhone Home Screen with the large Paeonia widget showing the
/// person's own drawing. The widget copies `PaeoniaWidgetEntryView`: the plum
/// background, the square drawing with the canvas corners, and the name, time and
/// refresh button under it.
///
/// Everything is sized from the picture's width, not from Dynamic Type, because it is
/// a picture. VoiceOver reads it as one image.
///
/// `activeStep` follows the how-to list: the press ring shows on step 0, the icons
/// jiggle like edit mode on steps 1 to 3, and the widget pops on step 4. Nil keeps it
/// still, for Reduce Motion. `isAdded` stops the motion, pops the widget and puts a
/// check on it.
struct WidgetHomeScreenMock: View {
    let drawing: UIImage
    var authorName: String?
    var activeStep: Int?
    var isAdded = false

    /// Width over height, close to a phone screen.
    private static let aspectRatio: CGFloat = 0.56

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popCount = 0

    private var showsPress: Bool { !isAdded && activeStep == 0 }
    private var jiggles: Bool { !isAdded && (1...3).contains(activeStep ?? -1) }

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(width: proxy.size.width)

            TimelineView(.animation(paused: !(showsPress || jiggles))) { context in
                screen(metrics: metrics, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .onChange(of: activeStep) { _, step in
            if step == WidgetNudgeHowTo.stepCount - 1 {
                popCount += 1
            }
        }
        .onChange(of: isAdded) { _, added in
            if added {
                popCount += 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.onboardingWidgetNudgeMockAccessibility))
        .accessibilityAddTraits(.isImage)
    }

    private func screen(metrics: Metrics, time: TimeInterval) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.width * 0.13, style: .continuous)

        return VStack(spacing: 0) {
            widget(metrics: metrics, time: time)
                .padding(.top, metrics.width * 0.13)

            Text(.appTitle)
                .font(.system(size: metrics.width * 0.04, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, metrics.width * 0.02)

            iconRow(metrics: metrics, time: time)
                .padding(.top, metrics.width * 0.05)

            Spacer(minLength: 0)

            dock(metrics: metrics, time: time)
                .padding(.bottom, metrics.width * 0.04)
        }
        .padding(.horizontal, metrics.margin)
        .frame(width: metrics.width, height: metrics.width / Self.aspectRatio)
        .background(wallpaper)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.paeoniaTextPrimary.opacity(0.22), lineWidth: max(2, metrics.width * 0.014))
        }
        .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
    }

    private var wallpaper: some View {
        LinearGradient(
            colors: [
                .paeoniaAccentSecondary.opacity(0.9),
                Color.paeoniaInkLavender.opacity(0.75),
                .paeoniaBackgroundElevated
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Widget

    private func widget(metrics: Metrics, time: TimeInterval) -> some View {
        let side = metrics.widgetSide
        // Read here, since the keyframe closure can't read view state.
        let pops = !reduceMotion

        return VStack(alignment: .leading, spacing: side * 0.03) {
            GeometryReader { proxy in
                let drawingSide = min(proxy.size.width, proxy.size.height)

                Image(uiImage: drawing)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(DrawingCanvasShape())
                    .accessibilityHidden(true)
                    .frame(width: drawingSide, height: drawingSide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            widgetFooter(side: side)
        }
        .padding(side * 0.05)
        .frame(width: side, height: side * 1.05)
        .background(.paeoniaBackgroundPrimary, in: RoundedRectangle(cornerRadius: side * 0.065, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isAdded {
                addedBadge(side: side)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .rotationEffect(jiggleAngle(index: 0, time: time))
        .keyframeAnimator(initialValue: CGFloat(1), trigger: popCount) { content, scale in
            content.scaleEffect(pops ? scale : 1)
        } keyframes: { _ in
            SpringKeyframe(1.05, duration: 0.18, spring: .snappy)
            SpringKeyframe(1, duration: 0.5, spring: .bouncy)
        }
    }

    private func widgetFooter(side: CGFloat) -> some View {
        HStack(spacing: side * 0.03) {
            VStack(alignment: .leading, spacing: 1) {
                if let authorName = authorName?.trimmedNonEmpty {
                    Text(verbatim: authorName)
                        .font(.system(size: side * 0.05, weight: .semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                }

                Text(Date().formatted(date: .omitted, time: .shortened))
                    .font(.system(size: side * 0.038, weight: .medium))
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: side * 0.036, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: side * 0.088, height: side * 0.088)
                .background(Color.paeoniaAccentPrimary.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
        }
    }

    private func addedBadge(side: CGFloat) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: side * 0.06, weight: .bold))
            .foregroundStyle(.paeoniaTextInverse)
            .frame(width: side * 0.14, height: side * 0.14)
            .background(.paeoniaAccentPrimary, in: Circle())
            .accessibilityHidden(true)
            .offset(x: side * 0.04, y: -side * 0.04)
    }

    // MARK: Icons

    /// Three apps and one empty spot, where the press ring shows.
    private func iconRow(metrics: Metrics, time: TimeInterval) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                VStack(spacing: metrics.width * 0.02) {
                    appIcon(metrics: metrics, opacity: 0.22 + Double(index) * 0.05)
                    Capsule()
                        .fill(.white.opacity(0.5))
                        .frame(width: metrics.icon * 0.7, height: metrics.width * 0.012)
                }
                .rotationEffect(jiggleAngle(index: index + 1, time: time))
                .frame(width: metrics.cell)
            }

            pressRing(metrics: metrics, time: time)
                .frame(width: metrics.cell)
        }
    }

    private func dock(metrics: Metrics, time: TimeInterval) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                Group {
                    if index == 3 {
                        paeoniaIcon(metrics: metrics)
                    } else {
                        appIcon(metrics: metrics, opacity: 0.2 + Double(index) * 0.04)
                    }
                }
                .rotationEffect(jiggleAngle(index: index + 4, time: time))
                .frame(width: metrics.cell)
            }
        }
        .padding(.vertical, metrics.width * 0.035)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: metrics.width * 0.08, style: .continuous))
    }

    private func appIcon(metrics: Metrics, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: metrics.icon * 0.225, style: .continuous)
            .fill(.white.opacity(opacity))
            .frame(width: metrics.icon, height: metrics.icon)
    }

    /// The asset is the whole app icon, rounded corners included.
    private func paeoniaIcon(metrics: Metrics) -> some View {
        Image(.paeoniaAppIconMark)
            .resizable()
            .scaledToFit()
            .frame(width: metrics.icon, height: metrics.icon)
            .accessibilityHidden(true)
    }

    /// A fingertip held on the empty spot, with a ring growing out of it.
    @ViewBuilder
    private func pressRing(metrics: Metrics, time: TimeInterval) -> some View {
        let progress = time.truncatingRemainder(dividingBy: 1.4) / 1.4

        ZStack {
            Circle()
                .stroke(.white.opacity(0.7 * (1 - progress)), lineWidth: max(1.5, metrics.width * 0.01))
                .frame(width: metrics.icon * 0.95, height: metrics.icon * 0.95)
                .scaleEffect(0.5 + 0.5 * progress)

            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: metrics.icon * 0.42, height: metrics.icon * 0.42)
        }
        .frame(width: metrics.icon, height: metrics.icon)
        .opacity(showsPress ? 1 : 0)
        .animation(PaeoniaMotion.stateChange, value: showsPress)
    }

    /// The small back and forth of edit mode. Each icon starts at a different point,
    /// so they don't swing together.
    private func jiggleAngle(index: Int, time: TimeInterval) -> Angle {
        guard jiggles else {
            return .zero
        }
        return .degrees(sin(time * 2 * .pi * 6 + Double(index) * 1.7) * 1.8)
    }
}

private struct Metrics {
    let width: CGFloat

    var margin: CGFloat { width * 0.07 }
    /// One of the four columns.
    var cell: CGFloat { (width - 2 * margin) / 4 }
    var icon: CGFloat { cell * 0.74 }
    /// The large widget spans all four columns, edge to edge with the icons.
    var widgetSide: CGFloat { width - 2 * margin - (cell - icon) }
}

#if DEBUG
#Preview("Still") {
    WidgetHomeScreenMock(drawing: UIImage(resource: .placeholderSketch), authorName: "Hjalmar")
        .frame(width: 230)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaeoniaGlowBackground())
        .preferredColorScheme(.dark)
}

#Preview("Jiggling") {
    WidgetHomeScreenMock(drawing: UIImage(resource: .placeholderSketch), authorName: "Hjalmar", activeStep: 2)
        .frame(width: 230)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaeoniaGlowBackground())
        .preferredColorScheme(.dark)
}
#endif
