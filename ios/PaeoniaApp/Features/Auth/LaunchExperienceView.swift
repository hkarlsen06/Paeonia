import SwiftUI

/// The cold-launch overlay. It looks exactly like the system launch screen, so the
/// launch has no visible jump, and holds only until the first app surface is ready.
/// Then it fades out over that surface (`LaunchScreenCanvas`).
///
/// Nothing in it moves, so the fade can overlap the system's own launch screen fade
/// or the app lock's cover, which show the same mark, without showing two marks.
struct LaunchExperienceView: View {
    /// True once the routed first surface behind the overlay is ready to be shown
    /// (auth/access has resolved). Starts the fade.
    let contentReady: Bool
    /// Called as the fade begins, cueing the surface underneath to bring its content in.
    let onRevealContent: () -> Void
    /// Called once the fade has played out and the overlay can be removed.
    let onFinished: () -> Void

    @State private var isFading = false
    @State private var hasFinished = false

    var body: some View {
        LaunchScreenCanvas(isFading: isFading, onFaded: finish)
            .onChange(of: contentReady, initial: true) { _, isReady in
                // Runs once. Readiness can flip again while the overlay fades.
                if isReady, !isFading {
                    isFading = true
                    onRevealContent()
                }
            }
            .ignoresSafeArea()
            // The screen underneath takes taps as soon as it starts to show.
            .allowsHitTesting(!isFading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.appStateLaunching))
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished()
    }
}

#if DEBUG
#Preview {
    LaunchExperienceView(contentReady: true, onRevealContent: {}, onFinished: {})
        .preferredColorScheme(.dark)
}
#endif
