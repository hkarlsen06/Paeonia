import SwiftUI

/// Places the bubble at its spot (`CallBubblePlacement`). A drag moves it, and it stays where it is
/// dropped. Pushed into the side of the screen, it tucks away as a tab there (`PresenceTab`), which
/// brings it back out. A pinch makes the video bigger or smaller.
struct CallBubbleLayer: View {
    let model: CallOverlayModel
    let session: CallSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
    @State private var bubbleSize = CGSize.zero
    /// How much the pinch in progress grows the video, on top of `model.videoScale`.
    @State private var pinch: CGFloat = 1
    /// How far the tab has been dragged up or down along its edge.
    @State private var tabDragHeight: CGFloat = 0

    private var motion: Animation? {
        reduceMotion ? nil : PaeoniaMotion.callOverlay
    }

    var body: some View {
        GeometryReader { proxy in
            let placement = model.placement(in: proxy)
            ZStack {
                if model.bubbleIsTucked {
                    tab(in: placement)
                } else {
                    bubble(in: placement)
                }
            }
        }
    }

    private func bubble(in placement: CallBubblePlacement) -> some View {
        let scales = videoScales(in: placement)
        return CallBubble(
            center: model.center, session: session, participants: model.participants,
            videoScale: clamp(model.videoScale * pinch, to: scales),
            resizeVideo: { resize($0, within: scales) },
            tuck: { withAnimation(motion) { model.bubbleIsTucked = true } }
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
        .transition(.move(edge: model.spot.isLeading ? .leading : .trailing).combined(with: .opacity))
    }

    /// The tab sits at the bubble's height on the side it was pushed into.
    private func tab(in placement: CallBubblePlacement) -> some View {
        let edge = model.spot.edge
        let width = PresenceTab.size.width
        let y = placement.center(of: model.spot, bubble: bubbleSize).y
        let shownY = placement.center(
            of: CallBubbleSpot(edge: edge, height: .center(y + tabDragHeight)), bubble: bubbleSize).y
        return PresenceTab(edge: edge, partnerName: model.participants.partnerName, hasWaitingNotice: false)
            .onTapGesture { untuck() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { untuck() }
            .gesture(tabDrag(edge: edge, fromY: y, in: placement))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.tabFrame = $0 }
            .position(x: edge == .leading ? width / 2 : placement.size.width - width / 2, y: shownY)
            .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
    }

    private func untuck() {
        withAnimation(motion) { model.bubbleIsTucked = false }
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
        withAnimation(motion) {
            model.videoScale = clamp(scale, to: scales)
        }
    }

    private func clamp(_ scale: CGFloat, to scales: ClosedRange<CGFloat>) -> CGFloat {
        min(max(scale, scales.lowerBound), scales.upperBound)
    }

    /// The bubble follows the finger and stays where it is dropped. A push over the left or right
    /// edge, or a hard fling at it, tucks it away.
    private func drag(in placement: CallBubblePlacement) -> some Gesture {
        // In global space, because the bubble moves under the finger.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let landing = placement.landing(
                    from: model.spot, translation: value.translation, velocity: value.velocity, bubble: bubbleSize,
                    staysWhereDropped: true)
                withAnimation(motion) {
                    model.spot = landing.spot
                    if case .tucked = landing { model.bubbleIsTucked = true }
                    dragOffset = .zero
                }
            }
    }

    /// The tab slides up and down its edge with the finger and stays where it is dropped. A pull in
    /// from the edge brings the bubble out there.
    private func tabDrag(edge: HorizontalEdge, fromY y: CGFloat, in placement: CallBubblePlacement) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { tabDragHeight = $0.translation.height }
            .onEnded { value in
                let inward = edge == .leading ? value.translation.width : -value.translation.width
                let dropped = placement.settledHeight(y + value.translation.height, bubble: bubbleSize)
                withAnimation(motion) {
                    model.spot = CallBubbleSpot(edge: edge, height: dropped)
                    if inward > PresenceTab.size.width * 1.5 { model.bubbleIsTucked = false }
                    tabDragHeight = 0
                }
            }
    }
}
