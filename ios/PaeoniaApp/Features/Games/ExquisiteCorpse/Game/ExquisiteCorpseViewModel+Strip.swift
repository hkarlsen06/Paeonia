import PencilKit
import SwiftUI

// The strip above the canvas of a body or legs drawer: the bottom 12% of the
// partner's part before. The strip file is the real thing. If the partner drew
// the part while this phone watched, the live strip fills in until the file has
// loaded. The two are the same drawing.
extension ExquisiteCorpseViewModel {
    /// The id of the partner's part above this person's canvas.
    var previousPartID: UUID? {
        guard phase == .drawing, let part, part.hasStripAbove, let game = state?.game, let partnerID = partnerUserID
        else { return nil }
        return ExquisiteCorpseIDs.part(
            gameID: game.id,
            figureNumber: game.figureNumber,
            partIndex: part.rawValue - 1,
            drawerID: partnerID
        )
    }

    /// The strip file of the part above, once the server has it.
    var stripAssetID: UUID? {
        guard phase == .drawing, let part, let previous = part.previous else { return nil }
        return figure?.part(at: previous.rawValue)?.stripMediaAssetID
    }

    /// Works out what the strip shows: the loaded file, or else the strip the
    /// partner sent live. The head has no strip. The strip stays on screen when
    /// the person leaves the drawing phase, so it can fade out with the screen.
    func updateStrip() {
        guard phase == .drawing else { return }
        guard part?.hasStripAbove == true else {
            if strip != nil { strip = nil }
            if isLoadingStrip || stripLoadFailed { cancelStripLoad(); stripLoadFailed = false }
            return
        }
        let file = downloadedStrip.flatMap { $0.assetID == stripAssetID ? $0.drawing : nil }
        let shown = file ?? previousPartID.flatMap { liveStrips[$0] }
        if strip != shown {
            strip = shown
        }
    }

    /// Fetches the strip file. It waits while the screen is closed or the app is
    /// in the background. A strip already on the phone shows in the same update.
    func loadStripIfNeeded() {
        guard isActive, !isStopped, phase == .drawing, let userID = currentUserID, let assetID = stripAssetID,
              downloadedStrip?.assetID != assetID, loadingStripAssetID != assetID
        else { return }
        loadingStripAssetID = assetID
        stripLoadFailed = false
        if let cached = dependencies.drawingStore.downloadedDrawing(mediaAssetID: assetID) {
            finishStripLoad(assetID: assetID, ownerUserID: userID, data: cached, isDownloaded: false)
            return
        }
        isLoadingStrip = true
        let transfer = dependencies.drawingTransfer
        stripTask = Task { [weak self] in
            let data = try? await transfer.downloadDrawing(mediaAssetID: assetID)
            guard !Task.isCancelled else { return }
            self?.finishStripLoad(assetID: assetID, ownerUserID: userID, data: data, isDownloaded: true)
        }
    }

    /// "Try again" on the strip that could not load.
    func retryLoadingStrip() {
        stripLoadFailed = false
        loadStripIfNeeded()
    }

    /// Stops a fetch that is still running, and forgets that it was.
    func cancelStripLoad() {
        stripTask?.cancel()
        stripTask = nil
        loadingStripAssetID = nil
        isLoadingStrip = false
    }

    private func finishStripLoad(assetID: UUID, ownerUserID: UUID, data: Data?, isDownloaded: Bool) {
        // A fetch that outlived its part, or this person's session, writes nothing.
        guard loadingStripAssetID == assetID, currentUserID == ownerUserID else { return }
        loadingStripAssetID = nil
        stripTask = nil
        isLoadingStrip = false
        if isDownloaded, let data {
            dependencies.drawingStore.saveDownloadedDrawing(data, mediaAssetID: assetID)
        }
        guard let data, let decoded = try? PKDrawing(data: data) else {
            // The next state change tries again, so a phone that was offline recovers.
            stripLoadFailed = stripAssetID == assetID
            return
        }
        stripLoadFailed = false
        downloadedStrip = (assetID, decoded)
        updateStrip()
    }
}
