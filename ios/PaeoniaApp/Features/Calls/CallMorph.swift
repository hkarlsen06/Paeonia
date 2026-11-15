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
    /// switches between the ring pill and the full call screen. Give `size` for a view with a fixed
    /// width and height, such as a photo or a round button. It then draws at that size and scales
    /// to the frame on the way, because a fixed frame ignores the size the morph offers and would
    /// only move.
    func callMorph(_ part: CallMorphPart?, size: CGFloat? = nil) -> some View {
        modifier(CallMorphModifier(part: part, size: size))
    }
}

private struct CallMorphModifier: ViewModifier {
    let part: CallMorphPart?
    let size: CGFloat?

    @Environment(\.callMorph) private var namespace

    func body(content: Content) -> some View {
        if let part, let namespace {
            if let size {
                GeometryReader { proxy in
                    content
                        .scaleEffect(x: proxy.size.width / size, y: proxy.size.height / size)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .matchedGeometryEffect(id: part, in: namespace)
                .frame(width: size, height: size)
            } else {
                // The name keeps its own size, because a title squeezed into the pill's narrow
                // frame would cut itself short on the way.
                content.matchedGeometryEffect(id: part, in: namespace, properties: part == .name ? .position : .frame)
            }
        } else {
            content
        }
    }
}
