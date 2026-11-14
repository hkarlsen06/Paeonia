import SwiftUI

/// A corner of the screen the bubble sits in.
nonisolated enum CallBubbleCorner: CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }
}

/// Places the bubble in its corner, clear of the navigation bar at the top and of the tab bar,
/// a screen's bottom controls and the game chat panel at the bottom. A drag moves it, and it
/// settles in the corner nearest to where it was thrown.
struct CallBubbleLayer: View {
    let model: CallOverlayModel
    let session: CallSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
    @State private var bubbleSize = CGSize.zero

    /// Room for a navigation bar under the status bar.
    private static let navigationBarClearance: CGFloat = 52
    /// Room for the floating tab bar above the bottom of the safe area.
    private static let tabBarClearance: CGFloat = 70
    private static let margin = PaeoniaSpacing.space12

    var body: some View {
        GeometryReader { proxy in
            let area = Self.area(in: proxy, controlsTop: model.controlsTop, panelTop: model.panelTop)
            CallBubble(center: model.center, session: session, participants: model.participants)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
                // The window passes every touch outside this frame to the app underneath.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.bubbleFrame = $0 }
                .gesture(drag(in: area))
                .position(center(of: model.corner, in: area))
                .offset(dragOffset)
        }
    }

    /// Where the bubble's center may go, in the layer's coordinates.
    private static func area(in proxy: GeometryProxy, controlsTop: CGFloat?, panelTop: CGFloat?) -> CGRect {
        let frame = proxy.frame(in: .global)
        let top = navigationBarClearance
        var bottom = proxy.size.height - tabBarClearance
        for edge in [controlsTop, panelTop].compactMap(\.self) {
            bottom = min(bottom, edge - frame.minY)
        }
        return CGRect(
            x: margin, y: top, width: max(0, proxy.size.width - 2 * margin), height: max(0, bottom - margin - top))
    }

    private func center(of corner: CallBubbleCorner, in area: CGRect) -> CGPoint {
        let halfWidth = bubbleSize.width / 2
        let halfHeight = bubbleSize.height / 2
        let x = corner.isLeading ? area.minX + halfWidth : area.maxX - halfWidth
        // A bottom corner with no room left, such as above an open chat panel, falls back to the top.
        let fitsBottom = area.height >= bubbleSize.height
        let y = corner.isTop || !fitsBottom ? area.minY + halfHeight : area.maxY - halfHeight
        return CGPoint(x: x, y: y)
    }

    private func drag(in area: CGRect) -> some Gesture {
        // In global space, because the bubble moves under the finger.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let start = center(of: model.corner, in: area)
                let thrownTo = CGPoint(
                    x: start.x + value.predictedEndTranslation.width,
                    y: start.y + value.predictedEndTranslation.height)
                let corner = CallBubbleCorner.allCases.min { lhs, rhs in
                    distance(center(of: lhs, in: area), thrownTo) < distance(center(of: rhs, in: area), thrownTo)
                } ?? model.corner
                withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2)) {
                    model.corner = corner
                    dragOffset = .zero
                }
            }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
