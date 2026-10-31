import PencilKit
import UIKit

/// Coordinates are percentages of the square canvas. Every mark is one real
/// PencilKit stroke, so drafts, live drawing, undo and uploads use the same data.
nonisolated enum DrawingComposition {
    enum Shape: String, CaseIterable, Identifiable {
        case circle, rectangle, triangle, horizontalLine, verticalLine, diagonalLine
        var id: Self { self }
    }

    static func points(shape: Shape, x: Double, y: Double, size: Double, side: CGFloat) -> [CGPoint] {
        guard side.isFinite, side > 0, x.isFinite, y.isFinite, size.isFinite else { return [] }
        let radius = min(max(size, 2), 90) / 200
        let centerX = min(max(x / 100, radius), 1 - radius)
        let centerY = min(max(y / 100, radius), 1 - radius)
        let offsets: [(Double, Double)]
        switch shape {
        case .circle:
            offsets = (0...64).map { index in
                let angle = Double(index) * 2 * .pi / 64
                return (cos(angle), sin(angle))
            }
        case .rectangle: offsets = [(-1, -1), (1, -1), (1, 1), (-1, 1), (-1, -1)]
        case .triangle: offsets = [(0, -1), (1, 1), (-1, 1), (0, -1)]
        case .horizontalLine: offsets = [(-1, 0), (1, 0)]
        case .verticalLine: offsets = [(0, -1), (0, 1)]
        case .diagonalLine: offsets = [(-1, -1), (1, 1)]
        }
        return offsets.map { CGPoint(x: (centerX + $0.0 * radius) * side, y: (centerY + $0.1 * radius) * side) }
    }

    static func stroke(shape: Shape, x: Double, y: Double, size: Double, side: CGFloat, color: UIColor) -> PKStroke? {
        let locations = points(shape: shape, x: x, y: y, size: size, side: side)
        guard !locations.isEmpty else { return nil }
        let width = max(1, side * 0.012)
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.01,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    static func shape(of stroke: PKStroke) -> Shape? {
        guard stroke.mask == nil else { return nil }
        let actual = stroke.path.map { $0.location.applying(stroke.transform) }
        for shape in Shape.allCases {
            let expected = points(shape: shape, x: 50, y: 50, size: 50, side: 1)
            guard expected.count == actual.count else { continue }
            func normalized(_ points: [CGPoint]) -> [CGPoint] {
                let xs = points.map(\.x)
                let ys = points.map(\.y)
                let left = xs.min() ?? 0
                let top = ys.min() ?? 0
                let width = (xs.max() ?? 0) - left
                let height = (ys.max() ?? 0) - top
                return points.map {
                    CGPoint(x: width > 0 ? ($0.x - left) / width : 0,
                            y: height > 0 ? ($0.y - top) / height : 0)
                }
            }
            if zip(normalized(actual), normalized(expected)).allSatisfy({
                abs($0.x - $1.x) < 0.0001 && abs($0.y - $1.y) < 0.0001
            }) { return shape }
        }
        return nil
    }

    static func replacing(_ index: Int?, in drawing: PKDrawing, with stroke: PKStroke?) -> PKDrawing {
        var strokes = drawing.strokes
        if let index, strokes.indices.contains(index) {
            if let stroke { strokes[index] = stroke } else { strokes.remove(at: index) }
        } else if index == nil, let stroke {
            strokes.append(stroke)
        }
        return PKDrawing(strokes: strokes)
    }
}
