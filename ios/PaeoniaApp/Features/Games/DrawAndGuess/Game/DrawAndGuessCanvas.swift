import ImageIO
import SwiftUI
import PencilKit
import UIKit

/// How a drawing travels between phones and into Memories.
enum DrawAndGuessCanvas {
    /// Every drawing is stored and sent on a square canvas of this many points.
    /// Phones draw on canvases of different sizes, so the drawer scales to this
    /// size before sending and the guesser scales to their own canvas. It is the
    /// size the live room already uses.
    nonisolated static let canonicalSide: CGFloat = WidgetLiveRoom.side

    /// Scales a drawing made on a canvas of `side` points to the canonical size.
    nonisolated static func canonical(_ drawing: PKDrawing, fromSide side: CGFloat) -> PKDrawing {
        drawing.scaled(fromSide: side, toSide: canonicalSide)
    }

    /// Scales a canonical drawing to a canvas of `side` points.
    nonisolated static func fitted(_ drawing: PKDrawing, toSide side: CGFloat) -> PKDrawing {
        drawing.scaled(fromSide: canonicalSide, toSide: side)
    }
}

/// Renders a finished drawing as the image that becomes the memory's photo. It
/// uses the background of the drawing screen, so the ink looks as it did on the
/// canvas.
enum DrawAndGuessImageRenderer {
    nonisolated static let mimeType = "image/jpeg"
    nonisolated static let fileExtension = "jpg"
    nonisolated static let pixelSide: CGFloat = 1_080

    /// - Parameter drawing: A drawing at the canonical canvas size.
    @MainActor
    static func render(_ drawing: PKDrawing) -> Data? {
        let side = DrawAndGuessCanvas.canonicalSide
        let scale = pixelSide / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)

        var strokes: UIImage?
        // The canvas is always light, so literal ink colors render as drawn.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            strokes = drawing.image(from: bounds, scale: scale)
        }
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor(Color.paeoniaBackgroundPrimary).setFill()
            context.fill(bounds)
            strokes?.draw(in: bounds)
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    /// The size in pixels of a rendered image. Memories need it with every photo.
    nonisolated static func pixelSize(of imageData: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else {
            return nil
        }
        return (width, height)
    }
}
