import SwiftUI

/// Fires the full-screen petal shower and its haptic. Read it with `@Environment(\.petalShower)`.
/// It does nothing outside `PaeoniaPetalShowerHost`.
struct PetalShowerAction {
    fileprivate var fire: (_ seed: String, _ hearts: Bool, _ delay: TimeInterval) -> Void = { _, _, _ in }

    /// The same seed gives the same shower. `delay` lets a screen finish appearing first.
    func callAsFunction(seed: String, hearts: Bool = false, after delay: TimeInterval = 0) {
        fire(seed, hearts, delay)
    }
}

extension EnvironmentValues {
    @Entry var petalShower = PetalShowerAction()
}

/// Draws the petal shower over the whole window, so a card inside a scroll view can fire one too.
/// Sits once at the app's root. Under Reduce Motion the petals don't draw and only the haptic
/// plays.
struct PaeoniaPetalShowerHost: ViewModifier {
    private struct Run {
        let start: Date
        let seed: String
        let hearts: Bool
    }

    @State private var run: Run?
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .environment(\.petalShower, PetalShowerAction(fire: fire))
            .overlay {
                if let run {
                    PaeoniaPetalShower(start: run.start, seed: run.seed, hearts: run.hearts)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private func fire(seed: String, hearts: Bool, delay: TimeInterval) {
        task?.cancel()
        run = Run(start: .now.addingTimeInterval(delay), seed: seed, hearts: hearts)
        task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            PaeoniaHaptics.petalShowerFired()
            try? await Task.sleep(for: .seconds(PaeoniaPetalShower.duration))
            guard !Task.isCancelled else { return }
            run = nil
        }
    }
}
