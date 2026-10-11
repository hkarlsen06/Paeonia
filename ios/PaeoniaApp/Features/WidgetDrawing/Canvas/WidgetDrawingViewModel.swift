import Observation
import PencilKit
import SwiftUI
import UIKit

/// A send that did not go through, so the view can pick the banner copy. A
/// fresh id each time makes `onChange` fire on repeated failures.
struct WidgetDrawingSaveFailure: Equatable, Identifiable {
    enum Reason: Equatable {
        /// Saving on this phone failed. The drawing stays on the canvas.
        case couldNotSave
        /// The drawing has more lines than the server accepts.
        case tooBig
    }

    let id = UUID()
    var reason: Reason = .couldNotSave
}

@MainActor
@Observable
final class WidgetDrawingViewModel {
    /// Where the latest send stands, as the person sees it.
    enum Delivery: Equatable {
        case idle
        /// Saving here and sending to the partner.
        case sending
        /// The partner has it. Shown briefly, then back to idle.
        case sent
        /// Saved on this phone. It goes out when the phone is online again.
        case waiting
    }

    /// Used when the canvas has not laid out yet (for example, during tests).
    nonisolated static let fallbackCanvasSide: CGFloat = 320
    private static let sentConfirmationDuration: Duration = .seconds(1.8)
    private static let draftPersistenceDelay: Duration = .milliseconds(250)

    let colorChoices = WidgetDrawingColorChoice.palette

    /// The drawing on the canvas. The canvas binding writes every stroke here.
    var drawing = PKDrawing()
    /// Bumped whenever the view model replaces the drawing itself (load, a
    /// partner's drawing, clear, resize). The canvas view pushes the drawing
    /// into PencilKit only when this changes, instead of comparing serialized
    /// bytes on every SwiftUI update.
    private(set) var drawingRevision = 0
    var selectedTool: WidgetDrawingTool = .pen
    var selectedColor: Color = .paeoniaWidgetDrawing
    private(set) var selectedCGColor: CGColor = UIColor.paeoniaWidgetDrawing.cgColor
    private var selectedUIColor: UIColor = .paeoniaWidgetDrawing
    private(set) var canUndoDrawing = false
    private(set) var canRedoDrawing = false
    private(set) var toolConfigurationRevision = 0
    private(set) var selectedColorChoiceID: String? = "blush"
    @ObservationIgnored private weak var canvasView: PKCanvasView?

    /// Slider position in `0...1`. The actual PencilKit width is derived per tool
    /// so the slider always spans the selected tool's full width range.
    private(set) var toolWidthFraction: CGFloat = 0.4

    var toolWidth: CGFloat {
        selectedTool.width(forFraction: toolWidthFraction)
    }

    private(set) var delivery: Delivery = .idle
    /// True while the drawing is being saved on this phone. Sending another
    /// drawing waits for this, but not for the upload to the partner.
    private(set) var isPublishing = false
    private(set) var saveFailure: WidgetDrawingSaveFailure?
    /// The partner sent a drawing while this canvas had changes that were not
    /// sent. The canvas keeps the changes; the screen says what sending does.
    private(set) var partnerSentWhileEditing = false
    /// Who made the drawing that is on the widgets now, and when. Both nil
    /// until something has been saved or loaded.
    private(set) var savedDrawingAuthorName: String?
    private(set) var savedDrawingCreatedAt: Date?
    /// Signature of the drawing on the widgets, in the canvas's coordinates.
    /// Keeps Send disabled until the canvas really differs from it.
    private var lastSavedDrawingSignature: Int?

    var isSaving: Bool { delivery == .sending }
    var recentlySaved: Bool { delivery == .sent }

