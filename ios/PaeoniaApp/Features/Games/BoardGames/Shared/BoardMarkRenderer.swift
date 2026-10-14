import PencilKit
import UIKit

/// Turns a stored mark into the template image the boards tint. A mark is a
/// `PKDrawing` made on a square canvas of `canvasSide` points, kept on the server
/// as base64 data of at most `maximumByteCount` bytes.
nonisolated enum BoardMarkRenderer {
    /// The side, in points, of the square canvas every mark is stored on. The
    /// editor scales its own canvas to this size before saving, and the renderer
    /// draws exactly this square, so a mark looks the same on every phone.
    static let canvasSide: CGFloat = 256
    /// Pixels on each side of the rendered image. A mark can be drawn large over
    /// a won small board in Ultimate Tic-Tac-Toe, so this is not much smaller than
    /// the canvas.
    static let pixelSide: CGFloat = 256
    /// The most raw drawing data the server keeps for a mark (`set_board_game_mark`).
    static let maximumByteCount = 48 * 1_024
    /// The smallest square a mark is cropped to, so a tiny mark is enlarged at
    /// most twice and its strokes stay thin.
    static let minimumCropSide: CGFloat = canvasSide / 2
    /// Room left around the strokes, as a share of the cropped square's side.
    static let cropPadding: CGFloat = 0.06

    /// NSCache is thread safe, so sharing this one instance across actors is safe.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()

    /// The drawing data inside the base64 text the server sends. Nil when the
    /// text is not base64.
    static func data(fromBase64 text: String) -> Data? {
        Data(base64Encoded: text)
    }

    /// True when the server accepts a mark of this size.
    static func fits(_ data: Data) -> Bool {
        data.count <= maximumByteCount
    }

    static func cachedImage(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// Forgets every picture. A privacy purge calls it with the data it removes.
    static func removeAll() {
        cache.removeAllObjects()
    }

    /// The drawing as a template image, or nil when `data` is not a drawing or has
    /// no strokes. The image has no background and is a square cropped around the
    /// strokes, so a mark drawn small or off to one side still fills its piece.
    /// A `cacheKey` such as "<userID>:<updatedAt>" keeps the image in
    /// memory and returns it on the next call without drawing again.
    @concurrent
    static func image(from data: Data, cacheKey: String? = nil) async -> UIImage? {
        if let cacheKey, let cached = cachedImage(forKey: cacheKey) {
            return cached
        }
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        var rendered: UIImage?
        // The canvas is always light, so literal ink colors render as drawn.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            let crop = cropRect(around: drawing.bounds)
            rendered = drawing.image(from: crop, scale: pixelSide / crop.width)
        }
        guard let image = rendered?.withRenderingMode(.alwaysTemplate) else { return nil }
        if let cacheKey {
            cache.setObject(image, forKey: cacheKey as NSString, cost: Int(pixelSide * pixelSide) * 4)
        }
        return image
    }

    /// A square centered on `bounds`, with padding, no smaller than
    /// `minimumCropSide`.
    static func cropRect(around bounds: CGRect) -> CGRect {
        let side = max(max(bounds.width, bounds.height) / (1 - 2 * cropPadding), minimumCropSide)
        return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }
}
