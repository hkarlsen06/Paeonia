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
    /// The tool before the current one, for Apple Pencil's "last used" double tap.
    @ObservationIgnored private var previousTool: WidgetDrawingTool?
    /// The pen or pencil to go back to after the eraser.
    @ObservationIgnored private var lastDrawingTool: WidgetDrawingTool = .pen
    private var selectedUIColor: UIColor = .paeoniaWidgetDrawing
    private var history = DrawingEditHistory()
    var canUndoDrawing: Bool { history.canUndo }
    var canRedoDrawing: Bool { history.canRedo }
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
    /// Unsent work that a newer drawing on the widgets replaced on the canvas.
    /// The person can bring it back or delete it.
    private(set) var setAsideDrawing: PKDrawing?
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
    /// Drawing together while the partner has the canvas open. Nil without a couple.
    let live: WidgetLiveDrawing?
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
    /// The `drawingRevision` the canvas view shows. Until it catches up with a
    /// replace, the canvas holds an older drawing than `drawing`.
    @ObservationIgnored private var canvasDrawingRevision: Int?
    @ObservationIgnored private var canvasRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var reloadAfterStroke = false

    init(
        ownerUserID: UUID? = nil,
        coupleID: UUID? = nil,
        authorName: String? = nil,
        service: any WidgetCanvasManaging = WidgetCanvasService.shared,
        uploader: any WidgetCanvasUploading = WidgetCanvasUploadServiceFactory.makeDefault(),
        draftStore: (any WidgetDrawingDraftStoring)? = nil,
        live: WidgetLiveDrawing? = nil
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
        self.live = live
        live?.applyRemoteDrawing = { [weak self] drawing in
            self?.applyPartnerLiveDrawing(drawing)
        }
        live?.currentDrawing = { [weak self] in
            self?.latestDrawing() ?? PKDrawing()
        }
        live?.setAsideDrawing = { [weak self] drawing in
            self?.setAside(drawing)
        }
        live?.savedStrokeKeys = { [weak self] in
            Set(self?.savedBaseline?.strokes.map(WidgetLiveStrokeSync.key(for:)) ?? [])
        }
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

    /// The canvas was changed on top of the drawing on the widgets, and can go
    /// back to it.
    var canRevertToSavedDrawing: Bool {
        !isPublishing && savedBaseline != nil && hasUnsavedEdits
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

        previousTool = selectedTool
        if !selectedTool.isEraser {
            lastDrawingTool = selectedTool
        }
        // The width re-derives from the same fraction against the new tool's
        // range, so the slider keeps its relative position across tools.
        selectedTool = tool
        toolConfigurationRevision += 1
    }

    /// Apple Pencil double tap, following the choice in Settings > Apple
    /// Pencil. The canvas has no palette to open, so the other choices switch
    /// between the drawing tool and the eraser, which is the default.
    func handlePencilDoubleTap(_ action: PencilPreferredAction) {
        if action == .ignore {
            return
        }
        if action == .switchPrevious, let previousTool {
            selectTool(previousTool)
            return
        }
        selectTool(selectedTool.isEraser ? lastDrawingTool : .eraser)
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
        live?.attach(to: canvasView)
    }

    /// A stroke or an erase on the canvas.
    func updateDrawing(_ drawing: PKDrawing) {
        history.record(from: self.drawing, to: drawing)
        self.drawing = drawing
        live?.localDrawingDidChange(drawing, side: currentCanvasSide())
        scheduleDraftPersistence()
    }

    /// The canvas reports when a finger or pencil touches down and lifts, so a
    /// partner's drawing never replaces the canvas in the middle of a stroke.
    func setDrawingStrokeInProgress(_ inProgress: Bool) {
        isDrawingStroke = inProgress
        if !inProgress {
            scheduleCanvasRefreshes()
        }
        guard !inProgress, reloadAfterStroke else {
            return
        }
        reloadAfterStroke = false
        Task { await reloadSavedDrawingFromSyncIfSafe() }
    }

    func canvasDidApplyDrawing(revision: Int) {
        canvasDrawingRevision = revision
    }

    /// The pixel eraser can finish changing the drawing after the last
    /// `canvasViewDrawingDidChange`. Without this, the draft, Send, and the
    /// partner would get the erase only with the next change.
    func refreshDrawingFromCanvas() {
        guard let canvasView, !isDrawingStroke, canvasDrawingRevision == drawingRevision else {
            return
        }
        let canvasDrawing = canvasView.drawing
        guard canvasDrawing != drawing else {
            return
        }
        updateDrawing(canvasDrawing)
    }

    /// The drawing as it is right now, including a late eraser change.
    func latestDrawing() -> PKDrawing {
        refreshDrawingFromCanvas()
        return drawing
    }

    /// Rendering callbacks usually catch the late eraser change. These reads
    /// make sure of it.
    private func scheduleCanvasRefreshes() {
        canvasRefreshTask?.cancel()
        canvasRefreshTask = Task { @MainActor [weak self] in
            for delay in [Duration.milliseconds(100), .milliseconds(500)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else {
                    return
                }
                self?.refreshDrawingFromCanvas()
            }
        }
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
        setAsideDrawing = setAsideKey
            .flatMap { draftStore.draft(for: $0) }
            .flatMap { try? PKDrawing(data: $0) }

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
        let editedMeanwhile = drawing.paeoniaContentSignature != signatureBeforeLoad
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
        guard drawing.paeoniaContentSignature == savedDrawing.paeoniaContentSignature else {
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
        // The canvas can change size while saving: on iPad the rows around it
        // change height. The baseline must be in the canvas's current size, or
        // the sent drawing reads as "not sent yet".
        adoptPublishedDrawing(sentDrawing.scaled(fromSide: canvasSide, toSide: currentCanvasSide()), savedAt: savedAt)

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
        applyEdit(PKDrawing())
        partnerSentWhileEditing = false
        persistDraftIfNeeded()
    }

    /// Puts the drawing on the widgets back on the canvas, as an edit that undo
    /// takes back.
    func revertToSavedDrawing() {
        guard canRevertToSavedDrawing, let savedBaseline else {
            return
        }
        applyEdit(savedBaseline)
        partnerSentWhileEditing = false
        persistDraftIfNeeded()
    }

    /// The paint bucket was tapped at `point`, in canvas points.
    func fill(at point: CGPoint) {
        guard let stroke = DrawingFloodFill.fillStroke(
            in: latestDrawing(),
            side: currentCanvasSide(),
            at: point,
            color: selectedUIColor
        ) else {
            return
        }
        applyEdit(PKDrawing(strokes: drawing.strokes + [stroke]))
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
            draftStore.setDraftBase((savedBaseline ?? PKDrawing()).paeoniaStrokeFingerprint, for: draftKey)
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
    private func setAside(_ drawing: PKDrawing) {
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
        history.scale(fromSide: drawingCanvasSide, toSide: laidOutCanvasSide)
        self.drawingCanvasSide = laidOutCanvasSide
        let fitted = !hadUnsavedEdits ? savedBaseline ?? scaledDrawing : scaledDrawing
        showOnCanvas(fitted)
        live?.drawingReplacedFromCode(fitted)
    }

    private func setBaseline(_ baseline: PKDrawing, authorName: String?, createdAt: Date?) {
        savedBaseline = baseline
        lastSavedDrawingSignature = baseline.paeoniaContentSignature
        savedDrawingAuthorName = authorName
        savedDrawingCreatedAt = createdAt
    }

    /// Replaces the canvas content from code (not from a stroke). Undo starts
    /// over, because its steps were made on the drawing that is gone.
    private func replaceDrawing(with newDrawing: PKDrawing) {
        history.removeAll()
        showOnCanvas(newDrawing)
        live?.drawingReplacedFromCode(newDrawing)
    }

    /// A change the person made with a button or a tap, not a stroke.
    private func applyEdit(_ newDrawing: PKDrawing) {
        history.record(from: drawing, to: newDrawing)
        showEdit(newDrawing)
    }

    private func showEdit(_ newDrawing: PKDrawing) {
        showOnCanvas(newDrawing)
        live?.localDrawingDidChange(newDrawing, side: currentCanvasSide())
        scheduleDraftPersistence()
    }

    private func showOnCanvas(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        drawingRevision += 1
    }

    // MARK: - Drawing together

    /// Connects once the saved drawing or draft is on the canvas, so the
    /// partner's strokes never land on a canvas that is still loading.
    func startLive() {
        guard hasLoadedSavedDrawing else {
            return
        }
        live?.start(drawing: drawing)
    }

    func stopLive() {
        live?.stop()
    }

    /// The partner's strokes arrived. They become part of this canvas, like
    /// strokes drawn here, so the draft keeps them and Send sends them. Undo
    /// keeps working: it only takes back this person's own steps.
    private func applyPartnerLiveDrawing(_ merged: PKDrawing) {
        showOnCanvas(merged)
        live?.drawingReplacedFromCode(merged)
        scheduleDraftPersistence()
    }

    // MARK: - Undo

    func undoDrawing() {
        if let previous = history.undo(latestDrawing()) {
            showEdit(previous)
        }
    }

    func redoDrawing() {
        if let next = history.redo(latestDrawing()) {
            showEdit(next)
        }
    }
}
