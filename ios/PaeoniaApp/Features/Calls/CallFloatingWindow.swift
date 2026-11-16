import SwiftUI

/// Where a floating window of the small call sits, how much it was pinched, and whether it waits
/// tucked away as a tab at the edge.
nonisolated struct CallFloat: Equatable {
    var spot: CallBubbleSpot
    var scale: CGFloat = 1
    var isTucked = false
}

/// One window of the small call, at its spot (`CallBubblePlacement`): the bubble, or the partner's
/// shared screen. A drag moves it, and it stays where it is dropped. Pushed into the side of the
/// screen, it tucks away as a tab there (`PresenceTab`), which brings it back out. A pinch on a
/// window that `zooms` makes it bigger or smaller and moves it with the fingers at the same time
/// (`CallBubbleGesture`). `notices` hang off its top or bottom edge, toward the middle of the screen.
struct CallFloatingWindow<Content: View, Notices: View>: View {
    let placement: CallBubblePlacement
    @Binding var float: CallFloat
    /// The window's size before a pinch, or nil for one that does not zoom, such as the voice bubble.
    let zoomBase: CGSize?
    let tabLabel: Text
    let tabIdentifier: String
    var hasWaitingNotice = false
    /// A symbol the tab shows while the window is tucked away (`PresenceTab.mark`).
    var tabMark: String?
    let frameChanged: (CGRect) -> Void
    let tabFrameChanged: (CGRect) -> Void
    /// The window at a scale, with VoiceOver's resize and the tuck it offers.
    @ViewBuilder let content: (
        _ scale: CGFloat, _ resize: @escaping (AccessibilityAdjustmentDirection) -> Void, _ tuck: @escaping () -> Void
    ) -> Content
    /// What hangs off the window, given whether it hangs below it.
    @ViewBuilder var notices: (_ below: Bool) -> Notices

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
    @State private var size = CGSize.zero
    /// How much the pinch in progress grows the window, on top of `float.scale`.
    @State private var pinch: CGFloat = 1
    /// How far the tab has been dragged up or down along its edge.
    @State private var tabDragHeight: CGFloat = 0

    private var motion: Animation? {
        reduceMotion ? nil : PaeoniaMotion.callOverlay
    }

    var body: some View {
        ZStack {
            if float.isTucked {
                tab
            } else {
                window
            }
        }
    }

    private var window: some View {
        let scales = Self.scales(for: zoomBase, in: placement)
        let center = placement.center(of: float.spot, bubble: size)
        let below = placement.growsDownward(fromY: center.y, rowHeight: size.height)
        return content(
            clamp(float.scale * pinch, to: scales),
            { resize($0, within: scales) },
            { withAnimation(motion) { float.isTucked = true } }
        )
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // The window passes every touch outside this frame to the app underneath.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frameChanged($0) }
        .overlay(alignment: Alignment(
            horizontal: float.spot.isLeading ? .leading : .trailing, vertical: below ? .bottom : .top
        )) {
            notices(below)
                // No height of its own, so it hangs off the window's bottom or top edge.
                .frame(height: 0, alignment: below ? .top : .bottom)
                .offset(y: below ? PaeoniaSpacing.space8 : -PaeoniaSpacing.space8)
        }
        .gesture(CallBubbleGesture(zooms: zoomBase != nil) { translation, scale in
            dragOffset = translation
            pinch = scale
        } ended: { translation, scale, velocity in
            drop(translation: translation, scale: scale, velocity: velocity, within: scales)
        } cancelled: {
            withAnimation(motion) {
                dragOffset = .zero
                pinch = 1
            }
        })
        .position(center)
        .offset(dragOffset)
        .transition(.move(edge: float.spot.isLeading ? .leading : .trailing).combined(with: .opacity))
    }

    /// The tab sits at the window's height on the side it was pushed into.
    private var tab: some View {
        let edge = float.spot.edge
        let width = PresenceTab.size.width
        let y = placement.center(of: float.spot, bubble: size).y
        let shownY = placement.center(
            of: CallBubbleSpot(edge: edge, height: .center(y + tabDragHeight)), bubble: size).y
        return PresenceTab(
            edge: edge, label: tabLabel, identifier: tabIdentifier, hasWaitingNotice: hasWaitingNotice, mark: tabMark)
            .onTapGesture { untuck() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { untuck() }
            .gesture(tabDrag(edge: edge, fromY: y))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tabFrameChanged($0) }
            .position(x: edge == .leading ? width / 2 : placement.size.width - width / 2, y: shownY)
            .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
    }

    private func untuck() {
        withAnimation(motion) { float.isTucked = false }
    }

    /// A window may grow until it fills most of the screen's width or all of the free area's height.
    static func scales(for base: CGSize?, in placement: CallBubblePlacement) -> ClosedRange<CGFloat> {
        let range = CallBubble.videoScales
        guard let base, base.width > 0, base.height > 0 else { return 1...1 }
        let fits = min(placement.area.width * 0.8 / base.width, placement.area.height / base.height)
        return range.lowerBound...max(range.lowerBound, min(range.upperBound, fits))
    }

    private func resize(_ direction: AccessibilityAdjustmentDirection, within scales: ClosedRange<CGFloat>) {
        let step: CGFloat = 0.25
        let scale = switch direction {
        case .increment: float.scale + step
        case .decrement: float.scale - step
        @unknown default: float.scale
        }
        withAnimation(motion) {
            float.scale = clamp(scale, to: scales)
        }
    }

    private func clamp(_ scale: CGFloat, to scales: ClosedRange<CGFloat>) -> CGFloat {
        min(max(scale, scales.lowerBound), scales.upperBound)
    }

    /// The window stays where the fingers let it go, at the size they left it. A push over the left
    /// or right edge, or a hard fling at it, tucks it away.
    private func drop(translation: CGSize, scale: CGFloat, velocity: CGSize, within scales: ClosedRange<CGFloat>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            float.scale = clamp(float.scale * scale, to: scales)
            pinch = 1
        }
        let landing = placement.landing(
            from: float.spot, translation: translation, velocity: velocity, bubble: size, staysWhereDropped: true)
        withAnimation(motion) {
            float.spot = landing.spot
            if case .tucked = landing { float.isTucked = true }
            dragOffset = .zero
        }
    }

    /// The tab slides up and down its edge with the finger and stays where it is dropped. A pull in
    /// from the edge brings the window out there.
    private func tabDrag(edge: HorizontalEdge, fromY y: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { tabDragHeight = $0.translation.height }
            .onEnded { value in
                let inward = edge == .leading ? value.translation.width : -value.translation.width
                let dropped = placement.settledHeight(y + value.translation.height, bubble: size)
                withAnimation(motion) {
                    float.spot = CallBubbleSpot(edge: edge, height: dropped)
                    if inward > PresenceTab.size.width * 1.5 { float.isTucked = false }
                    tabDragHeight = 0
                }
            }
    }
}
