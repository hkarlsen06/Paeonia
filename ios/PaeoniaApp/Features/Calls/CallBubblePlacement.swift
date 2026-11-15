import SwiftUI

/// Where the call bubble and the partner's avatar sit: against the left or the right edge, at the
/// height the person dropped it. They share one spot, so the bubble shows where the avatar was.
nonisolated struct CallBubbleSpot: Equatable, Sendable {
    var edge: HorizontalEdge
    /// The center's height in the layer. The free area keeps it in, so `.infinity` is as low as it goes.
    var y: CGFloat

    /// Bottom right, above the tab bar.
    static let initial = CallBubbleSpot(edge: .trailing, y: .infinity)

    var isLeading: Bool { edge == .leading }
}

/// Where the call bubble and the partner's avatar may sit. They stay clear of the navigation bar at
/// the top, and of the tab bar, a screen's bottom controls, a chat's composer and the game chat panel
/// at the bottom.
nonisolated struct CallBubblePlacement {
    /// Room for a navigation bar under the status bar.
    private static let navigationBarClearance: CGFloat = 52
    /// Room for the floating tab bar above the bottom of the safe area.
    private static let tabBarClearance: CGFloat = 70
    static let margin = PaeoniaSpacing.space12
    /// How far ahead a throw carries, in seconds of its speed when the finger lets go.
    private static let throwCarry: CGFloat = 0.1

    /// The layer's size.
    let size: CGSize
    /// Where a bubble's frame may go, in the layer's coordinates.
    let area: CGRect

    /// `globalMinY` is the top of the layer in global coordinates, and `controlsTop` and `panelTop`
    /// are global too.
    init(size: CGSize, globalMinY: CGFloat, controlsTop: CGFloat?, panelTop: CGFloat?) {
        self.size = size
        let top = Self.navigationBarClearance
        var bottom = size.height - Self.tabBarClearance
        for edge in [controlsTop, panelTop].compactMap(\.self) {
            bottom = min(bottom, edge - globalMinY)
        }
        let margin = Self.margin
        area = CGRect(
            x: margin, y: top, width: max(0, size.width - 2 * margin), height: max(0, bottom - margin - top))
    }

    /// The center of a bubble of `bubble` size at `spot`, kept inside the free area. With no room
    /// left, such as above an open chat panel, it goes to the top.
    func center(of spot: CallBubbleSpot, bubble: CGSize) -> CGPoint {
        let x = spot.isLeading ? area.minX + bubble.width / 2 : area.maxX - bubble.width / 2
        let lowest = max(area.minY, area.maxY - bubble.height) + bubble.height / 2
        return CGPoint(x: x, y: min(max(spot.y, area.minY + bubble.height / 2), lowest))
    }

    /// In the top half something taller than the spot's row grows down from it, and in the bottom
    /// half up from it. A row with no room below it, as above an open chat panel, is at the top.
    func growsDownward(fromY y: CGFloat, rowHeight: CGFloat) -> Bool {
        y < area.midY || area.height < rowHeight
    }

    /// Where a dragged bubble settles.
    enum Landing: Equatable {
        case spot(CallBubbleSpot)
        /// Pushed a third past the left or right edge, or flung hard at it, which tucks the partner's
        /// avatar away there. It comes back at the spot.
        case tucked(CallBubbleSpot)

        var spot: CallBubbleSpot {
            switch self {
            case let .spot(spot), let .tucked(spot): spot
            }
        }
    }

    /// Where a bubble that started at `spot` settles once the finger lets go: against the edge it was
    /// thrown toward, at the height it was dropped, carried a little by the throw.
    func landing(
        from spot: CallBubbleSpot, translation: CGSize, velocity: CGSize, bubble: CGSize
    ) -> Landing {
        let start = center(of: spot, bubble: bubble)
        let released = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let carried = CGPoint(
            x: released.x + velocity.width * Self.throwCarry, y: released.y + velocity.height * Self.throwCarry)
        let edge: HorizontalEdge = carried.x < size.width / 2 ? .leading : .trailing
        let landed = CallBubbleSpot(edge: edge, y: settledY(carried.y, bubble: bubble))
        // How far the bubble's middle went past the edge. A finger can't leave the screen, so a third
        // of the bubble over the edge is as far as a drag by its middle can surely push it.
        let pastEdge = edge == .leading ? -released.x : released.x - size.width
        // A fling tucks only when it starts near that edge, so a throw across the screen never does.
        let startsNearEdge = pastEdge > -bubble.width * 1.5
        let flungPastEdge = edge == .leading ? -carried.x : carried.x - size.width
        let tucks = pastEdge > -bubble.width / 6 || (startsNearEdge && flungPastEdge > bubble.width)
        return tucks ? .tucked(landed) : .spot(landed)
    }

    /// Dropped as low or as high as it goes, the bubble keeps to that end, so a keyboard or a panel that
    /// goes away later doesn't leave it in the middle of the screen.
    func settledY(_ y: CGFloat, bubble: CGSize) -> CGFloat {
        let settled = center(of: CallBubbleSpot(edge: .trailing, y: y), bubble: bubble).y
        if settled >= center(of: CallBubbleSpot(edge: .trailing, y: .infinity), bubble: bubble).y { return .infinity }
        if settled <= area.minY + bubble.height / 2 { return -.infinity }
        return settled
    }
}

extension View {
    /// Puts this view against `edge`, with its row of `rowHeight` centered at `rowY`. A view taller than
    /// its row grows away from that row toward the middle of the screen, and sideways toward the
    /// middle too, so the row's end at the edge stays put.
    func placed(
        on edge: HorizontalEdge, rowY: CGFloat, rowHeight: CGFloat, in placement: CallBubblePlacement
    ) -> some View {
        let downward = placement.growsDownward(fromY: rowY, rowHeight: rowHeight)
        let height = placement.size.height
        let rowEnd = downward ? rowY - rowHeight / 2 : rowY + rowHeight / 2
        return frame(
            width: placement.area.width, height: height,
            alignment: Alignment(
                horizontal: edge == .leading ? .leading : .trailing, vertical: downward ? .top : .bottom)
        )
        .position(x: placement.area.midX, y: downward ? rowEnd + height / 2 : rowEnd - height / 2)
    }
}
