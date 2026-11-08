import SwiftUI

/// The cold-launch intro. It continues the system launch screen (the petal mark
/// centered on the plum background) with no visible jump and holds it only until the
/// first app surface is ready. Then the two petal halves move apart while a circular
/// hole opens from the center. The hole cuts through the petals and the plum canvas
/// together, so the petals disappear as part of the screen opening up. The hole keeps
/// growing past the screen corners and unmasks the first app surface, already drawn
/// underneath.
///
/// The reveal runs as Core Animation on `LaunchRevealCanvas`, so the render server
/// plays it. The first surface builds in the same update that starts it, and on an
/// iPhone that update took 80 to 100 ms. A SwiftUI animation lost its first 6 to 8
/// frames to it. This one starts when that update is drawn and keeps its frame rate
/// while the main thread stays busy after it. The sides and finish callbacks come
/// from the animation itself, so they stay in step with what is on screen.
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
    @State private var reveal: LaunchRevealCanvas.Reveal?
    @State private var hasFinished = false

    var body: some View {
        LaunchRevealCanvas(reveal: reveal, onSidesUncovered: onSidesUncovered, onFinished: finishReveal)
        .onChange(of: contentReady, initial: true) { _, isReady in
            if isReady {
                beginReveal()
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced, reveal == .opening {
                reveal = .fading
                onSidesUncovered()
                finishReveal()
            }
        }
        .ignoresSafeArea()
        // The mask does not change hit testing, so without this the overlay would
        // swallow taps on the screen it is uncovering until it is removed.
        .allowsHitTesting(reveal == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.appStateLaunching))
    }

    /// Runs once. Readiness can flip again while the reveal plays.
    private func beginReveal() {
        guard reveal == nil else {
            return
        }
        onRevealContent()
        if reduceMotion {
            onSidesUncovered()
            reveal = .fading
        } else {
            reveal = .opening
        }
    }

    private func finishReveal() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished()
    }
}

#if DEBUG
#Preview {
    LaunchExperienceView(contentReady: true, onRevealContent: {}, onSidesUncovered: {}, onFinished: {})
        .preferredColorScheme(.dark)
}
#endif
