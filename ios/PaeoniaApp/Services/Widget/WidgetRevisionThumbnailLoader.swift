import CoreGraphics
import Foundation

/// Renders small previews of past revisions for the history timeline. Abstracted
/// so the timeline can be tested and previewed without the network.
nonisolated protocol WidgetRevisionThumbnailLoading: Sendable {
    /// PNG data for a revision's thumbnail, or nil if it can't be built. Cached
    /// after the first successful render so re-scrolling is free.
    func thumbnailPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) async -> Data?
}

/// Downloads a revision's payload and rasterizes it into a thumbnail. Loads are
/// lazy (driven per cell), deduped while in flight, and cached by revision id.
actor WidgetRevisionThumbnailLoader: WidgetRevisionThumbnailLoading {
    private let gateway: any WidgetCanvasGateway
    private let downloader: any WidgetPayloadDownloading
    private let rasterizer = WidgetDrawingRasterizer()
    private let pixelWidth: CGFloat
    private var cache: [UUID: Data] = [:]
    private var inFlight: [UUID: Task<Data?, Never>] = [:]

    init(
        gateway: any WidgetCanvasGateway,
        downloader: any WidgetPayloadDownloading = URLSessionWidgetPayloadDownloader(),
        pixelWidth: CGFloat = 240
    ) {
        self.gateway = gateway
        self.downloader = downloader
        self.pixelWidth = pixelWidth
    }

    func thumbnailPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) async -> Data? {
        if let cached = cache[revisionID] {
            return cached
        }
        if let existing = inFlight[revisionID] {
            return await existing.value
        }

        let task = Task { await self.render(mediaAssetID: mediaAssetID, canvasSide: canvasSide) }
        inFlight[revisionID] = task
        let data = await task.value
        inFlight[revisionID] = nil
        if let data {
            cache[revisionID] = data
        }
        return data
    }

    private func render(mediaAssetID: UUID, canvasSide: CGFloat) async -> Data? {
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
