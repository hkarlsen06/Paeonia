import Foundation
import SwiftUI

/// The cold-launch intro. It continues the system launch screen (the petal mark
/// centered on the plum background) with no visible jump and holds it only until the
/// first app surface is ready. Then the two petal halves move apart while a circular
/// hole opens from the center. The hole cuts through the petals and the plum canvas
/// together, so the petals disappear as part of the screen opening up. The hole keeps
/// growing past the screen corners and unmasks the first app surface, already drawn
/// underneath.
struct LaunchExperienceView: View {
    /// True once the routed first surface behind the overlay is ready to be shown
    /// (auth/access has resolved). Starts the reveal.
    let contentReady: Bool
    /// Called as the reveal begins, cueing the surface underneath to bring its
    /// content in.
    let onRevealContent: () -> Void
    /// Called when the opening hole reaches the screen's left and right edges.
    let onSidesUncovered: () -> Void
    /// Called once the reveal has fully played out and the overlay can be removed.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealing = false
    /// Per-side horizontal travel of each petal half. `0` composes the full mark,
    /// exactly matching the system launch screen.
    @State private var petalSpread: CGFloat = 0
    /// `0` leaves the canvas whole, `1` has carried the circular hole past the
    /// screen's furthest corner.
    @State private var holeProgress: CGFloat = 0
    /// Reduce Motion exits by fading the whole overlay instead. `1` at rest.
    @State private var overlayOpacity: Double = 1

    // The composed mark matches the system launch screen's visible art exactly: the
    // `PaeoniaLaunchPetalMark` asset is a 150 pt square whose mark fills a centered
    // 124×62 region. The half assets share the full mark's viewBox, so overlaying
    // them at zero spread reproduces `PaeoniaMark` pixel for pixel.
    private let markWidth: CGFloat = 124
    private let markHeight: CGFloat = 62
    /// How far each half travels outward during the reveal.
    private let revealSpread: CGFloat = 100

    private static let revealDuration: TimeInterval = 0.35
    private static let reducedMotionExitDuration: TimeInterval = 0.22
    /// The petals start fast and settle, so they visibly part before the hole
    /// reaches them.
    private static let petalAnimation = Animation.timingCurve(0.3, 0.8, 0.3, 1, duration: revealDuration)
    /// The hole starts slowly and speeds up, catching the petals about 70 ms in and
    /// cutting them away over the next 45 ms. It clears the corners around 290 ms.
    private static let holeAnimation = Animation.timingCurve(0.4, 0, 0.3, 1, duration: revealDuration)
    /// When the hole's edge reaches the left and right screen edges on a phone
    /// (about 0.42 of `holeProgress`). On iPad it arrives about 30 ms later.
    private static let sidesUncoveredDelay: TimeInterval = 0.12

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.paeoniaBackgroundPrimary
                logo
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .mask { holeCutout(in: proxy.size) }
        }
        .opacity(overlayOpacity)
        .ignoresSafeArea()
        // The mask does not change hit testing, so without this the overlay would
        // swallow taps on the screen it is uncovering until it is removed.
        .allowsHitTesting(!isRevealing)
        .onChange(of: contentReady, initial: true) { _, isReady in
            if isReady {
                beginReveal()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.appStateLaunching))
    }

    /// A full canvas with a circular hole cut from its center. At `holeProgress` `1`
    /// the hole's edge has passed the furthest corner with a little slack, so no lit
    /// sliver survives to be cut off by the overlay's unmount.
    private func holeCutout(in size: CGSize) -> some View {
        let diameter = holeProgress * (hypot(size.width, size.height) + 2)
        return Rectangle()
            .fill(.black)
            .overlay {
                Circle()
                    .frame(width: diameter, height: diameter)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    private var logo: some View {
        ZStack {
            Image(.paeoniaMarkPetalLeft)
                .resizable()
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .offset(x: -petalSpread)

            Image(.paeoniaMarkPetalRight)
                .resizable()
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .offset(x: petalSpread)
        }
        .accessibilityHidden(true)
    }

    /// Runs once. Readiness can flip again while the reveal plays.
    private func beginReveal() {
        guard !isRevealing else {
            return
        }
        isRevealing = true
        onRevealContent()

        if reduceMotion {
            withAnimation(.easeOut(duration: Self.reducedMotionExitDuration)) {
                overlayOpacity = 0
            }
            onSidesUncovered()
            finish(after: Self.reducedMotionExitDuration)
            return
        }

        withAnimation(Self.petalAnimation) {
            petalSpread = revealSpread
        }
        withAnimation(Self.holeAnimation) {
            holeProgress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.sidesUncoveredDelay))
            onSidesUncovered()
        }
        finish(after: Self.revealDuration)
    }

    private func finish(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            onFinished()
        }
    }
}

#if DEBUG
#Preview {
    LaunchExperienceView(contentReady: true, onRevealContent: {}, onSidesUncovered: {}, onFinished: {})
        .preferredColorScheme(.dark)
}
#endif
