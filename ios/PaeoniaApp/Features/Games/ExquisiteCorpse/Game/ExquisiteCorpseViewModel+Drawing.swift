import PencilKit
import SwiftUI

// The drawer's canvas: filling it for the part, keeping the draft on the phone,
// and Done.
extension ExquisiteCorpseViewModel {
    // MARK: - Canvas

    /// Whether the Done button works.
    var canFinishDrawing: Bool {
        phase == .drawing && !board.isEmpty && board.canvasSide > 0 && !isFinishing
    }

    /// Fills the canvas when this person's part starts, and again when a refused
    /// part comes back. The refusal saves the drawing as the draft of the part.
    func syncBoard() {
        // Done is reading this canvas. It syncs again when it returns.
        guard !isFinishing, phase == .drawing, let userID = currentUserID, let partID = ownPartID else { return }
        let store = dependencies.drawingStore
        let isBackFromSending = boardSentPartID == partID
            && store.draft(ownerUserID: userID, roundID: partID) != nil
        guard boardPartID != partID || isBackFromSending else {
            refreshIdeaDeck()
            return
        }
        // The turn may have moved straight to another part of this person's, such
        // as after their other phone sent this one. The canvas stays a draft.
        keepBoard(ownerUserID: userID)
        boardPartID = partID
        boardSentPartID = nil
        doneSentPartID = nil
        board.reset()
        takeLeftoverDraft(into: partID, ownerUserID: userID)
        if let data = store.draft(ownerUserID: userID, roundID: partID), let saved = try? PKDrawing(data: data) {
            board.restore(canonical: saved)
        }
        sentStrip = (partID, PKDrawing().paeoniaContentSignature)
        penSampler = ExquisiteCorpsePenSampler()
        restoreIdea(for: partID)
        // A restored draft may already reach the strip, and a watching partner has not seen it.
        if !board.isEmpty, partnerPresence == .watching {
            resendLiveState()
        }
    }

    /// An empty canvas takes the oldest drawing this phone kept for an earlier
    /// part of this person's that never reached the server: one the server
    /// refused after its turn moved on, or a canvas the turn left when this person
    /// sent the part from another phone. Part ids are known from the game alone
    /// (`ExquisiteCorpseIDs`), so the drafts are found without a list that could
    /// go stale, also after a relaunch or a privacy purge that keeps drafts.
    private func takeLeftoverDraft(into partID: UUID, ownerUserID: UUID) {
        let store = dependencies.drawingStore
        guard store.draft(ownerUserID: ownerUserID, roundID: partID) == nil else { return }
        for leftover in ownRecentPartIDs(ownerUserID: ownerUserID) where leftover != partID {
            guard let data = store.draft(ownerUserID: ownerUserID, roundID: leftover) else { continue }
            store.saveDraft(data, ownerUserID: ownerUserID, roundID: partID)
            store.removeDraft(ownerUserID: ownerUserID, roundID: leftover)
            return
        }
    }

    /// This person's part ids in every figure so far, oldest first. A part that is
    /// not theirs, or not drawn yet, has no draft and is skipped by the caller.
    private func ownRecentPartIDs(ownerUserID: UUID) -> [UUID] {
        guard let game = state?.game, game.figureNumber >= 1 else { return [] }
        return (1...game.figureNumber).flatMap { number in
            (0...2).map { index in
                ExquisiteCorpseIDs.part(gameID: game.id, figureNumber: number, partIndex: index, drawerID: ownerUserID)
            }
        }
    }

    /// The canvas left the drawing phase without a send from this phone, because
    /// this person sent the part from another phone. What is on it stays a draft.
    func keepUnsentBoard() {
        guard phase != .drawing, phase != .loading, let userID = currentUserID, boardPartID != nil else { return }
        keepBoard(ownerUserID: userID)
        if !isFinishing {
            boardPartID = nil
        }
    }

    /// Saves the canvas as the draft of its part, unless this phone sent that part
    /// or is sending it right now. Done saves its own drawing when the turn moved
    /// on while it ran. A canvas the person cleared leaves no draft behind.
    private func keepBoard(ownerUserID: UUID) {
        guard let partID = boardPartID, boardSentPartID != partID, !isFinishing, board.canvasSide > 0 else { return }
        guard !board.isEmpty else {
            dependencies.drawingStore.removeDraft(ownerUserID: ownerUserID, roundID: partID)
            return
        }
        dependencies.drawingStore.saveDraft(
            board.canonicalDrawing.dataRepresentation(),
            ownerUserID: ownerUserID,
            roundID: partID
        )
    }

