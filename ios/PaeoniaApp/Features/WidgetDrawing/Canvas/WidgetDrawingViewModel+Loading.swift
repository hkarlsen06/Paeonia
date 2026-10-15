import PencilKit
import UIKit

extension WidgetDrawingViewModel {
    private static let draftPersistenceDelay: Duration = .milliseconds(250)

    /// Loads the drawing on the widgets into the canvas once, or an unsent draft
    /// if there is one. Never replaces strokes drawn while it loads.
    func loadSavedDrawingIfNeeded() async {
        guard !hasLoadedSavedDrawing else {
            return
        }
        hasLoadedSavedDrawing = true
        setAsideDrawing = setAsideKey
            .flatMap { draftStore.draft(for: $0) }
            .flatMap { try? PKDrawing(data: $0) }

        guard drawing.strokes.isEmpty else {
            return
        }
        let signatureBeforeLoad = drawingSignature

        let snapshot = await service.loadSavedSnapshot()
        let hasPendingUpload = await uploader.hasPendingUpload
        if hasPendingUpload, delivery == .idle {
            delivery = .waiting
        }
        let savedDrawing = snapshot.flatMap { try? PKDrawing(data: $0.drawingData) }
        let targetSide = laidOutCanvasSide ?? snapshot?.canvasSide ?? drawingCanvasSide
        if let savedDrawing {
            setBaseline(
                savedDrawing.scaled(fromSide: snapshot?.canvasSide ?? targetSide ?? 0, toSide: targetSide ?? 0),
                authorName: snapshot?.authorName?.trimmedNonEmpty,
                createdAt: snapshot?.createdAt
            )
        }

        // The person may have started drawing while the saved drawing loaded.
        // Their strokes win; the loaded drawing is still the baseline above.
        guard drawingSignature == signatureBeforeLoad else {
            return
        }

        restoreDraftOrBaseline()
        drawingCanvasSide = targetSide
        fitDrawingToCanvas()
    }

    /// Puts an unsent draft on the canvas, or the drawing on the widgets.
    private func restoreDraftOrBaseline() {
        guard let draftKey = usableDraftKey, let draftData = draftStore.draft(for: draftKey) else {
            replaceDrawing(with: savedBaseline ?? PKDrawing())
            return
        }
        guard let draftDrawing = try? PKDrawing(data: draftData) else {
            draftStore.removeDraft(for: draftKey)
            replaceDrawing(with: savedBaseline ?? PKDrawing())
            return
        }
        // The draft was made on a drawing that is no longer on the widgets, for
        // example the partner sent a new one since. Showing both at once would
        // pile one drawing on the other, so the new one goes on the canvas and
        // the draft is kept aside.
        if widgetsChanged(since: draftKey) {
            setAside(draftDrawing)
            draftStore.removeDraft(for: draftKey)
            replaceDrawing(with: savedBaseline ?? PKDrawing())
            return
        }
        // A draft is from this phone, so it is already in the canvas's size.
        replaceDrawing(with: draftDrawing)
        if draftDrawing.paeoniaContentSignature == lastSavedDrawingSignature {
            draftStore.removeDraft(for: draftKey)
        }
    }

    /// Picks up a drawing that synced in while this screen is open. With no
    /// unsent changes the canvas shows it. With unsent changes the canvas keeps
    /// them, and the screen says the partner sent something new.
    func reloadSavedDrawingFromSyncIfSafe() async {
        // Our own save posts the same update. While it publishes, nothing else
        // can land (it is marked as not sent yet), and it sets the baseline itself.
        guard !isPublishing else {
            return
        }
        guard !isDrawingStroke else {
            reloadAfterStroke = true
            return
        }
        let signatureBeforeLoad = drawingSignature
        let hadUnsavedEdits = hasUnsavedEdits && !drawing.strokes.isEmpty

        guard let snapshot = await service.loadSavedSnapshot(),
              let loadedDrawing = try? PKDrawing(data: snapshot.drawingData),
              !isPublishing
        else {
            return
        }

        let targetSide = drawingCanvasSide ?? laidOutCanvasSide ?? snapshot.canvasSide
        let savedDrawing = loadedDrawing.scaled(
            fromSide: snapshot.canvasSide ?? targetSide ?? 0,
            toSide: targetSide ?? 0
        )
        guard savedDrawing.paeoniaContentSignature != lastSavedDrawingSignature else {
            refreshAttribution(from: snapshot)
            return
        }

        // A finger went down while the drawing loaded. Try again once it lifts,
        // before anything changes.
        guard !isDrawingStroke else {
            reloadAfterStroke = true
            return
        }

        // A different drawing must never inherit the previous one's attribution.
        setBaseline(savedDrawing, authorName: snapshot.authorName?.trimmedNonEmpty, createdAt: snapshot.createdAt)
        hasLoadedSavedDrawing = true

        guard !canvasAlreadyShows(savedDrawing) else {
            return
        }

        // Strokes drawn while the drawing loaded count as unsent changes too.
        let editedMeanwhile = drawingSignature != signatureBeforeLoad
        guard setAsideUnsentWork(if: hadUnsavedEdits || editedMeanwhile) else {
            return
        }
        showSavedDrawing(savedDrawing, side: targetSide)
    }

