import SwiftUI

/// What the board shows while its scene loads: the dark of the room with a small candle
/// flame, as the table is set. The scene fades in over the same color, so the flame seems
/// to be lit before the room appears. With Reduce Motion the flame holds still.
struct LudoLoadingView: View {
    /// The shortest time the loading view shows, and how long it takes to fade away.
    static let minimumShowTime: TimeInterval = 1.2
    static let fadeDuration: TimeInterval = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The flame and the words come in softly when the view first shows.
    @State private var isLit = false

    var body: some View {
        ZStack {
            Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.roomHex))
            VStack(spacing: PaeoniaSpacing.space16) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    flame(flicker: Self.flicker(time))
                }
                .frame(width: 80, height: 96)
                .accessibilityHidden(true)
                Text(.ludoLoading)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .opacity(isLit ? 1 : 0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? nil : PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                isLit = true
            }
        }
    }

    /// The flame and its glow. `flicker` runs from -1 to 1.
    private func flame(flicker: Double) -> some View {
        let core = Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.flameCoreHex))
        let warm = Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.flameHex))
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [warm.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 40)
                )
                .scaleEffect(1 + flicker * 0.06)
            LudoFlameShape()
                .fill(LinearGradient(colors: [core, warm], startPoint: .bottom, endPoint: .top))
                .frame(width: 18, height: 34)
                .scaleEffect(x: 1 - flicker * 0.04, y: 1 + flicker * 0.1, anchor: .bottom)
                .offset(y: 4)
        }
    }

    /// The same soft wander as the candle on the table.
    private static func flicker(_ time: Double) -> Double {
        sin(time * 7.3) * 0.5 + sin(time * 13.1 + 1.7) * 0.3 + sin(time * 23.9 + 0.4) * 0.2
    }
}

/// A candle flame standing on its rounded base, with its tip at the top.
nonisolated private struct LudoFlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        path.move(to: tip)
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.maxX * 1.05, y: rect.minY + rect.height * 0.55),
            control2: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.minX, y: rect.maxY),
            control2: CGPoint(x: rect.minX - rect.width * 0.05, y: rect.minY + rect.height * 0.55)
        )
        path.closeSubpath()
        return path
    }
}
