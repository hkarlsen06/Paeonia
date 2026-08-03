import Foundation
import SwiftUI

/// The cold-launch intro. It continues the system launch screen (the petal mark
/// centered on the plum background) with no visible jump, then plays a short,
/// deliberate sequence: the two petal halves pull apart like a spring under tension,
/// release, and collapse back at full speed. They are never seen stopping — the fade
/// is what the collision looks like: a fast flick timed to the tail of the release,
/// reaching zero on the landing instant itself, so the petals are gone exactly as
/// they would have met. The shockwave fires at the same moment the fade begins — the
/// instant they start to collide is the instant they start to go. The circular
/// shockwave opens the plum canvas from the collision point and expands past the
/// screen corners, unmasking the first app surface (already drawn underneath), which
/// cascades its own content in (see `View.launchEntrance(order:)`).
///
/// The sequencing/gating lives in `LaunchExperienceSequence`; this view owns only the
/// timing and the SwiftUI presentation. The animated portion waits for `contentReady`,
/// so a slow auth/access resolve holds the static petal instead of competing with
/// startup work or flashing a half-loaded surface.
struct LaunchExperienceView: View {
    /// True once the routed first surface behind the overlay is ready to be shown
    /// (auth/access has resolved). Drives the gate on the reveal.
    let contentReady: Bool
    /// Called on the impact, as the shockwave begins to unmask the app surface,
    /// cueing that surface to cascade its content in.
    let onRevealContent: () -> Void
    /// Called once the reveal has fully played out and the overlay can be removed.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sequence = LaunchExperienceSequence()
    /// Per-side horizontal travel of each petal half. `0` composes the full mark,
    /// exactly matching the system launch screen.
    @State private var petalSpread: CGFloat = 0
    /// The petals' exit: the fast flick at the tail of the release (or the plain
    /// Reduce Motion fade). `1` at rest.
    @State private var logoOpacity: Double = 1
    /// Reduce Motion exits by fading the plum backdrop (seamless — same plum as the
    /// app) instead of blasting it open. `1` at rest and untouched otherwise.
    @State private var backdropOpacity: Double = 1
    /// The shockwave: `0` leaves the canvas whole, `1` has carried the circular hole
    /// past the screen's furthest corner.
    @State private var shockProgress: CGFloat = 0

    // Layout — the composed mark matches the system launch screen's visible art
    // exactly: the `PaeoniaLaunchPetalMark` asset is a 150 pt square whose mark fills
    // a centered 124×62 region, so framing the halves at that size keeps the hand-off
    // from the system splash seamless. The half assets share the full mark's viewBox,
    // so overlaying them at zero spread reproduces `PaeoniaMark` pixel for pixel.
    private let markWidth: CGFloat = 124
    private let markHeight: CGFloat = 62
    /// How far past rest each half is pulled while the spring loads.
    private let pullSpread: CGFloat = 22
    /// The collision point the collapse falls toward: just short of composed, so the
    /// halves never merge back into the mark. The exit flick reaches zero opacity on
    /// the same instant the fall arrives here, so the stop itself is never seen.
    private let landingSpread: CGFloat = 4
    // Timing.
    private static let markHold: TimeInterval = 0.25
    private static let pullDuration: TimeInterval = 0.38
    private static let releaseDuration: TimeInterval = 0.42
    private static let shockDuration: TimeInterval = 0.42
    /// When the shockwave fires and the petals' fade begins, as a fraction of the
    /// release: the instant they begin to collide is the instant they start to go.
    /// Chosen so the fade below runs through the fall's last stretch and lands its
    /// zero exactly on the release's end.
    private static let collisionFraction: Double = 0.88
    /// The petals' fade: a fast flick filling the gap between the collision instant
    /// and the release's end (0.12 × 420ms), so opacity reaches zero on the landing
    /// itself and the petals are never seen stopped. Keep these two in step: this
    /// duration should equal `(1 - collisionFraction) × releaseDuration`.
    private static let petalFadeDuration: TimeInterval = 0.05
    /// Reduce Motion: the composed mark holds for a beat in place of the spring, and
    /// the exit is a plain fade.
    private static let reducedMotionHold: TimeInterval = 0.4
    private static let reducedMotionExitDuration: TimeInterval = 0.22