    @ObservationIgnored private let service: any WidgetCanvasManaging
    @ObservationIgnored private let uploader: any WidgetCanvasUploading
    /// Drafts are kept per person and relationship. Without both IDs the screen
    /// keeps no draft at all, so a draft can never reach another couple.
    @ObservationIgnored private let draftKey: WidgetDrawingDraftKey?
    @ObservationIgnored private let draftStore: any WidgetDrawingDraftStoring
    /// The store's purge count when this screen opened. A purge while the screen
    /// stays open (for example an unpair) must not get its draft written back.
    @ObservationIgnored private let draftPurgeGeneration: Int
    @ObservationIgnored private let authorName: String?
    @ObservationIgnored private var hasLoadedSavedDrawing = false
    @ObservationIgnored private var sentConfirmationTask: Task<Void, Never>?
    @ObservationIgnored private var draftPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private var sendGeneration = 0
    /// The drawing on the widgets, kept in the canvas's coordinates so its
    /// signature can be recomputed after a resize.
    @ObservationIgnored private var savedBaseline: PKDrawing?
    /// The side of the square that `drawing` and `savedBaseline` are in.
    @ObservationIgnored private var drawingCanvasSide: CGFloat?
    /// The side of the square the canvas has on screen right now.
    @ObservationIgnored private var laidOutCanvasSide: CGFloat?
    @ObservationIgnored private var isDrawingStroke = false
    @ObservationIgnored private var reloadAfterStroke = false

    init(
        ownerUserID: UUID? = nil,
        coupleID: UUID? = nil,
        authorName: String? = nil,
        service: any WidgetCanvasManaging = WidgetCanvasService.shared,
        uploader: any WidgetCanvasUploading = WidgetCanvasUploadServiceFactory.makeDefault(),
        draftStore: (any WidgetDrawingDraftStoring)? = nil
    ) {
        let draftStore = draftStore ?? FileWidgetDrawingDraftStore.shared
        if let ownerUserID, let coupleID {
            draftKey = WidgetDrawingDraftKey(ownerUserID: ownerUserID, coupleID: coupleID)
        } else {
            draftKey = nil
        }
        draftPurgeGeneration = ownerUserID.map { draftStore.purgeGeneration(for: $0) } ?? 0
        self.authorName = authorName
        self.service = service
        self.uploader = uploader
        self.draftStore = draftStore
    }

    var isColorSelectionEnabled: Bool {
        !selectedTool.isEraser
    }

    /// True when the canvas differs from the drawing on the widgets. Returns
    /// false again once edits are undone back to that drawing.
    var hasUnsavedEdits: Bool {
        drawing.paeoniaContentSignature != lastSavedDrawingSignature
    }

    var canSave: Bool {
        !isPublishing && !drawing.strokes.isEmpty && hasUnsavedEdits
    }

    /// True once there is a drawing on the widgets to describe. Independent of
    /// the canvas being empty: clearing is only an unsent edit, so the row keeps
    /// describing what the widgets still show.
    var isShowingSavedAttribution: Bool {
        lastSavedDrawingSignature != nil
            && (savedDrawingAuthorName != nil || savedDrawingCreatedAt != nil)
    }

    var canClear: Bool {
        !isPublishing && !drawing.strokes.isEmpty
    }

    var pencilKitTool: any PKTool {
        selectedTool.pencilKitTool(
            color: selectedUIColor,
            width: toolWidth
        )
    }

    // MARK: - Tools

    func selectTool(_ tool: WidgetDrawingTool) {
        guard selectedTool != tool else {
            return
        }

        // The width re-derives from the same fraction against the new tool's
        // range, so the slider keeps its relative position across tools.
        selectedTool = tool
        toolConfigurationRevision += 1
    }

    func selectColorChoice(_ choice: WidgetDrawingColorChoice) {
        guard isColorSelectionEnabled else {
            return
        }

        selectedColor = choice.color
        selectedCGColor = choice.uiColor.cgColor
        selectedUIColor = choice.uiColor
        selectedColorChoiceID = choice.id
        toolConfigurationRevision += 1
    }

