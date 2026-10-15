import SwiftUI

/// Where a card goes in `HomeWideLayout`. The phone stack ignores it.
nonisolated enum HomeWideRole: LayoutValueKey {
    /// One of the cards, in whichever column ends highest.
    case card
    /// The map, across the top of the left two columns.
    case map
    /// The milestone and drawing tiles, side by side under the map.
    case tiles

    static let defaultValue = HomeWideRole.card
}

/// The Home tab on a wide iPad: three columns about phone width. The map and the tile
/// row under it take the left two columns, so the two square tiles line up with the
/// columns and the 2:1 map is about as tall as a tile. The cards go in order, each in
/// the column that ends highest, so today's questions start at the top of the right
/// column and later cards fill in under the tiles. The page stays about one screen
/// tall instead of leaving a hole beside a short column.
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
        let columnWidth = (width - 2 * spacing) / 3
        let wideWidth = 2 * columnWidth + spacing
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var wideBottom: CGFloat = 0
        // The phone puts the tiles above the map, so place the map first here.
        for role in [HomeWideRole.map, .tiles] {
            for index in subviews.indices where subviews[index][HomeWideRole.self] == role {
                let height = subviews[index].sizeThatFits(ProposedViewSize(width: wideWidth, height: nil)).height
                frames[index] = CGRect(x: 0, y: wideBottom, width: wideWidth, height: height)
                wideBottom += height + spacing
            }
        }
        var columnTops = [wideBottom, wideBottom, 0]
        for index in subviews.indices where subviews[index][HomeWideRole.self] == .card {
            // Ties go to the right column, so the first card sits beside the map.
            let column = columnTops.indices.reversed().min { columnTops[$0] < columnTops[$1] } ?? 2
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            frames[index] = CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: columnTops[column],
                width: columnWidth,
                height: height
            )
            columnTops[column] += height + spacing
        }
        return frames
    }
}
