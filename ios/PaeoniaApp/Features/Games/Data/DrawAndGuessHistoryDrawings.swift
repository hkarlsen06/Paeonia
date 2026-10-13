import PencilKit
import UIKit

/// Reads the drawings of finished rounds for "Our drawings". A drawing already
/// on the phone loads from disk. Any other one downloads through the same path
/// the game uses and stays on the phone, so the screen works offline for the
/// drawings it showed before.
nonisolated struct DrawAndGuessHistoryDrawings: Sendable {
    let store: any GameDrawingStoring
    let transfer: any GameDrawingTransferring

    /// The `.pkdrawing` bytes. Nil when the phone has no copy and the download fails.
    func data(for mediaAssetID: UUID) async -> Data? {
        if let kept = store.downloadedDrawing(mediaAssetID: mediaAssetID) {
            return kept
        }
        guard let downloaded = try? await transfer.downloadDrawing(mediaAssetID: mediaAssetID) else { return nil }
        store.saveDownloadedDrawing(downloaded, mediaAssetID: mediaAssetID)
        return downloaded
    }

    func drawing(for mediaAssetID: UUID) async -> PKDrawing? {
        guard let data = await data(for: mediaAssetID) else { return nil }
        return try? PKDrawing(data: data)
    }

    /// The thumbnail from memory, or one rendered off the main actor.
    func thumbnail(for mediaAssetID: UUID) async -> UIImage? {
        if let cached = DrawAndGuessThumbnails.cachedImage(for: mediaAssetID) {
            return cached
        }
        guard let data = await data(for: mediaAssetID) else { return nil }
        return await DrawAndGuessThumbnails.render(data, mediaAssetID: mediaAssetID)
    }
}

/// Thumbnails of drawings, kept in memory. The picture has no background: the
/// cell puts it on `.paeoniaBackgroundPrimary`.
nonisolated enum DrawAndGuessThumbnails {
    /// Points of the rendered square. The grid cells are smaller than this on a
    /// phone and a little larger on an iPad.
    static let side: CGFloat = 240
    private static let scale: CGFloat = 2

    /// NSCache is thread safe, so sharing this one instance across actors is safe.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    static func cachedImage(for mediaAssetID: UUID) -> UIImage? {
        cache.object(forKey: key(mediaAssetID))
    }

    /// Forgets every picture. A privacy purge calls it with the files it removes.
    static func removeAll() {
        cache.removeAllObjects()
    }

    /// Renders a drawing at the canonical canvas size to a square picture.
    @concurrent
    static func render(_ data: Data, mediaAssetID: UUID) async -> UIImage? {
        guard let drawing = try? PKDrawing(data: data) else { return nil }
        let canvas = DrawAndGuessCanvas.canonicalSide
        var image: UIImage?
        // The canvas is always light, so literal ink colors render as drawn.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(
                from: CGRect(x: 0, y: 0, width: canvas, height: canvas),
                scale: scale * side / canvas
            )
        }
        guard let image else { return nil }
        let cost = image.cgImage.map { $0.width * $0.height * 4 } ?? 0
        cache.setObject(image, forKey: key(mediaAssetID), cost: cost)
        return image
    }

    private static func key(_ mediaAssetID: UUID) -> NSString {
        mediaAssetID.uuidString as NSString
    }
}