    func selectCustomColor(_ color: CGColor) {
        guard isColorSelectionEnabled else {
            return
        }

        let uiColor = UIColor.paeoniaDrawingColor(from: color)

        selectedColor = Color(uiColor: uiColor)
        selectedCGColor = uiColor.cgColor
        selectedUIColor = uiColor
        selectedColorChoiceID = nil
        toolConfigurationRevision += 1
    }

    func updateToolWidthFraction(_ fraction: CGFloat) {
        let clampedFraction = min(max(0, fraction), 1)

        guard toolWidthFraction != clampedFraction else {
            return
        }

        toolWidthFraction = clampedFraction
        toolConfigurationRevision += 1
    }

    // MARK: - Canvas

    func bindCanvasView(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
        // This is called from the canvas representable's `makeUIView`, which runs
        // inside SwiftUI's view update. Defer the observed undo/redo refresh to
        // the next main-actor turn so we don't mutate published state mid-update.
        Task { @MainActor in
            self.refreshUndoRedoAvailability()
        }
    }

    func updateDrawing(_ drawing: PKDrawing, undoManager: UndoManager?) {
        self.drawing = drawing
        scheduleDraftPersistence()
        refreshUndoRedoAvailability(using: undoManager)

        Task { @MainActor in
            self.refreshUndoRedoAvailability()
        }
    }

    /// The canvas reports when a finger or pencil touches down and lifts, so a
    /// partner's drawing never replaces the canvas in the middle of a stroke.
    func setDrawingStrokeInProgress(_ inProgress: Bool) {
        isDrawingStroke = inProgress
        guard !inProgress, reloadAfterStroke else {
            return
        }
        reloadAfterStroke = false
        Task { await reloadSavedDrawingFromSyncIfSafe() }
    }

    /// The on-screen side of the square canvas. A drawing made on a screen of a
    /// different size is scaled to fit, so nothing is cut off.
    func canvasDidLayout(side: CGFloat) {
        guard side > 0 else {
            return
        }
        laidOutCanvasSide = side
        fitDrawingToCanvas()
    }

    // MARK: - Loading

