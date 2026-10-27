import SwiftUI

extension View {
    /// While `isLoading`, the view keeps its space and draws nothing. When it loads, it comes
    /// into focus from a soft blur. `delay` staggers neighbours, so a title, its line and a
    /// button arrive one after another. With Reduce Motion it only fades in.
    func paeoniaLoadingReveal(_ isLoading: Bool, delay: TimeInterval = 0) -> some View {
        modifier(PaeoniaLoadingReveal(isLoading: isLoading, delay: delay))
    }
}

private struct PaeoniaLoadingReveal: ViewModifier {
    let isLoading: Bool
    let delay: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            if isLoading {
                content.hidden()
            } else {
                content.transition(.asymmetric(insertion: insertion, removal: .identity))
            }
        }
        .animation(PaeoniaMotion.loadingReveal.delay(delay), value: isLoading)
    }

    private var insertion: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(BlurReplaceTransition(configuration: .upUp))
    }
}