    /// The pull decelerates into full tension, so the stretch reads as held rather
    /// than as a bounce on its way somewhere.
    private static let pullAnimation = Animation.timingCurve(0.25, 1, 0.5, 1, duration: pullDuration)
    /// The release accelerates the whole way and arrives at full speed with nowhere
    /// to go — the stop *is* the impact. No overshoot, no recoil: a mark that gives
    /// and resettles reads as light, and the landing must read as heavy.
    private static let releaseAnimation = Animation.timingCurve(0.5, 0, 0.85, 0.25, duration: releaseDuration)
    /// The shockwave loses speed as it travels — that is what makes it read as
    /// something thrown outwards rather than a wipe — but clears the corners well
    /// before its end, so no sliver of canvas creeps into them after the reveal has
    /// already read as done.
    private static let shockAnimation = Animation.timingCurve(0.2, 0.7, 0.4, 1, duration: shockDuration)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backdrop(in: proxy.size)

                logo
                    .compositingGroup()
                    .opacity(logoOpacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        // Keep the petal perfectly still while auth, SwiftData, and the routed
        // first surface are being prepared. Starting the animated portion only
        // after readiness prevents launch work from stealing frames mid-motion.
        .task(id: contentReady) {
            guard contentReady else { return }
            await runScript()
        }
        .onChange(of: sequence.phase) { _, phase in
            handlePhaseChange(phase)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.appStateLaunching))
    }

    /// The plum canvas, masked so the shockwave can punch a growing hole through it
    /// while the petals drawn on top stay whole. The mask is unconditional and a
    /// no-op at rest (a zero-diameter hole), so nothing changes structure mid-flight.
    private func backdrop(in size: CGSize) -> some View {
        Color.paeoniaBackgroundPrimary
            .opacity(backdropOpacity)
            .mask { shockCutout(in: size) }
    }

    /// A full canvas with a circular hole cut from its center. At `shockProgress`
    /// `1` the hole's edge has passed the furthest corner with a little slack, so
    /// no lit sliver survives to be cut off by the overlay's unmount.
    private func shockCutout(in size: CGSize) -> some View {
        let diameter = shockProgress * (hypot(size.width, size.height) + 2)
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

    // MARK: - Timing

    private func runScript() async {
        sequence.markContentReady()

        do {
            try await Task.sleep(for: .seconds(Self.markHold))
        } catch {
            return
        }
        sequence.beginSpring()

        if reduceMotion {
            // The whole point of the spring is motion, so there is no shortened
            // version of it to offer: hold the composed mark for a beat instead.
            do {
                try await Task.sleep(for: .seconds(Self.reducedMotionHold))
            } catch {
                return
            }
            sequence.markSpringLanded()
            return
        }

        withAnimation(Self.pullAnimation) {
            petalSpread = pullSpread
        }
        do {
            try await Task.sleep(for: .seconds(Self.pullDuration))
        } catch {
            return
        }

        withAnimation(Self.releaseAnimation) {
            petalSpread = landingSpread
        }
        // The collision, not the animation's end: the petals finish their fall (and
        // their exit flick) on their own underneath the shockwave, so they are never
        // seen stopping.
        do {
            try await Task.sleep(for: .seconds(Self.releaseDuration * Self.collisionFraction))
        } catch {
            return
        }
        sequence.markSpringLanded()
    }

    private func handlePhaseChange(_ phase: LaunchExperienceSequence.Phase) {
        switch phase {
        case .revealing:
            beginExit()
        case .finished:
            onFinished()
        case .mark, .spring:
            break
        }
    }

    /// The collision's consequences, all on one instant: the content is cued, the
    /// shockwave starts opening the canvas from the point the petals are vanishing
    /// into, and the petals flick out — reaching zero exactly as their fall lands.
    private func beginExit() {
        onRevealContent()

        if reduceMotion {
            withAnimation(.easeOut(duration: Self.reducedMotionExitDuration)) {
                backdropOpacity = 0
                logoOpacity = 0
            }
            finishReveal(after: Self.reducedMotionExitDuration)
            return
        }

        withAnimation(Self.shockAnimation) {
            shockProgress = 1
        }
        withAnimation(.linear(duration: Self.petalFadeDuration)) {
            logoOpacity = 0
        }
        finishReveal(after: Self.shockDuration)
    }

    private func finishReveal(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            sequence.finishReveal()
        }
    }
}

#if DEBUG
#Preview {
    LaunchExperienceView(contentReady: true, onRevealContent: {}, onFinished: {})
        .preferredColorScheme(.dark)
}
#endif
