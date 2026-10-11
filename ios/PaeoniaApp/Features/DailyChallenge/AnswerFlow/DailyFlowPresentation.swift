import SwiftUI

/// Stable source ids for the Daily Challenge zoom transition. The Home prompt card and
/// the Questions-tab hero card each tag themselves with one of these via
/// `.matchedTransitionSource`, and `MainTabView` zooms the answer flow's full-screen
/// cover out of whichever card opened it. (Partner-answer cards use their question id.)
enum DailyFlowZoom {
    static let home = "dailyFlow.home"
    static let questions = "dailyFlow.questions"
}

extension View {
    /// Marks this view as the source the answer flow zooms out of, but only when a
    /// namespace is provided. A nil namespace passes through untouched, as used by
    /// previews (which present no flow) and to skip the source under Reduce Motion.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Zooms a presentation out of its matching `zoomSource(_:in:)`, so the source card
    /// appears to grow into the full-screen cover. When `enabled` is false (Reduce
    /// Motion) or no namespace is provided, the cover keeps its default transition.
    @ViewBuilder
    func zoomTransition(_ id: some Hashable, in namespace: Namespace.ID?, enabled: Bool) -> some View {
        if enabled, let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// Dismisses the keyboard when the user taps anywhere on the view that isn't an
    /// interactive control. This is a convenience for sighted users, not an
    /// accessibility control, so it intentionally does not advertise a button trait
    /// (VoiceOver dismisses the keyboard through its own affordances). Shared by the
    /// daily challenge flow and the Questions-tab partner-answer flow.
    func dismissesKeyboardOnTap(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle()).onTapGesture(perform: action)
    }
}
