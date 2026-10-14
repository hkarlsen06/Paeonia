import PencilKit
import UIKit

/// Reads the drawings of finished rounds or figures for a game's history, such as
/// "Our drawings". A drawing already on the phone loads from disk. Any other one
/// downloads through the same path the game uses and stays on the phone, so the
/// screen works offline for the drawings it showed before.
nonisolated struct GameHistoryDrawings: Sendable {
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
        if let cached = GameDrawingThumbnails.cachedImage(for: mediaAssetID) {
            return cached
        }
        guard let data = await data(for: mediaAssetID) else { return nil }
        return await GameDrawingThumbnails.render(data, mediaAssetID: mediaAssetID)
    }
}
