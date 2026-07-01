import Foundation
import SwiftUI

/// The cold-launch intro. It continues the system launch screen (the petal mark
/// centered on the plum background) with no visible jump, then plays a short,
/// deliberate sequence: the petal lifts to reveal the `Paeonia` wordmark, the pair
/// holds for a beat, and finally the intro exits — the plum backdrop drops away (it
/// is the same plum as the app, so the swap is seamless) and the logo fades out fast,
/// uncovering the first app surface, which cascades its own content in (see
/// `View.launchEntrance(order:)`).
///
/// The sequencing/gating lives in `LaunchExperienceSequence`; this view owns only the
/// timing and the SwiftUI presentation. The reveal waits for `contentReady`, so a slow
/// auth/access resolve simply holds on the branded wordmark instead of flashing a
/// half-loaded surface.
struct LaunchExperienceView: View {
    /// True once the routed first surface behind the overlay is ready to be shown
    /// (auth/access has resolved). Drives the gate on the reveal.
    let contentReady: Bool
    /// Called as the intro begins its exit, cueing the app surface to cascade its
    /// content in while the logo fades out.
    let onRevealContent: () -> Void
    /// Called once the reveal has fully played out and the overlay can be removed.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sequence = LaunchExperienceSequence()
    @State private var wordmarkHeight: CGFloat = 0
    /// The logo's exit: a fast fade out. `1` at rest.
    @State private var logoOpacity: Double = 1
    /// The plum backdrop that covers the app during the intro. Fades away (seamlessly —
    /// same plum as the app) as the exit begins.
    @State private var backdropOpacity: Double = 1

    // Layout — the mark matches the system launch screen's visible art exactly: the
    // `PaeoniaLaunchPetalMark` asset is a 150 pt square whose mark fills a centered
    // 124×62 region, so framing the slim mark at that size keeps the hand-off from
    // the system splash seamless while sitting the wordmark tight beneath it.
    private let markWidth: CGFloat = 124
    private let markHeight: CGFloat = 62
    /// How far the lockup lifts so mark + wordmark read as centered on reveal.
    private let markRise: CGFloat = 30
    private let wordmarkGap: CGFloat = 10
    private let wordmarkSize: CGFloat = 40

    // Timing.
    private static let markHold: TimeInterval = 0.25
    private static let revealDuration: TimeInterval = 0.7
    private static let wordmarkHold: TimeInterval = 0.4
    /// A fast fade out: the logo and backdrop dim away quickly while the content cascade
    /// carries the motion.
    private static let exitDuration: TimeInterval = 0.22

    /// A gentle, graceful reveal of the wordmark — slower than the app's default so
    /// the lockup settles in rather than snapping.
    private static let revealAnimation = PaeoniaMotion.standardCurve(duration: revealDuration)

    var body: some View {
        overlay
            .animation(sequenceAnimation, value: sequence.phase)
            .task { await runScript() }
            .onChange(of: contentReady, initial: true) { _, ready in
                if ready {
                    sequence.markContentReady()
                }
            }
            .onChange(of: sequence.phase) { _, phase in
                handlePhaseChange(phase)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.appStateLaunching))
    }

    private var overlay: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary
                .opacity(backdropOpacity)

            logo
                .opacity(logoOpacity)
                .offset(y: markOffsetY)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var logo: some View {
        ZStack {
            markArt

            wordmarkLabel
                .opacity(wordmarkOpacity)
                .offset(y: wordmarkCenterOffset)
        }
    }

    private var markArt: some View {
        Image(.paeoniaMark)
            .resizable()
            .scaledToFit()
            .frame(width: markWidth, height: markHeight)
            .accessibilityHidden(true)
    }

    private var wordmarkLabel: some View {
        Text(.appTitle)
            .font(PaeoniaTypography.wordmark(size: wordmarkSize))
            .foregroundStyle(.paeoniaTextPrimary)
            .lineLimit(1)
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WordmarkHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .onPreferenceChange(WordmarkHeightPreferenceKey.self) { height in
                wordmarkHeight = height
            }
    }

    // MARK: - Derived presentation

    private var wordmarkCenterOffset: CGFloat {
        markHeight / 2 + wordmarkGap + wordmarkHeight / 2
    }

    /// The mark sits dead-center (matching the system splash) until it lifts to make
    /// room for the wordmark. Reduce Motion keeps it centered.
    private var markOffsetY: CGFloat {
        guard !reduceMotion, sequence.phase != .mark else {
            return 0
        }

        return -markRise
    }

    /// The wordmark fades in once on reveal and then stays put until the whole logo
    /// fades out on exit.
    private var wordmarkOpacity: Double {
        sequence.phase == .mark ? 0 : 1
    }

    private var sequenceAnimation: Animation? {
        if reduceMotion {
            return PaeoniaMotion.stateChange
        }

        switch sequence.phase {
        case .mark:
            return nil
        case .wordmark:
            return Self.revealAnimation
        case .revealing, .finished:
            return nil
        }
    }

    // MARK: - Timing

    private func runScript() async {
        try? await Task.sleep(for: .seconds(Self.markHold))
        sequence.revealWordmark()

        try? await Task.sleep(for: .seconds(Self.revealDuration + Self.wordmarkHold))
        sequence.markWordmarkHoldElapsed()
    }

    private func handlePhaseChange(_ phase: LaunchExperienceSequence.Phase) {
        switch phase {
        case .revealing:
            beginExit()
        case .finished:
            onFinished()
        case .mark, .wordmark:
            break
        }
    }

    /// Cues the content to cascade in and fades the logo and backdrop out fast. One
    /// coordinated exit, then the overlay releases.
    private func beginExit() {
        onRevealContent()

        withAnimation(.easeOut(duration: Self.exitDuration)) {
            backdropOpacity = 0
            logoOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.exitDuration))
            sequence.finishReveal()
        }
    }
}

private struct WordmarkHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
#Preview {
    LaunchExperienceView(contentReady: true, onRevealContent: {}, onFinished: {})
        .preferredColorScheme(.dark)
}
#endif
