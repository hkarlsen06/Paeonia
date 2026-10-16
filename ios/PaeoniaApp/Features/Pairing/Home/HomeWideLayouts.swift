import SwiftUI

/// Where a card goes in `HomeWideLayout`. The phone stack ignores it.
nonisolated enum HomeWideRole: LayoutValueKey {
    /// One column wide.
    case card
    /// The milestone and drawing tiles, side by side across two columns.
    case tiles

    static let defaultValue = HomeWideRole.card
}

/// The Home tab on a wide iPad: three columns about phone width. The cards keep the
/// phone's order and fill in the way people read, left to right and then down. Each card
/// goes in the column that ends highest, and ties go left, so today's questions start at
/// the top left. The tile pair takes the two neighboring columns that end highest, so its
/// squares line up with the columns and with the square map.
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
        var columnTops: [CGFloat] = [0, 0, 0]
        return subviews.map { subview in
            let span = subview[HomeWideRole.self] == .tiles ? 2 : 1
            let starts = Array(0...(columnTops.count - span))
            let top = { (start: Int) in columnTops[start..<(start + span)].max() ?? 0 }
            // `min(by:)` keeps the first of equal elements, so ties go left.
            let column = starts.min { top($0) < top($1) } ?? 0
            let y = top(column)
            let frameWidth = CGFloat(span) * columnWidth + CGFloat(span - 1) * spacing
            let height = subview.sizeThatFits(ProposedViewSize(width: frameWidth, height: nil)).height
            for index in column..<(column + span) {
                columnTops[index] = y + height + spacing
            }
            return CGRect(x: CGFloat(column) * (columnWidth + spacing), y: y, width: frameWidth, height: height)
        }
    }
}
