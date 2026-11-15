import SwiftUI

/// The parts of the ring pill that grow into the full call screen, and shrink back into the pill.
enum CallMorphPart: Hashable {
    case background
    case photo
    case name
    case decline
    case answer
}

extension EnvironmentValues {
    /// Pairs the ring pill's parts with the call screen's. The overlay sets it.
    @Entry var callMorph: Namespace.ID?
}

extension View {
    /// Moves and resizes this view to and from the same part on the other surface when the call
    /// switches between the ring pill and the full call screen.
    func callMorph(_ part: CallMorphPart?) -> some View {
        modifier(CallMorphModifier(part: part))
    }
}

private struct CallMorphModifier: ViewModifier {
    let part: CallMorphPart?

    @Environment(\.callMorph) private var namespace

    func body(content: Content) -> some View {
        if let part, let namespace {
            // The name keeps its own size, because a title squeezed into the pill's narrow
            // frame would cut itself short on the way.
            content.matchedGeometryEffect(id: part, in: namespace, properties: part == .name ? .position : .frame)
        } else {
            content
        }
    }
}
