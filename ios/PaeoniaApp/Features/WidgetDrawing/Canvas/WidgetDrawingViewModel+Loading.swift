import PencilKit
import UIKit

extension WidgetDrawingViewModel {
    /// Loads the drawing on the widgets into the canvas once, or an unsent draft
    /// if there is one. Never replaces strokes drawn while it loads.
    func loadSavedDrawingIfNeeded() async {
        guard !hasLoadedSavedDrawing else {
            return
        }
        hasLoadedSavedDrawing = true
        defer {
            hasFinishedLoading = true
            addWaitingStrokes()
        }
        refreshDraftSaveFailure()
        setAsideDrawing = setAsideKey
            .flatMap { draftStore.draft(for: $0) }
            .flatMap { try? PKDrawing(data: $0) }

        guard drawing.strokes.isEmpty else {
            return
        }
        let signatureBeforeLoad = drawingSignature

        let descriptionBeforeLoad = accessibilityText
        let snapshot = await service.loadSavedSnapshot()
        savedAccessibilityText = snapshot?.accessibilityText ?? ""
        if descriptionBeforeLoad.isEmpty, accessibilityText == descriptionBeforeLoad {
            accessibilityText = savedAccessibilityText
        }
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
        guard drawingSignature == signatureBeforeLoad, accessibilityText == savedAccessibilityText else {
            return
        }

        restoreDraftOrBaseline()
        drawingCanvasSide = targetSide
        fitDrawingToCanvas()
    }

    /// Strokes waiting for the canvas to load, in a square `side` points wide.
    struct StrokesToAdd {
        let drawing: PKDrawing
        let side: CGFloat
        let onAdded: @MainActor () -> Void
    }

    /// Puts strokes drawn on another screen on this canvas, scaled from a square
    /// `side` points wide to this one, on top of the draft or the saved drawing.
    /// They wait until the canvas has loaded, because a canvas that already has
    /// strokes skips its draft. Each stroke is its own undo step, like one drawn
    /// here. The draft is written at once, then `onAdded` runs, so the strokes are
    /// never in both places after a relaunch.
    func addStrokesOnceLoaded(_ drawing: PKDrawing, side: CGFloat, onAdded: @escaping @MainActor () -> Void) {
        strokesToAdd = StrokesToAdd(drawing: drawing, side: side, onAdded: onAdded)
        addWaitingStrokes()
    }

    private func addWaitingStrokes() {
        guard hasFinishedLoading, let strokesToAdd else {
            return
        }
        self.strokesToAdd = nil
        let scaled = strokesToAdd.drawing.scaled(fromSide: strokesToAdd.side, toSide: currentCanvasSide())
        for stroke in scaled.strokes {
            applyEdit(PKDrawing(strokes: drawing.strokes + [stroke]))
        }
        persistDraftImmediatelyIfNeeded()
        strokesToAdd.onAdded()
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
            accessibilityText = draftStore.description(for: draftKey) ?? ""
            setAside(draftDrawing)
            accessibilityText = savedAccessibilityText
            draftStore.removeDraft(for: draftKey)
            replaceDrawing(with: savedBaseline ?? PKDrawing())
            return
        }
        // A draft is from this phone, so it is already in the canvas's size.
        accessibilityText = draftStore.description(for: draftKey) ?? ""
        replaceDrawing(with: draftDrawing)
        if draftDrawing.paeoniaContentSignature == lastSavedDrawingSignature,
           accessibilityText == savedAccessibilityText {
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
        let descriptionBeforeLoad = accessibilityText
        let hadDescriptionEdits = accessibilityText != savedAccessibilityText

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
        let hasLocalDescriptionEdits = hadDescriptionEdits || accessibilityText != descriptionBeforeLoad
        setBaseline(savedDrawing, authorName: snapshot.authorName?.trimmedNonEmpty, createdAt: snapshot.createdAt)
        hasLoadedSavedDrawing = true
        savedAccessibilityText = snapshot.accessibilityText ?? ""
        if drawingSignature == savedDrawing.paeoniaContentSignature, !hasLocalDescriptionEdits {
            accessibilityText = savedAccessibilityText
        }

        guard !canvasAlreadyShows(savedDrawing) else {
            return
        }

        // Strokes drawn while the drawing loaded count as unsent changes too.
        let editedMeanwhile = drawingSignature != signatureBeforeLoad
        guard setAsideUnsentWork(if: hadUnsavedEdits || editedMeanwhile || hasLocalDescriptionEdits) else {
            return
        }
        accessibilityText = savedAccessibilityText
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
        if accessibilityText == savedAccessibilityText {
            clearDraft()
        } else {
            persistDraftImmediatelyIfNeeded()
        }
        return true
    }

    /// The same strokes may have been saved again by either partner. Refresh
    /// any metadata that arrived with that save so the row names the actual
    /// latest author and time. A timestamp means this is complete metadata, so
    /// a missing author clears the old name instead of misattributing it.
    /// Without any metadata, keep the last values.
    private func refreshAttribution(from snapshot: WidgetCanvasSnapshot) {
        let hadUnsentWork = hasUnsavedEdits
        savedAccessibilityText = snapshot.accessibilityText ?? ""
        if !hadUnsentWork { accessibilityText = savedAccessibilityText }
        let normalizedAuthorName = snapshot.authorName?.trimmedNonEmpty
        if let createdAt = snapshot.createdAt {
            savedDrawingAuthorName = normalizedAuthorName
            savedDrawingCreatedAt = createdAt
        } else if let normalizedAuthorName {
            savedDrawingAuthorName = normalizedAuthorName
        }
    }

    // MARK: - Set-aside drawing

    var setAsideKey: WidgetDrawingDraftKey? {
        usableDraftKey.map {
            WidgetDrawingDraftKey(ownerUserID: $0.ownerUserID, coupleID: $0.coupleID, slot: .setAside)
        }
    }

    /// The widgets show a different drawing than when the draft was made. A
    /// draft with no recorded base counts as changed. It goes aside, where the
    /// person can bring it back.
    private func widgetsChanged(since draftKey: WidgetDrawingDraftKey) -> Bool {
        let current = savedBaseline ?? PKDrawing()
        return draftStore.draftBase(for: draftKey) != current.paeoniaStrokeFingerprint
    }

    /// Keeps `drawing` for later. An earlier set-aside drawing is kept too, so
    /// nothing is lost when this happens twice.
    func setAside(_ drawing: PKDrawing) {
        guard !drawing.strokes.isEmpty || !accessibilityText.isEmpty else {
            return
        }
        let combined = setAsideDrawing.map {
            WidgetLiveStrokeSync.apply(upserts: drawing.strokes, removals: [], to: $0)
        } ?? drawing
        setAsideDrawing = combined
        if let setAsideKey {
            let previous = draftStore.description(for: setAsideKey) ?? ""
            let description = [previous, accessibilityText].filter { !$0.isEmpty }.joined(separator: "\n")
            saveDraft(combined.dataRepresentation(), base: "", description: description, key: setAsideKey)
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
        let asideDescription = setAsideKey.flatMap { draftStore.description(for: $0) } ?? ""
        let current = drawing
        let currentHasUnsentWork = hasUnsavedEdits
            && (!current.strokes.isEmpty || accessibilityText != savedAccessibilityText)
        discardSetAsideDrawing()
        if currentHasUnsentWork {
            setAside(current)
        }
        live?.localDrawingDidChange(aside, side: currentCanvasSide())
        accessibilityText = asideDescription
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