    private func showSavedDrawing(_ savedDrawing: PKDrawing, side: CGFloat?) {
        replaceDrawing(with: savedDrawing)
        drawingCanvasSide = side
        if let draftKey = usableDraftKey {
            draftStore.removeDraft(for: draftKey)
        }
    }

    /// Makes room for the partner's new drawing. Returns false when the canvas
    /// must stay as it is because the partner draws along on it.
    private func setAsideUnsentWork(if hasUnsentWork: Bool) -> Bool {
        guard hasUnsentWork else {
            return true
        }
        partnerSentWhileEditing = true
        if live?.partnerActivity == .drawing {
            return false
        }
        setAside(drawing)
        return true
    }

    /// Drawing together, the partner usually sends exactly what this canvas
    /// shows. That is not news, and nothing here is left unsent.
    private func canvasAlreadyShows(_ savedDrawing: PKDrawing) -> Bool {
        guard drawingSignature == savedDrawing.paeoniaContentSignature else {
            return false
        }
        partnerSentWhileEditing = false
        clearDraft()
        return true
    }

    /// The same strokes may have been saved again by either partner. Refresh
    /// any metadata that arrived with that save so the row names the actual
    /// latest author and time. A timestamp means this is complete metadata, so
    /// a missing author clears the old name instead of misattributing it.
    /// Without any metadata, keep the last values.
    private func refreshAttribution(from snapshot: WidgetCanvasSnapshot) {
        let normalizedAuthorName = snapshot.authorName?.trimmedNonEmpty
        if let createdAt = snapshot.createdAt {
            savedDrawingAuthorName = normalizedAuthorName
            savedDrawingCreatedAt = createdAt
        } else if let normalizedAuthorName {
            savedDrawingAuthorName = normalizedAuthorName
        }
    }

    /// Persists the current edit synchronously so an interactive swipe-dismiss,
    /// background transition, or process suspension cannot drop the latest
    /// PencilKit delegate update.
    func persistDraftIfNeeded() {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = nil
        persistDraftImmediatelyIfNeeded()
    }

    /// The draft key while it is still safe to use: nil without a couple, and
    /// nil after a privacy purge ran while this screen stayed open.
    private var usableDraftKey: WidgetDrawingDraftKey? {
        guard let draftKey,
              draftStore.purgeGeneration(for: draftKey.ownerUserID) == draftPurgeGeneration
        else {
            return nil
        }
        return draftKey
    }

