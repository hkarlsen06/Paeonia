#if DEBUG
import PencilKit
import UIKit

/// Sample strokes for previews, at the canonical side. Every part has lines that
/// cross the folds at the same places, so the parts connect when they are stacked.
enum ExquisiteCorpsePreviewDrawings {
    private static let side = GameCanvas.canonicalSide
    private static let neckX: [CGFloat] = [130, 190]
    private static let legX: [CGFloat] = [135, 185]

    /// A round head with ears and a face. Its neck crosses the bottom fold.
    static var head: PKDrawing {
        var strokes = [
            stroke(ellipse(CGPoint(x: 160, y: 140), 95, 85), .paeoniaWidgetDrawing),
            stroke([CGPoint(x: 90, y: 90), CGPoint(x: 80, y: 20), CGPoint(x: 135, y: 62)], .paeoniaWidgetDrawing),
            stroke([CGPoint(x: 230, y: 90), CGPoint(x: 240, y: 20), CGPoint(x: 185, y: 62)], .paeoniaWidgetDrawing),
            stroke([CGPoint(x: 125, y: 125), CGPoint(x: 126, y: 126)], .paeoniaInkGold, width: 14),
            stroke([CGPoint(x: 195, y: 125), CGPoint(x: 196, y: 126)], .paeoniaInkGold, width: 14),
            stroke([CGPoint(x: 135, y: 170), CGPoint(x: 160, y: 185), CGPoint(x: 185, y: 170)], .paeoniaInkLavender),
        ]
        for x in neckX {
            strokes.append(stroke([CGPoint(x: x, y: 220), CGPoint(x: x, y: side)], .paeoniaWidgetDrawing))
        }
        return PKDrawing(strokes: strokes)
    }

    /// The bottom of the head, as the next drawer gets it.
    static var headStrip: PKDrawing {
        let fold = ExquisiteCorpseFold.foldY(side: side)
        return PKDrawing(strokes: neckX.map { x in
            stroke([CGPoint(x: x, y: fold), CGPoint(x: x, y: side)], .paeoniaWidgetDrawing)
        })
    }

    /// A striped sweater between the neck and the legs.
    static var body: PKDrawing {
        var strokes: [PKStroke] = []
        for x in neckX {
            strokes.append(stroke([CGPoint(x: x, y: 0), CGPoint(x: x, y: 30)], .paeoniaWidgetDrawing))
        }
        let outline = [
            CGPoint(x: neckX[0], y: 30), CGPoint(x: 70, y: 50), CGPoint(x: 60, y: 200),
            CGPoint(x: 100, y: 205), CGPoint(x: 100, y: 245), CGPoint(x: 220, y: 245),
            CGPoint(x: 220, y: 205), CGPoint(x: 260, y: 200), CGPoint(x: 250, y: 50),
            CGPoint(x: neckX[1], y: 30),
        ]
        strokes.append(stroke(outline, .paeoniaInkBlue))
        let stripeYs: [CGFloat] = [70, 115, 160]
        for (index, y) in stripeYs.enumerated() {
            let color: UIColor = index.isMultiple(of: 2) ? .paeoniaInkGold : .paeoniaInkLavender
            strokes.append(stroke([CGPoint(x: 80, y: y), CGPoint(x: 240, y: y)], color, width: 8))
        }
        for x in legX {
            strokes.append(stroke([CGPoint(x: x, y: 245), CGPoint(x: x, y: side)], .paeoniaInkGold))
        }
        return PKDrawing(strokes: strokes)
    }

    /// Thin legs with three-toed feet.
    static var legs: PKDrawing {
        var strokes: [PKStroke] = []
        for x in legX {
            strokes.append(stroke([CGPoint(x: x, y: 0), CGPoint(x: x, y: 230)], .paeoniaInkGold))
            let foot = [CGPoint(x: x - 30, y: 285), CGPoint(x: x, y: 230), CGPoint(x: x + 30, y: 285)]
            strokes.append(stroke(foot, .paeoniaInkGold))
            strokes.append(stroke([CGPoint(x: x, y: 230), CGPoint(x: x, y: 290)], .paeoniaInkGold))
        }
        return PKDrawing(strokes: strokes)
    }

    private static func stroke(_ points: [CGPoint], _ color: UIColor, width: CGFloat = 6) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: Double(index) * 0.05,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: color),
            path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSinceReferenceDate: 0))
        )
    }

    private static func ellipse(_ center: CGPoint, _ radiusX: CGFloat, _ radiusY: CGFloat) -> [CGPoint] {
        (0...40).map { step in
            let angle = Double(step) / 40 * 2 * .pi
            return CGPoint(x: center.x + radiusX * cos(angle), y: center.y + radiusY * sin(angle))
        }
    }
}
#endif
