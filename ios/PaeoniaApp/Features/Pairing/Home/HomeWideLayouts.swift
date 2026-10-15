import SwiftUI

/// Where a card goes in `HomeWideLayout`. The phone stack ignores it.
nonisolated enum HomeWideRole: LayoutValueKey {
    /// One of the main cards, in the two columns under the map.
    case card
    /// The map, across the top of the main cards.
    case map
    /// The milestone and drawing tiles, in their own column on the right.
    case tiles

    static let defaultValue = HomeWideRole.card
}

/// The Home tab on a wide iPad. The main cards take the left two thirds and the tile
/// column the right third, so the 2:1 map and the square drawing tile beside it are
/// the same height. The map spans the main cards' width at the top. The other cards go
/// in two columns below it in order, each card in the column that ends higher, so the
/// cards stay about phone width and today's questions sit beside the game card instead
/// of below it.
struct HomeWideLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let tileWidth = (width - spacing) / 3
        let mainWidth = width - spacing - tileWidth
        let columnWidth = (mainWidth - spacing) / 2
        let mapBottom = subviews.first { $0[HomeWideRole.self] == .map }
            .map { $0.sizeThatFits(ProposedViewSize(width: mainWidth, height: nil)).height + spacing } ?? 0
        var columnTops = [mapBottom, mapBottom]
        return subviews.map { subview in
            switch subview[HomeWideRole.self] {
            case .map:
                return CGRect(x: 0, y: 0, width: mainWidth, height: mapBottom - spacing)
            case .tiles:
                let height = subview.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height
                return CGRect(x: mainWidth + spacing, y: 0, width: tileWidth, height: height)
            case .card:
                let column = columnTops[1] < columnTops[0] ? 1 : 0
                let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
                defer { columnTops[column] += height + spacing }
                return CGRect(
                    x: CGFloat(column) * (columnWidth + spacing),
                    y: columnTops[column],
                    width: columnWidth,
                    height: height
                )
            }
        }
    }
}

/// The tile column in the wide Home layout. It stacks the tiles in reverse, so the
/// drawing, written last for the phone's row, sits on top beside the map.
struct HomeWideTileColumnLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: heights.reduce(gaps, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews.reversed() {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }
}
