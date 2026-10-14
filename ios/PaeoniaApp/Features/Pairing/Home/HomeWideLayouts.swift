import SwiftUI

/// The Home tab on a wide iPad. The main cards take the left two thirds and the tile
/// column the right third, so the 2:1 map and the square drawing tile beside it are
/// the same height. Both columns are offered the taller column's height, which lets
/// the tile column end level with the main cards.
struct HomeWideColumnsLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = zip(subviews, columnWidths(width))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths(bounds.width)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func columnWidths(_ width: CGFloat) -> [CGFloat] {
        let tileWidth = (width - spacing) / 3
        return [width - spacing - tileWidth, tileWidth]
    }
}

/// The tile column in the wide Home layout. It stacks the tiles in reverse, so the
/// drawing, written last for the phone's row, sits on top beside the map. The first
/// tile, the milestone, fills whatever height is left below.
struct HomeWideTileColumnLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: max(heights.reduce(gaps, +), proposal.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for index in subviews.indices.reversed() {
            let subview = subviews[index]
            let height = index == subviews.startIndex
                ? bounds.maxY - y
                : subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }
}