    func scheduleDraftPersistence() {
        guard usableDraftKey != nil else {
            return
        }

        draftPersistenceTask?.cancel()
        draftPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.draftPersistenceDelay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            self.draftPersistenceTask = nil
            self.persistDraftInBackground()
        }
    }

    /// True when the canvas holds work that is not sent, so a draft is kept.
    private var shouldKeepDraft: Bool {
        hasUnsavedEdits && (!drawing.strokes.isEmpty || lastSavedDrawingSignature != nil)
    }

    /// Writes the draft now, on the main actor.
    private func persistDraftImmediatelyIfNeeded() {
        guard let draftKey = usableDraftKey else {
            return
        }

        draftOrder.performNow {
            if shouldKeepDraft {
                draftStore.setDraft(drawing.dataRepresentation(), for: draftKey)
                draftStore.setDraftBase((savedBaseline ?? PKDrawing()).paeoniaStrokeFingerprint, for: draftKey)
            } else {
                draftStore.removeDraft(for: draftKey)
            }
        }
    }

    /// Encodes and writes the draft off the main actor, because a large drawing
    /// takes long to encode. Only the copy of the drawing is made here.
    private func persistDraftInBackground() {
        guard let draftKey = usableDraftKey else {
            return
        }
        guard shouldKeepDraft else {
            persistDraftImmediatelyIfNeeded()
            return
        }
        let ticket = draftOrder.nextTicket()
        let snapshot = DraftSnapshot(drawing: drawing, baseline: savedBaseline ?? PKDrawing())
        let draftStore = draftStore
        let order = draftOrder
        let generation = draftStore.purgeGeneration(for: draftKey.ownerUserID)
        Task {
            await Self.writeDraft(snapshot, key: draftKey, ticket: ticket, store: draftStore, order: order)
            // A privacy purge can run while the write is going, even after this screen is gone.
            // The write may have recreated the draft, so it goes again.
            if draftStore.purgeGeneration(for: draftKey.ownerUserID) != generation {
                draftStore.removeDraft(for: draftKey)
            }
        }
    }

    /// The canvas and the drawing on the widgets, as they were when the save began.
    private struct DraftSnapshot: Sendable {
        let drawing: PKDrawing
        let baseline: PKDrawing
    }

    @concurrent
    private static func writeDraft(
        _ snapshot: DraftSnapshot,
        key: WidgetDrawingDraftKey,
        ticket: Int,
        store: any WidgetDrawingDraftStoring,
        order: DraftWriteOrder
    ) async {
        let data = snapshot.drawing.dataRepresentation()
        let base = snapshot.baseline.paeoniaStrokeFingerprint
        order.perform(ticket) {
            store.setDraft(data, base: base, for: key)
        }
    }

    func clearDraft() {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = nil
        guard let draftKey = usableDraftKey else {
            return
        }
        draftOrder.performNow {
            draftStore.removeDraft(for: draftKey)
        }
    }

    // MARK: - Set-aside drawing

    private var setAsideKey: WidgetDrawingDraftKey? {
        usableDraftKey.map {
            WidgetDrawingDraftKey(ownerUserID: $0.ownerUserID, coupleID: $0.coupleID, slot: .setAside)
        }
    }

    /// The widgets show a different drawing than when the draft was made. A
    /// draft with no recorded base (the best-effort write failed) counts as
    /// changed. It goes aside, where the person can bring it back.
    private func widgetsChanged(since draftKey: WidgetDrawingDraftKey) -> Bool {
        let current = savedBaseline ?? PKDrawing()
        return draftStore.draftBase(for: draftKey) != current.paeoniaStrokeFingerprint
    }

    /// Keeps `drawing` for later. An earlier set-aside drawing is kept too, so
    /// nothing is lost when this happens twice.
    func setAside(_ drawing: PKDrawing) {
        guard !drawing.strokes.isEmpty else {
            return
        }
        let combined = setAsideDrawing.map {
            WidgetLiveStrokeSync.apply(upserts: drawing.strokes, removals: [], to: $0)
        } ?? drawing
        setAsideDrawing = combined
        if let setAsideKey {
            draftStore.setDraft(combined.dataRepresentation(), for: setAsideKey)
        }
    }

    /// Puts the set-aside drawing back on an empty canvas, alone, because two
    /// drawings on top of each other are a mess. Unsent work on the canvas
    /// takes its place as the set-aside drawing, so the two can be swapped
    /// back and nothing is lost.
    func restoreSetAsideDrawing() {
        guard let aside = setAsideDrawing else {
            return
        }
        let current = drawing
        let currentHasUnsentWork = hasUnsavedEdits && !current.strokes.isEmpty
        discardSetAsideDrawing()
        if currentHasUnsentWork {
            setAside(current)
        }
        live?.localDrawingDidChange(aside, side: currentCanvasSide())
        replaceDrawing(with: aside)
        partnerSentWhileEditing = false
        persistDraftIfNeeded()
    }

    func discardSetAsideDrawing() {
        setAsideDrawing = nil
        if let setAsideKey {
            draftStore.removeDraft(for: setAsideKey)
        }
    }
}