    func drawingChangedByUser(_: PKDrawing) {
        draftTask?.cancel()
        draftTask = Task { [weak self, sleep] in
            try? await sleep(.seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveDraftNow(inBackground: true)
        }
        sendStripIfChanged()
    }

    /// Keeps the unsent part on the phone, so closing the app loses nothing. The
    /// delayed save after a stroke scales, encodes and writes off the main
    /// actor. Leaving the screen saves right away.
    func saveDraftNow(inBackground: Bool = false) {
        // Done owns the drawing while it queues it, and a sent part needs no draft.
        guard !isFinishing, let userID = currentUserID, phase == .drawing, let partID = ownPartID,
              boardPartID == partID, boardSentPartID != partID
        else { return }
        if board.isEmpty || board.canvasSide <= 0 {
            if board.isEmpty {
                dependencies.drawingStore.removeDraft(ownerUserID: userID, roundID: partID)
            }
            return
        }
        if inBackground {
            dependencies.drawingStore.saveDraftInBackground(
                board.drawing,
                fromSide: board.canvasSide,
                ownerUserID: userID,
                roundID: partID
            )
            return
        }
        dependencies.drawingStore.saveDraft(
            board.canonicalDrawing.dataRepresentation(),
            ownerUserID: userID,
            roundID: partID
        )
    }

    // MARK: - Done

    /// Sends the part. It is saved on the phone first and goes out when the phone
    /// is online. The partner sees Done right away when they are watching.
    func finishDrawing() async {
        guard canFinishDrawing, let part, let partID = ownPartID else { return }
        isFinishing = true
        // A late eraser change and a stroke in progress are read first, so they go out too.
        let drawing = await board.finishedCanonicalDrawing()
        if phase == .drawing, ownPartID == partID, !drawing.strokes.isEmpty {
            await queuePart(part, id: partID, drawing: drawing)
        } else if !drawing.strokes.isEmpty, let userID = currentUserID {
            // The turn moved on while a stroke finished, such as when the other
            // phone sent this part. The drawing stays a draft of its part.
            dependencies.drawingStore.saveDraft(drawing.dataRepresentation(), ownerUserID: userID, roundID: partID)
        }
        isFinishing = false
        // The canvas waited for Done. The turn may have moved meanwhile, and the
        // canvas follows it now.
        recompute()
    }

    private func queuePart(_ part: ExquisiteCorpsePartKind, id partID: UUID, drawing: PKDrawing) async {
        guard let userID = currentUserID, let coupleID = participants.coupleID,
              let game = state?.game, let figureID = figureIDToSend
        else { return }
        let data = drawing.dataRepresentation()
        guard WidgetDrawingLimits.allows(
            byteCount: data.count,
            strokeCount: drawing.strokes.count,
            pointCount: drawing.paeoniaPointCount
        ) else {
            notice = .drawingTooBig
            return
        }
        // The draft saves again if the part can't be queued.
        draftTask?.cancel()
        // The strip is clipped here, so the hidden part of the drawing never leaves the phone as a file either.
        let strip = part.hasStrip ? ExquisiteCorpseFold.strip(of: drawing) : nil
        let payload = ExquisiteCorpseSubmitPartPayload(
            gameID: game.id,
            figureID: figureID,
            partID: partID,
            partIndex: part.rawValue,
            coupleID: coupleID,
            drawing: makeUpload(data),
            strip: strip.map { makeUpload($0.dataRepresentation()) },
            idea: idea,
            createdAt: dependencies.now()
        )
        let scope = "exquisite-corpse-part:\(partID.uuidString.lowercased())"
        // The queued part carries the drawing from here on. The draft goes first,
        // because the send can start, and be refused and put the drawing back as
        // the draft, before `enqueue` returns.
        dependencies.drawingStore.removeDraft(ownerUserID: userID, roundID: partID)
        guard await enqueue(.exquisiteCorpseSubmitPart, scope: scope, payload: payload) else {
            dependencies.drawingStore.saveDraft(data, ownerUserID: userID, roundID: partID)
            return
        }
        boardSentPartID = partID
        sendDoneLive(partID: partID, strip: strip)
    }

    /// A file to upload, with the client operations of its two steps made up front,
    /// so a retry replays the same requests.
    private func makeUpload(_ data: Data) -> ExquisiteCorpseQueuedUpload {
        ExquisiteCorpseQueuedUpload(
            data: data,
            reserveOperation: dependencies.operationProvider.makeOperation(),
            finalizeOperation: dependencies.operationProvider.makeOperation()
        )
    }
}
