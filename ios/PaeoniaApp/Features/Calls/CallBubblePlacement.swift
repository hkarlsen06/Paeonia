import SwiftUI

/// A corner of the screen the bubble sits in.
nonisolated enum CallBubbleCorner: CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }

    init(isTop: Bool, isLeading: Bool) {
        self = switch (isTop, isLeading) {
        case (true, true): .topLeading
        case (true, false): .topTrailing
        case (false, true): .bottomLeading
        case (false, false): .bottomTrailing
        }
    }
}

/// Where the call bubble and the partner's avatar may sit. They share one corner, so the
/// bubble shows where the avatar was. Their center stays clear of the navigation bar at the top, and
/// of the tab bar, a screen's bottom controls and the game chat panel at the bottom. While a chat is
/// on screen the bottom corners move to the top, because the chat's composer is there.
nonisolated struct CallBubblePlacement {
    /// Room for a navigation bar under the status bar.
    private static let navigationBarClearance: CGFloat = 52
    /// Room for the floating tab bar above the bottom of the safe area.
    private static let tabBarClearance: CGFloat = 70
    static let margin = PaeoniaSpacing.space12

    /// The layer's size.
    let size: CGSize
    /// Where a bubble's frame may go, in the layer's coordinates.
    let area: CGRect
    private let bottomIsTaken: Bool

    /// `globalMinY` is the top of the layer in global coordinates, and `controlsTop` and `panelTop`
    /// are global too.
    init(size: CGSize, globalMinY: CGFloat, controlsTop: CGFloat?, panelTop: CGFloat?, chatIsOnScreen: Bool) {
        self.size = size
        bottomIsTaken = chatIsOnScreen
        let top = Self.navigationBarClearance
        var bottom = size.height - Self.tabBarClearance
        for edge in [controlsTop, panelTop].compactMap(\.self) {
            bottom = min(bottom, edge - globalMinY)
        }
        let margin = Self.margin
        area = CGRect(
            x: margin, y: top, width: max(0, size.width - 2 * margin), height: max(0, bottom - margin - top))
    }

    /// The center of a bubble of `bubble` size in `corner`.
    func center(of corner: CallBubbleCorner, bubble: CGSize) -> CGPoint {
        let x = corner.isLeading ? area.minX + bubble.width / 2 : area.maxX - bubble.width / 2
        let y = showsAtTop(corner, height: bubble.height)
            ? area.minY + bubble.height / 2 : area.maxY - bubble.height / 2
        return CGPoint(x: x, y: y)
    }

    /// A bottom corner with no room left, such as above an open chat panel, falls back to the top.
    func showsAtTop(_ corner: CallBubbleCorner, height: CGFloat) -> Bool {
        corner.isTop || bottomIsTaken || area.height < height
    }

    /// Where a thrown bubble or avatar settles.
    enum Landing: Equatable {
        case corner(CallBubbleCorner)
        /// Thrown past the left or right edge, which tucks the partner's avatar away there. It comes
        /// back in the corner.
        case tucked(HorizontalEdge, CallBubbleCorner)

        var corner: CallBubbleCorner {
            switch self {
            case let .corner(corner), let .tucked(_, corner): corner
            }
        }
    }

    /// The corner nearest to where a bubble that starts in `corner` was thrown, or a tuck at the edge
    /// it was thrown past.
    func landing(thrownFrom corner: CallBubbleCorner, by translation: CGSize, bubble: CGSize) -> Landing {
        let start = center(of: corner, bubble: bubble)
        let thrownTo = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let nearest = CallBubbleCorner.allCases.min { lhs, rhs in
            distance(center(of: lhs, bubble: bubble), thrownTo) < distance(center(of: rhs, bubble: bubble), thrownTo)
        } ?? corner
        if thrownTo.x < 0 {
            return .tucked(.leading, CallBubbleCorner(isTop: nearest.isTop, isLeading: true))
        }
        if thrownTo.x > size.width {
            return .tucked(.trailing, CallBubbleCorner(isTop: nearest.isTop, isLeading: false))
        }
        return .corner(nearest)
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
