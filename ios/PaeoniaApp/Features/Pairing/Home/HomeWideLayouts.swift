import SwiftUI

/// The Home tab on a wide iPad. The main cards take the left two thirds and the tile
/// column the right third, so the 2:1 map and the square drawing tile beside it are
/// the same height. Each column takes its own height.
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
                proposal: ProposedViewSize(width: width, height: nil)
            )
            x += width + spacing
        }
    }

    private func columnWidths(_ width: CGFloat) -> [CGFloat] {
        let tileWidth = (width - spacing) / 3
        return [width - spacing - tileWidth, tileWidth]
    }
}

/// Marks the card that spans the top of `HomeWideMainCardsLayout`.
struct HomeWideSpansFullWidth: LayoutValueKey {
    static let defaultValue = false
}

/// The main cards in the wide Home layout. The card marked with
/// `HomeWideSpansFullWidth`, the map, spans the full width at the top. The rest go
/// in two columns below it in order, each card in the column that ends higher, so
/// the cards stay about phone width and today's questions sit beside the game card
/// instead of below it.
struct HomeWideMainCardsLayout: Layout {
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
        let topHeight = subviews.first { $0[HomeWideSpansFullWidth.self] }
            .map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height + spacing } ?? 0
        let columnWidth = (width - spacing) / 2
        var columnTops = [topHeight, topHeight]
        return subviews.map { subview in
            if subview[HomeWideSpansFullWidth.self] {
                return CGRect(x: 0, y: 0, width: width, height: topHeight - spacing)
            }
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
