import SwiftUI

/// Places the bubble at its spot (`CallBubblePlacement`). A drag moves it, and it settles against the
/// edge it was thrown toward, at the height it was dropped. A pinch makes the video bigger or smaller,
/// and it grows from the edge it sits against.
struct CallBubbleLayer: View {
    let model: CallOverlayModel
    let session: CallSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
    @State private var bubbleSize = CGSize.zero
    /// How much the pinch in progress grows the video, on top of `model.videoScale`.
    @State private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let placement = model.placement(in: proxy)
            let scales = videoScales(in: placement)
            CallBubble(
                center: model.center, session: session, participants: model.participants,
                videoScale: clamp(model.videoScale * pinch, to: scales),
                resizeVideo: { resize($0, within: scales) }
            )
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
            // The window passes every touch outside this frame to the app underneath.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.bubbleFrame = $0 }
            .gesture(drag(in: placement))
            .simultaneousGesture(
                resizing(within: scales), including: CallBubble.showsVideo(session) ? .all : .subviews)
            .position(placement.center(of: model.spot, bubble: bubbleSize))
            .offset(dragOffset)
        }
    }

    /// The video may grow until it fills most of the screen's width or all of the free area's height.
    private func videoScales(in placement: CallBubblePlacement) -> ClosedRange<CGFloat> {
        let range = CallBubble.videoScales
        let fits = min(
            placement.area.width * 0.8 / CallBubble.videoSize.width,
            placement.area.height / CallBubble.videoSize.height)
        return range.lowerBound...max(range.lowerBound, min(range.upperBound, fits))
    }

    private func resizing(within scales: ClosedRange<CGFloat>) -> some Gesture {
        MagnifyGesture()
            .onChanged { pinch = $0.magnification }
            .onEnded { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    model.videoScale = clamp(model.videoScale * value.magnification, to: scales)
                    pinch = 1
                }
            }
    }

    private func resize(_ direction: AccessibilityAdjustmentDirection, within scales: ClosedRange<CGFloat>) {
        let step: CGFloat = 0.25
        let scale = switch direction {
        case .increment: model.videoScale + step
        case .decrement: model.videoScale - step
        @unknown default: model.videoScale
        }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.callOverlay) {
            model.videoScale = clamp(scale, to: scales)
        }
    }

    private func clamp(_ scale: CGFloat, to scales: ClosedRange<CGFloat>) -> CGFloat {
        min(max(scale, scales.lowerBound), scales.upperBound)
    }

    private func drag(in placement: CallBubblePlacement) -> some Gesture {
        // In global space, because the bubble moves under the finger.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                // The bubble never tucks away. Thrown past an edge, it settles against it.
                let landing = placement.landing(
                    from: model.spot, translation: value.translation, velocity: value.velocity, bubble: bubbleSize)
                withAnimation(reduceMotion ? nil : PaeoniaMotion.callOverlay) {
                    model.spot = landing.spot
                    dragOffset = .zero
                }
            }
    }
}
