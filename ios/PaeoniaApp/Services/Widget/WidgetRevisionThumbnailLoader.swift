import CoreGraphics
import Foundation

/// Renders small previews of past revisions for the history timeline. Abstracted
/// so the timeline can be tested and previewed without the network.
nonisolated protocol WidgetRevisionThumbnailLoading: Sendable {
    /// PNG data for a revision's thumbnail, or nil if it can't be built. Cached
    /// after the first successful render so re-scrolling is free.
    func thumbnailPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) async -> Data?

    /// A full-quality PNG of a revision for saving to the device, rendered larger
    /// than the timeline thumbnail. Not cached: saving is a one-off action.
    func exportPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) async -> Data?
}

/// Downloads a revision's payload and rasterizes it into a thumbnail. Loads are
/// lazy (driven per cell), deduped while in flight, and cached by revision id.
actor WidgetRevisionThumbnailLoader: WidgetRevisionThumbnailLoading {
    private let gateway: any WidgetCanvasGateway
    private let downloader: any WidgetPayloadDownloading
    private let rasterizer = WidgetDrawingRasterizer()
    private let pixelWidth: CGFloat
    private let exportPixelWidth: CGFloat
    private var cache: [UUID: Data] = [:]
    private var inFlight: [UUID: Task<Data?, Never>] = [:]

    init(
        gateway: any WidgetCanvasGateway,
        downloader: any WidgetPayloadDownloading = URLSessionWidgetPayloadDownloader(),
        pixelWidth: CGFloat = 240,
        exportPixelWidth: CGFloat = 1_024
    ) {
        self.gateway = gateway
        self.downloader = downloader
        self.pixelWidth = pixelWidth
        self.exportPixelWidth = exportPixelWidth
    }

    func thumbnailPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) async -> Data? {
        if let cached = cache[revisionID] {
            return cached
        }
        if let existing = inFlight[revisionID] {
            return await existing.value
        }

        let task = Task {
            await self.render(mediaAssetID: mediaAssetID, canvasSide: canvasSide, pixelWidth: pixelWidth)
        }
        inFlight[revisionID] = task
        let data = await task.value
        inFlight[revisionID] = nil
        if let data {
            cache[revisionID] = data
        }
        return data
    }

    func exportPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) async -> Data? {
        // Render fresh at full quality; the small thumbnail cache isn't reused so
        // the saved image is crisp rather than a 240pt preview blown up.
        await render(mediaAssetID: mediaAssetID, canvasSide: canvasSide, pixelWidth: exportPixelWidth)
    }

    private func render(mediaAssetID: UUID, canvasSide: CGFloat, pixelWidth: CGFloat) async -> Data? {
        guard let url = try? await gateway.signedPayloadURL(mediaAssetID: mediaAssetID),
              let payload = try? await downloader.download(from: url) else {
            return nil
        }
        return await rasterizer.renderPNG(
            fromDrawingData: payload,
            canvasSide: max(canvasSide, 1),
            pixelWidth: pixelWidth
        )
    }
}

/// A loader that produces nothing — used as a default for previews and tests that
/// never exercise thumbnail or export rendering.
nonisolated struct NoOpWidgetRevisionThumbnailLoader: WidgetRevisionThumbnailLoading {
    func thumbnailPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) -> Data? { nil }
    func exportPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) -> Data? { nil }
}
