import SwiftUI

/// Where the call bubble and the partner's avatar sit: the partner's avatar against the left or the
/// right edge, and the call bubble where the person dropped it, at the height they dropped it. They
/// share one spot, so the bubble shows where the avatar was.
nonisolated struct CallBubbleSpot: Equatable, Sendable {
    enum Height: Equatable, Sendable {
        /// Just above the screen's bottom controls, such as the tab bar or a chat's composer. Where it
        /// starts, before the person moves it.
        case aboveControls
        /// Dropped as high or as low as it goes, it keeps to that end, so a keyboard or a panel that
        /// goes away later doesn't leave it in the middle of the screen.
        case top
        case bottom
        /// The center's height in the layer. The free area keeps it in.
        case center(CGFloat)
    }

    /// The side it is nearest, where the partner's avatar sits and where either tucks away.
    var edge: HorizontalEdge
    var height: Height
    /// Where the call bubble's center was dropped across the screen. Nil keeps it against `edge`.
    var x: CGFloat?

    /// Bottom right, above the tab bar.
    static let initial = CallBubbleSpot(edge: .trailing, height: .aboveControls)

    var isLeading: Bool { edge == .leading }
}

/// Where the call bubble and the partner's avatar may sit. The person may drop them anywhere from
/// under the navigation bar to the bottom of the screen, over the tab bar and a screen's bottom
/// controls too. The keyboard and the game chat panel push them up while they are open, and they
/// start above the bottom controls.
nonisolated struct CallBubblePlacement {
    /// Room for a navigation bar under the status bar.
    private static let navigationBarClearance: CGFloat = 52
    static let margin = PaeoniaSpacing.space12
    /// How far ahead a throw reaches, in seconds of its speed when the finger lets go, when it picks
    /// the side and whether a fling tucks the bubble. The bubble itself rests where it was let go.
    private static let throwCarry: CGFloat = 0.1

    /// The layer's size.
    let size: CGSize
    /// Where a bubble's frame may go, in the layer's coordinates.
    let area: CGRect
    /// The lowest a bubble's frame goes at `.aboveControls`.
    private let controlsMaxY: CGFloat

    /// `globalMinY` is the top of the layer in global coordinates, and `controlsTop` and `panelTop`
    /// are global too. The bottom controls keep the bubble above them only while the keyboard is up,
    /// because then they ride on it.
    init(size: CGSize, globalMinY: CGFloat, controlsTop: CGFloat?, panelTop: CGFloat?, keyboardIsUp: Bool) {
        self.size = size
        let margin = Self.margin
        let top = Self.navigationBarClearance
        let controlsBottom = controlsTop.map { min(size.height, $0 - globalMinY) } ?? size.height
        var bottom = keyboardIsUp ? controlsBottom : size.height
        if let panelTop { bottom = min(bottom, panelTop - globalMinY) }
        area = CGRect(
            x: margin, y: top, width: max(0, size.width - 2 * margin), height: max(0, bottom - margin - top))
        controlsMaxY = min(area.maxY, controlsBottom - margin)
    }

    /// The center of a bubble of `bubble` size at `spot`, kept inside the free area. With no room
    /// left, such as above an open chat panel, it goes to the top.
    func center(of spot: CallBubbleSpot, bubble: CGSize) -> CGPoint {
        let leftmost = area.minX + bubble.width / 2
        let rightmost = max(leftmost, area.maxX - bubble.width / 2)
        let x = spot.x.map { min(max($0, leftmost), rightmost) } ?? (spot.isLeading ? leftmost : rightmost)
        let highest = area.minY + bubble.height / 2
        let lowest = max(area.minY, area.maxY - bubble.height) + bubble.height / 2
        let y: CGFloat = switch spot.height {
        case .aboveControls: max(area.minY, controlsMaxY - bubble.height) + bubble.height / 2
        case .top: highest
        case .bottom: lowest
        case let .center(y): min(max(y, highest), lowest)
        }
        return CGPoint(x: x, y: y)
    }

    /// In the top half something taller than the spot's row grows down from it, and in the bottom
    /// half up from it. A row with no room below it, as above an open chat panel, is at the top.
    func growsDownward(fromY y: CGFloat, rowHeight: CGFloat) -> Bool {
        y < area.midY || area.height < rowHeight
    }

    /// Where a dragged bubble settles.
    enum Landing: Equatable {
        case spot(CallBubbleSpot)
        /// Pushed over the left or right edge, or flung hard at it, which tucks the bubble or the
        /// partner's avatar away there. It comes back at the spot.
        case tucked(CallBubbleSpot)

        var spot: CallBubbleSpot {
            switch self {
            case let .spot(spot), let .tucked(spot): spot
            }
        }
    }

    /// Where a bubble that started at `spot` settles once the finger lets go: at the height it was
    /// let go, and where it was let go across the screen when it `staysWhereDropped`, else against the
    /// edge it was thrown toward. The throw picks only that edge and whether a fling tucks it, so the
    /// bubble never slides on past the finger.
    func landing(
        from spot: CallBubbleSpot, translation: CGSize, velocity: CGSize, bubble: CGSize, staysWhereDropped: Bool
    ) -> Landing {
        let start = center(of: spot, bubble: bubble)
        let released = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let carried = CGPoint(
            x: released.x + velocity.width * Self.throwCarry, y: released.y + velocity.height * Self.throwCarry)
        let edge: HorizontalEdge = carried.x < size.width / 2 ? .leading : .trailing
        var landed = CallBubbleSpot(edge: edge, height: settledHeight(released.y, bubble: bubble))
        // How far the bubble's middle went past the edge. A finger can't leave the screen, and it may
        // hold the bubble anywhere, so a quarter of the bubble over the edge, and at most 24 pt of it,
        // is enough to tuck it.
        let pastEdge = edge == .leading ? -released.x : released.x - size.width
        let overEdge = pastEdge + bubble.width / 2
        // A fling tucks only when it starts near that edge, so a throw across the screen never does.
        let startsNearEdge = pastEdge > -bubble.width * 1.5
        let flungPastEdge = edge == .leading ? -carried.x : carried.x - size.width
        let tucks = overEdge > min(bubble.width / 4, 24) || (startsNearEdge && flungPastEdge > bubble.width)
        // A tucked bubble comes back against the edge.
        if tucks { return .tucked(landed) }
        if staysWhereDropped { landed.x = released.x }
        return .spot(landed)
    }

    /// The height a bubble dropped with its center at `y` keeps.
    func settledHeight(_ y: CGFloat, bubble: CGSize) -> CallBubbleSpot.Height {
        let settled = center(of: CallBubbleSpot(edge: .trailing, height: .center(y)), bubble: bubble).y
        if settled >= center(of: CallBubbleSpot(edge: .trailing, height: .bottom), bubble: bubble).y { return .bottom }
        if settled <= area.minY + bubble.height / 2 { return .top }
        return .center(settled)
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