    /// Loads the drawing on the widgets into the canvas once, or an unsent draft
    /// if there is one. Never replaces strokes drawn while it loads.
    func loadSavedDrawingIfNeeded() async {
        guard !hasLoadedSavedDrawing else {
            return
        }
        hasLoadedSavedDrawing = true

        guard drawing.strokes.isEmpty else {
            return
        }
        let signatureBeforeLoad = drawing.paeoniaContentSignature

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
        guard drawing.paeoniaContentSignature == signatureBeforeLoad else {
            refreshUndoRedoAvailability()
            return
        }

        restoreDraftOrBaseline()
        drawingCanvasSide = targetSide
        fitDrawingToCanvas()
        refreshUndoRedoAvailability()
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
        let signatureBeforeLoad = drawing.paeoniaContentSignature
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

        // A different drawing must never inherit the previous one's attribution.
        setBaseline(savedDrawing, authorName: snapshot.authorName?.trimmedNonEmpty, createdAt: snapshot.createdAt)
        hasLoadedSavedDrawing = true

        // Strokes drawn while the drawing loaded count as unsent changes too.
        let editedMeanwhile = drawing.paeoniaContentSignature != signatureBeforeLoad
        if hadUnsavedEdits || editedMeanwhile || isDrawingStroke {
            partnerSentWhileEditing = true
            return
        }

        replaceDrawing(with: savedDrawing)
        drawingCanvasSide = targetSide
        if let draftKey = usableDraftKey {
            draftStore.removeDraft(for: draftKey)
        }
        refreshUndoRedoAvailability()
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

    // MARK: - Sending

    /// Saves the drawing on this phone, shows it on both widgets, and sends it
    /// to the partner.
    func save() async {
        guard canSave else {
            return
        }

        let sentDrawing = drawing
        guard let uploadPayload = makeUploadPayload(for: sentDrawing) else {
            saveFailure = WidgetDrawingSaveFailure(reason: .tooBig)
            return
        }

        sendGeneration += 1
        let generation = sendGeneration
        sentConfirmationTask?.cancel()
        isPublishing = true
        delivery = .sending
        saveFailure = nil
        let savedAt = Date()
        let canvasSide = uploadPayload.canvasSide

        // Marked before the drawing is shown locally, so a sync running right now
        // cannot pull an older drawing over this one.
        let previousPending = await uploader.markPending(uploadPayload)
        do {
            try await service.saveDrawing(
                uploadPayload.drawingData,
                canvasSize: CGSize(width: canvasSide, height: canvasSide),
                authorName: authorName,
                createdAt: savedAt
            )
        } catch {
            await uploader.restorePending(previousPending, replacing: uploadPayload)
            isPublishing = false
            delivery = .idle
            saveFailure = WidgetDrawingSaveFailure()
            return
        }

        isPublishing = false
        adoptPublishedDrawing(sentDrawing, savedAt: savedAt)

        let outcome = await uploader.send(uploadPayload)
        // A newer send owns the status now.
        if generation == sendGeneration {
            applyDelivery(outcome)
        }
    }

    private func applyDelivery(_ outcome: WidgetDrawingDelivery) {
        switch outcome {
        case .delivered:
            showSentConfirmation()
        case .waiting:
            delivery = .waiting
        case .replaced:
            delivery = .idle
        }
    }

    /// The upload payload for `drawing`, or nil when the drawing is past the
    /// server's limits. PencilKit-derived metadata is read here, on the main
    /// actor, so the upload uses values that match the bytes being saved.
    private func makeUploadPayload(for drawing: PKDrawing) -> WidgetDrawingUploadPayload? {
        let drawingData = drawing.dataRepresentation()
        let strokeCount = drawing.strokes.count
        let pointCount = drawing.paeoniaPointCount
        guard WidgetDrawingLimits.allows(
            byteCount: drawingData.count,
            strokeCount: strokeCount,
            pointCount: pointCount
        ) else {
            return nil
        }
        return WidgetDrawingUploadPayload(
            drawingData: drawingData,
            canvasSide: currentCanvasSide(),
            strokeCount: strokeCount,
            pointCount: pointCount,
            bounds: drawing.bounds
        )
    }

    /// The canvas stays usable while the save runs. The baseline is the exact
    /// drawing that was published, not strokes added meanwhile.
    private func adoptPublishedDrawing(_ sentDrawing: PKDrawing, savedAt: Date) {
        let sentSignature = sentDrawing.paeoniaContentSignature
        savedBaseline = sentDrawing
        lastSavedDrawingSignature = sentSignature
        savedDrawingAuthorName = authorName?.trimmedNonEmpty
        savedDrawingCreatedAt = savedAt
        partnerSentWhileEditing = false
        if drawing.paeoniaContentSignature == sentSignature {
            clearDraft()
        } else {
            persistDraftIfNeeded()
        }
    }

    /// A send that was waiting for the network went out in the background.
    func refreshDelivery() async {
        guard delivery == .waiting else {
            return
        }
        if await !uploader.hasPendingUpload, delivery == .waiting {
            showSentConfirmation()
        }
    }

    private func showSentConfirmation() {
        delivery = .sent
        sentConfirmationTask?.cancel()
        sentConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.sentConfirmationDuration)
            guard !Task.isCancelled, let self, self.delivery == .sent else {
                return
            }
            self.delivery = .idle
        }
    }

    /// Empties the canvas as a local editing action. The widgets keep the last
    /// sent drawing until the next send.
    func clearCanvas() {
        replaceDrawing(with: PKDrawing())
        partnerSentWhileEditing = false
        persistDraftIfNeeded()
        refreshUndoRedoAvailability()
    }

    // MARK: - Drafts

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

    private func scheduleDraftPersistence() {
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
            self.persistDraftImmediatelyIfNeeded()
        }
    }

    private func persistDraftImmediatelyIfNeeded() {
        guard let draftKey = usableDraftKey else {
            return
        }

        if hasUnsavedEdits && (!drawing.strokes.isEmpty || lastSavedDrawingSignature != nil) {
            draftStore.setDraft(drawing.dataRepresentation(), for: draftKey)
        } else {
            draftStore.removeDraft(for: draftKey)
        }
    }

    private func clearDraft() {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = nil
        guard let draftKey = usableDraftKey else {
            return
        }
        draftStore.removeDraft(for: draftKey)
    }

    // MARK: - Canvas size

    private func currentCanvasSide() -> CGFloat {
        if let drawingCanvasSide {
            return drawingCanvasSide
        }
        return Self.canvasSide(for: canvasView?.bounds.size ?? .zero)
    }

    /// PencilKit, upload metadata, and raster rendering share one square source
    /// rect. The short edge is the only safe source dimension if UIKit reports a
    /// transient non-square bound during layout.
    nonisolated static func canvasSide(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else {
            return fallbackCanvasSide
        }
        return min(size.width, size.height)
    }

    /// Scales the canvas and its baseline together, so a resize is never
    /// mistaken for an edit.
    private func fitDrawingToCanvas() {
        guard let laidOutCanvasSide else {
            return
        }
        guard let drawingCanvasSide else {
            drawingCanvasSide = laidOutCanvasSide
            return
        }
        guard abs(drawingCanvasSide - laidOutCanvasSide) >= 0.5 else {
            return
        }
        let hadUnsavedEdits = hasUnsavedEdits
        if let savedBaseline {
            let scaledBaseline = savedBaseline.scaled(fromSide: drawingCanvasSide, toSide: laidOutCanvasSide)
            self.savedBaseline = scaledBaseline
            lastSavedDrawingSignature = scaledBaseline.paeoniaContentSignature
        }
        let scaledDrawing = drawing.scaled(fromSide: drawingCanvasSide, toSide: laidOutCanvasSide)
        self.drawingCanvasSide = laidOutCanvasSide
        if !hadUnsavedEdits, let savedBaseline {
            replaceDrawing(with: savedBaseline)
        } else {
            replaceDrawing(with: scaledDrawing)
        }
    }

    private func setBaseline(_ baseline: PKDrawing, authorName: String?, createdAt: Date?) {
        savedBaseline = baseline
        lastSavedDrawingSignature = baseline.paeoniaContentSignature
        savedDrawingAuthorName = authorName
        savedDrawingCreatedAt = createdAt
    }

    /// Replaces the canvas content from code (not from a stroke).
    private func replaceDrawing(with newDrawing: PKDrawing) {
        drawing = newDrawing
        drawingRevision += 1
    }

    // MARK: - Undo

    func undoDrawing() {
        guard let canvasView,
              let undoManager = canvasView.undoManager,
              undoManager.canUndo
        else {
            refreshUndoRedoAvailability()
            return
        }

        undoManager.undo()
        drawing = canvasView.drawing
        refreshUndoRedoAvailability(using: undoManager)
    }

    func redoDrawing() {
        guard let canvasView,
              let undoManager = canvasView.undoManager,
              undoManager.canRedo
        else {
            refreshUndoRedoAvailability()
            return
        }

        undoManager.redo()
        drawing = canvasView.drawing
        refreshUndoRedoAvailability(using: undoManager)
    }

    private func refreshUndoRedoAvailability() {
        refreshUndoRedoAvailability(using: canvasView?.undoManager)
    }

    private func refreshUndoRedoAvailability(using undoManager: UndoManager?) {
        canUndoDrawing = undoManager?.canUndo ?? false
        canRedoDrawing = undoManager?.canRedo ?? false
    }
}
