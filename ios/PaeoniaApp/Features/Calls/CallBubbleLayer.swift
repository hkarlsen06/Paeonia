import SwiftUI

/// Places the bubble in its corner (`CallBubblePlacement`). A drag moves it, and it settles in the
/// corner nearest to where it was thrown.
struct CallBubbleLayer: View {
    let model: CallOverlayModel
    let session: CallSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
    @State private var bubbleSize = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let placement = model.placement(in: proxy)
            CallBubble(center: model.center, session: session, participants: model.participants)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
                // The window passes every touch outside this frame to the app underneath.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.bubbleFrame = $0 }
                .gesture(drag(in: placement))
                .position(placement.center(of: model.corner, bubble: bubbleSize))
                .offset(dragOffset)
        }
    }

    private func drag(in placement: CallBubblePlacement) -> some Gesture {
        // In global space, because the bubble moves under the finger.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                // The bubble never tucks away. Thrown past an edge, it settles in the corner there.
                let landing = placement.landing(
                    thrownFrom: model.corner, by: value.predictedEndTranslation, bubble: bubbleSize)
                withAnimation(reduceMotion ? nil : PaeoniaMotion.callOverlay) {
                    model.corner = landing.corner
                    dragOffset = .zero
                }
            }
    }
}
