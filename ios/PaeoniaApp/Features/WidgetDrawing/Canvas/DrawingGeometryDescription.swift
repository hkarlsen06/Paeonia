import Foundation
import PencilKit

/// Only describes stroke geometry. It never guesses an object, a game answer,
/// or content outside the supplied drawing, such as the folded creature parts.
@MainActor
enum DrawingGeometryDescription {
    static func text(_ drawing: PKDrawing, side: CGFloat) -> String {
        ([String(localized: .drawingGeometryExplanation)] + marks(drawing, side: side)).joined(separator: "\n")
    }

    static func marks(_ drawing: PKDrawing, side: CGFloat) -> [String] {
        guard side.isFinite, side > 0 else { return [] }
        return drawing.strokes.enumerated().map { index, stroke in
            let bounds = stroke.renderBounds
            func percent(_ value: CGFloat) -> Int32 {
                guard value.isFinite else { return 0 }
                return Int32(min(max((value / side * 100).rounded(), 0), 100))
            }
            let shape = DrawingComposition.shape(of: stroke).map { String(localized: $0.label) }
            let color = WidgetDrawingColorChoice.palette.first { $0.uiColor.isEqual(stroke.ink.color) }
                .map { String(localized: $0.accessibilityLabel) }
            let geometry = String(localized: .drawingGeometryMark(
                Int32(index + 1), percent(bounds.midX), percent(bounds.midY),
                percent(bounds.width), percent(bounds.height)
            ))
            return [shape, color, geometry].compactMap { $0 }.joined(separator: ". ")
        }
    }
}
