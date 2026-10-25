import CoreGraphics
import Foundation

/// Solid, dashed or dotted. A canvas-wide choice, like the color, for the pen
/// and the pencil.
nonisolated enum InkLineStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case solid
    case dashed
    case dotted

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .solid:
            .widgetDrawingLineStyleSolid
        case .dashed:
            .widgetDrawingLineStyleDashed
        case .dotted:
            .widgetDrawingLineStyleDotted
        }
    }

    /// The dash layout for a line `lineWidth` wide, or nil for a solid line.
    /// Lengths grow with the width, so a thick dashed line keeps its look,
    /// and have floors, so a thin one still reads as dashed.
    func pattern(lineWidth: CGFloat) -> InkDashPattern? {
        switch self {
        case .solid:
            return nil
        case .dashed:
            let dash = max(3 * lineWidth, 8)
            let gap = max(2 * lineWidth, 6)
            // Each run gets a round end half a line width long at both ends.
            return InkDashPattern(on: dash - lineWidth, period: dash + gap)
        case .dotted:
            return InkDashPattern(on: 0, period: lineWidth + max(lineWidth, 4))
        }
    }
}

/// Where a dashed or dotted line shows ink, along its length from the start.
nonisolated struct InkDashPattern: Equatable, Sendable {
    /// The length of each run of ink, not counting its round ends. Zero for
    /// dots.
    var on: CGFloat
    /// From the start of one run to the start of the next.
    var period: CGFloat
}
