import Foundation
import SwiftUI

/// The cold-launch intro. It continues the system launch screen (the petal mark
/// centered on the plum background) with no visible jump, then plays a short,
/// deliberate sequence: the petal lifts to reveal the `Paeonia` wordmark, the pair
/// holds for a beat, and finally the launch screen is unmasked — the right petal of
/// the mark turns transparent and explodes open onto the app.
///
/// The whole launch surface (plum + mark + wordmark) is one composite drawn from the
/// vector mark (`paeoniaMark`). On unmask the right petal is punched out of it as a
/// growing transparent window, and at the same time the colored surface fades away,
/// so the reveal is a soft cross-fade led by the exploding petal rather than a hard
/// cut — and no colored seam is left behind. The sequencing/gating lives in
/// `LaunchExperienceSequence`; this view owns only the timing and the SwiftUI
/// presentation. The unmask waits for `contentReady`, so a slow auth/access resolve
/// simply holds on the branded wordmark instead of flashing a half-loaded surface.
struct LaunchExperienceView: View {
    /// True once the routed first surface behind the overlay is ready to be shown
    /// (auth/access has resolved). Drives the gate on the final unmask.
    let contentReady: Bool
    /// Called once the reveal has fully played out and the overlay can be removed.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sequence = LaunchExperienceSequence()
    @State private var wordmarkHeight: CGFloat = 0
    /// The right-petal window: `holeScale` grows it, `eraserStrength` fades it in so
    /// the petal turns from colored to transparent softly rather than snapping open.
    @State private var holeScale: CGFloat = 1
    @State private var eraserStrength: Double = 0
    /// The whole colored surface's opacity. Fades to 0 alongside the exploding petal
    /// so the reveal is a soft cross-fade and no colored remnant (seam, left petal)
    /// lingers.
    @State private var coverOpacity: Double = 1

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
    /// The right wing's solid centroid within the full mark frame; the petal window
    /// explodes from here so the app opens out of the right petal in place.
    private let rightWingAnchor = UnitPoint(x: 0.74, y: 0.51)
    /// How large the right petal swells. The simultaneous cover fade finishes the
    /// reveal, so this only has to sell the burst, not cover the whole screen alone.
    private static let petalExplosionScale: CGFloat = 18

    // Timing.
    private static let markHold: TimeInterval = 0.25
    private static let revealDuration: TimeInterval = 0.7
    private static let wordmarkHold: TimeInterval = 0.4
    private static let unmaskDuration: TimeInterval = 0.45

    /// A gentle, graceful reveal of the wordmark — slower than the app's default so
    /// the lockup settles in rather than snapping.
    private static let revealAnimation = PaeoniaMotion.standardCurve(duration: revealDuration)
    /// A fast, front-loaded burst so the petal explodes open rather than drifting.
    private static let unmaskAnimation = Animation.timingCurve(0.16, 1, 0.3, 1, duration: unmaskDuration)

    var body: some View {
        cover
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

    /// The launch surface — plum, mark, and wordmark composited as one "image" — with
    /// the right petal punched out of it as a transparent window that grows to uncover
    /// the app behind, while the whole surface fades away at the same time.
    private var cover: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary

            markArt
                .offset(y: markOffsetY)

            wordmarkLabel
                .opacity(wordmarkOpacity)
                .offset(y: markOffsetY + wordmarkCenterOffset)
        }
        .compositingGroup()
        .opacity(coverOpacity)
        .mask { petalRevealMask }
        .ignoresSafeArea()
    }

    /// An inverse mask: the surface shows everywhere except where the right petal is
    /// punched out (`destinationOut`) as a transparent window, which fades in
    /// (`eraserStrength`) and grows (`holeScale`) to open onto the app.
    private var petalRevealMask: some View {
        Rectangle()
            .overlay {
                rightPetalWindow
                    .opacity(eraserStrength)
                    .scaleEffect(holeScale, anchor: rightWingAnchor)
                    .offset(y: markOffsetY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    private var markArt: some View {
        Image(.paeoniaMark)
            .resizable()
            .scaledToFit()
            .frame(width: markWidth, height: markHeight)
            .accessibilityHidden(true)
    }

    /// The solid right wing of the mark, isolated by keeping only the right half of
    /// the (symmetric, seam-down-the-middle) art. It overlays the cover's own right
    /// petal exactly at `holeScale == 1`, so opening it turns *that* petal transparent
    /// in place — a single wing has no central seam, so the hole is clean.
    private var rightPetalWindow: some View {
        Image(.paeoniaMark)
            .resizable()
            .scaledToFit()
            .frame(width: markWidth, height: markHeight)
            .mask(alignment: .trailing) {
                Rectangle().frame(width: markWidth * 0.5)
            }
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
    /// room for the wordmark, then holds that raised position through the burst so the
    /// reveal radiates from the logo. Reduce Motion keeps it centered.
    private var markOffsetY: CGFloat {
        guard !reduceMotion, sequence.phase != .mark else {
            return 0
        }

        return -markRise
    }

    /// The wordmark fades in once on reveal and then stays put — it is part of the
    /// launch composite and dissolves with it, never fading out on its own.
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
        case .unmasking, .finished:
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
        case .unmasking:
            openPetalWindow()
        case .finished:
            onFinished()
        case .mark, .wordmark:
            break
        }
    }

    /// Explodes the right petal open while the colored surface fades away — one
    /// simultaneous motion, so the petal turns transparent as it expands and no hard
    /// cut or colored seam is left. Reduce Motion keeps just the cross-fade.
    private func openPetalWindow() {
        withAnimation(Self.unmaskAnimation) {
            coverOpacity = 0
            if !reduceMotion {
                holeScale = Self.petalExplosionScale
                eraserStrength = 1
            }
        }

        // Release the overlay once the burst has played out; the app is fully
        // uncovered by then, so its removal is invisible.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.unmaskDuration))
            sequence.finishUnmask()
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
    LaunchExperienceView(contentReady: true, onFinished: {})
        .preferredColorScheme(.dark)
}
#endif
