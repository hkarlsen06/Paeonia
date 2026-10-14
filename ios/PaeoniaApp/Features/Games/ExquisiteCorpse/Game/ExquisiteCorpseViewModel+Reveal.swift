import PencilKit
import SwiftUI

// The reveal: getting the three drawings of the finished figure onto the phone,
// and moving past it.
//
// This person's own parts are on the phone already. The submit handler keeps each
// one under the asset id the server gave it, and a part still queued carries its
// drawing. Only the partner's parts are downloaded.
extension ExquisiteCorpseViewModel {
    // MARK: - Content

    /// Builds the content for the finished figure from the drawings that are on
    /// the phone. Drawings that are still loading are nil, and the reveal waits
    /// with the folded paper until all three are there.
    func updateReveal(_ resolution: ExquisiteCorpseResolution) {
        guard resolution.phase == .reveal, let figure = resolution.figure else {
            if revealFigureID != nil {
                resetReveal()
            }
            return
        }
        if revealFigureID != figure.id {
            resetReveal()
            revealFigureID = figure.id
        }
        for remote in figure.parts {
            guard let kind = remote.kind, revealDrawings[kind] == nil, let drawing = drawingOnPhone(for: remote) else {
                continue
            }
            revealDrawings[kind] = drawing
        }
        publishRevealContent(of: figure)
    }

    /// The part's drawing when this phone has it: a queued part of this person's,
    /// or a file kept under the part's asset id.
    private func drawingOnPhone(for remote: RemoteExquisiteCorpsePart) -> PKDrawing? {
        if let queued = pending.parts.first(where: { $0.partID == remote.id }),
           let drawing = try? PKDrawing(data: queued.drawing.data) {
            return drawing
        }
        guard let assetID = remote.drawingMediaAssetID,
              let data = dependencies.drawingStore.downloadedDrawing(mediaAssetID: assetID)
        else { return nil }
        return try? PKDrawing(data: data)
    }

    private func publishRevealContent(of figure: RemoteExquisiteCorpseFigure) {
        guard let userID = currentUserID else { return }
        let parts = ExquisiteCorpsePartKind.allCases.compactMap { kind -> ExquisiteCorpseRevealContent.Part? in
            guard let remote = figure.part(at: kind.rawValue) else { return nil }
            let isMine = remote.drawerUserID == userID
            return ExquisiteCorpseRevealContent.Part(
                kind: kind,
                drawing: revealDrawings[kind],
                drawerIsMe: isMine,
                drawer: isMine ? me : partner,
                idea: remote.idea?.text
            )
        }
        let content = ExquisiteCorpseRevealContent(
            figureID: figure.id,
            number: figure.number,
            parts: parts,
            partnerName: partnerName,
            // The partner who drew the body starts the next figure.
            nextIsMine: figure.starterUserID != userID
        )
        revealContent = content
        isLoadingReveal = !content.isReady && !loadingRevealAssets.isEmpty
        // A failure stays on screen while the next try runs, so the screen does not flicker.
        revealLoadFailed = !content.isReady && !failedRevealAssets.isEmpty
    }

    // MARK: - Downloads

    /// Downloads the drawings of the reveal that are not on the phone. It waits
    /// while the screen is closed or the app is in the background. A drawing that
    /// failed is tried again on the next state change, so a phone that was
    /// offline recovers.
    func loadRevealDrawingsIfNeeded() {
        guard isActive, !isStopped, phase == .reveal, let figure, figure.id == revealFigureID else { return }
        var started = false
        for remote in figure.parts {
            guard let kind = remote.kind, revealDrawings[kind] == nil,
                  let assetID = remote.drawingMediaAssetID,
                  !loadingRevealAssets.contains(assetID)
            else { continue }
            started = true
            loadingRevealAssets.insert(assetID)
            let transfer = dependencies.drawingTransfer
            let figureID = figure.id
            revealTasks[assetID] = Task { [weak self] in
                let data = try? await transfer.downloadDrawing(mediaAssetID: assetID)
                guard !Task.isCancelled else { return }
                self?.finishRevealDownload(assetID: assetID, kind: kind, figureID: figureID, data: data)
            }
        }
        if started {
            publishRevealContent(of: figure)
        }
    }

    private func finishRevealDownload(assetID: UUID, kind: ExquisiteCorpsePartKind, figureID: UUID, data: Data?) {
        // A fetch that outlived its figure writes nothing.
        guard revealFigureID == figureID, loadingRevealAssets.contains(assetID) else { return }
        loadingRevealAssets.remove(assetID)
        revealTasks[assetID] = nil
        if let data, let drawing = try? PKDrawing(data: data) {
            dependencies.drawingStore.saveDownloadedDrawing(data, mediaAssetID: assetID)
            revealDrawings[kind] = drawing
            failedRevealAssets.remove(assetID)
        } else {
            failedRevealAssets.insert(assetID)
        }
        if let figure, figure.id == figureID {
            publishRevealContent(of: figure)
        }
    }

    /// "Try again" on a reveal whose drawings could not be fetched.
    func retryLoadingReveal() {
        failedRevealAssets = []
        revealLoadFailed = false
        loadRevealDrawingsIfNeeded()
    }

    func cancelRevealLoads() {
        for task in revealTasks.values {
            task.cancel()
        }
        revealTasks = [:]
        loadingRevealAssets = []
        isLoadingReveal = false
    }

    func resetReveal() {
        cancelRevealLoads()
        revealFigureID = nil
        revealDrawings = [:]
        failedRevealAssets = []
        revealContent = nil
        revealLoadFailed = false
    }

    // MARK: - Moving on

    /// Leaves the reveal for the next turn. The "I have seen this" mark is saved on
    /// the phone first, so the screen moves on at once without the network. The
    /// server keeps it per person, so a second phone and a fresh install do not
    /// show the same figure again.
    func continueFromReveal() async {
        guard phase == .reveal, let figure, !isContinuing, !pending.hasRevealSeen(figureID: figure.id) else { return }
        isContinuing = true
        defer { isContinuing = false }
        let payload = ExquisiteCorpseRevealSeenPayload(figureID: figure.id, createdAt: dependencies.now())
        await enqueue(
            .exquisiteCorpseRevealSeen,
            scope: "exquisite-corpse-reveal-seen:\(figure.id.uuidString.lowercased())",
            payload: payload
        )
    }
}
