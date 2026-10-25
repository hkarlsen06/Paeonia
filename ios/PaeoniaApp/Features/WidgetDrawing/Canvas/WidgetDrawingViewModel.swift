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

    let colorChoices = WidgetDrawingColorChoice.palette

    /// The drawing on the canvas. The canvas binding writes every stroke here.
    var drawing = PKDrawing() {
        didSet { drawingSignature = drawing.paeoniaContentSignature }
    }
    /// `drawing.paeoniaContentSignature`, kept up to date when `drawing` is set.
    /// The signature reads every stroke, and the screen asks for it many times
    /// per update.
    @ObservationIgnored private(set) var drawingSignature = PKDrawing().paeoniaContentSignature
    /// Bumped whenever the view model replaces the drawing itself (load, a
    /// partner's drawing, clear, resize). The canvas view pushes the drawing
    /// into PencilKit only when this changes, instead of comparing serialized
    /// bytes on every SwiftUI update.
    var drawingRevision = 0
    var selectedTool: WidgetDrawingTool = .pen
    private(set) var selectedLineStyle: InkLineStyle = .solid
    var selectedColor: Color = .paeoniaWidgetDrawing
    private(set) var selectedCGColor: CGColor = UIColor.paeoniaWidgetDrawing.cgColor
    /// The tool before the current one, for Apple Pencil's "last used" double tap.
    @ObservationIgnored private var previousTool: WidgetDrawingTool?
    /// The pen or pencil to go back to after the eraser.
    @ObservationIgnored private var lastDrawingTool: WidgetDrawingTool = .pen
    private var selectedUIColor: UIColor = .paeoniaWidgetDrawing
    var history = DrawingEditHistory()
    var canUndoDrawing: Bool { history.canUndo }
    var canRedoDrawing: Bool { history.canRedo }
    private(set) var selectedColorChoiceID: String? = "blush"
    @ObservationIgnored weak var canvasView: PKCanvasView?

    /// Slider position in `0...1`. The actual PencilKit width is derived per tool
    /// so the slider always spans the selected tool's full width range.
    private(set) var toolWidthFraction: CGFloat = 0.4
    private(set) var isAdjustingToolWidth = false

    var toolWidth: CGFloat {
        selectedTool.width(forFraction: toolWidthFraction)
    }

    var delivery: Delivery = .idle
    /// True while the drawing is being saved on this phone. Sending another
    /// drawing waits for this, but not for the upload to the partner.
    private(set) var isPublishing = false
    private(set) var saveFailure: WidgetDrawingSaveFailure?
    /// The partner sent a drawing while this canvas had changes that were not
    /// sent. The canvas keeps the changes; the screen says what sending does.
    var partnerSentWhileEditing = false
    /// The user sent a drawing since the app started. The notification ask
    /// waits for this.
    @ObservationIgnored private(set) var hasSentDrawing = false
    /// Unsent work that a newer drawing on the widgets replaced on the canvas.
    /// The person can bring it back or delete it.
    var setAsideDrawing: PKDrawing?
    /// Who made the drawing that is on the widgets now, and when. Both nil
    /// until something has been saved or loaded.
    var savedDrawingAuthorName: String?
    var savedDrawingCreatedAt: Date?
    /// Signature of the drawing on the widgets, in the canvas's coordinates.
    /// Keeps Send disabled until the canvas really differs from it.
    var lastSavedDrawingSignature: Int?

    var isSaving: Bool { delivery == .sending }
    var recentlySaved: Bool { delivery == .sent }

    @ObservationIgnored let service: any WidgetCanvasManaging
    @ObservationIgnored let uploader: any WidgetCanvasUploading
    /// Drafts are kept per person and relationship. Without both IDs the screen
    /// keeps no draft at all, so a draft can never reach another couple.
    @ObservationIgnored let draftKey: WidgetDrawingDraftKey?
    @ObservationIgnored let draftStore: any WidgetDrawingDraftStoring
    /// The store's purge count when this screen opened. A purge while the screen
    /// stays open (for example an unpair) must not get its draft written back.
    @ObservationIgnored let draftPurgeGeneration: Int
    @ObservationIgnored let authorName: String?
    /// Drawing together while the partner has the canvas open. Nil without a couple.
    let live: WidgetLiveDrawing?
    @ObservationIgnored var hasLoadedSavedDrawing = false
    @ObservationIgnored private var sentConfirmationTask: Task<Void, Never>?
    @ObservationIgnored var draftPersistenceTask: Task<Void, Never>?
    @ObservationIgnored let draftOrder = DraftWriteOrder()
    @ObservationIgnored private var sendGeneration = 0
    /// The drawing on the widgets, kept in the canvas's coordinates so its
    /// signature can be recomputed after a resize.
    @ObservationIgnored var savedBaseline: PKDrawing?
    /// The side of the square that `drawing` and `savedBaseline` are in.
    @ObservationIgnored var drawingCanvasSide: CGFloat?
    /// The side of the square the canvas has on screen right now.
    @ObservationIgnored var laidOutCanvasSide: CGFloat?
    @ObservationIgnored var isDrawingStroke = false
    /// The `drawingRevision` the canvas view shows. Until it catches up with a
    /// replace, the canvas holds an older drawing than `drawing`.
    @ObservationIgnored var canvasDrawingRevision: Int?
    @ObservationIgnored var canvasRefreshTask: Task<Void, Never>?
    @ObservationIgnored var reloadAfterStroke = false

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

    var isLineStyleSelectionEnabled: Bool {
        selectedTool.drawsLines
    }

    /// True when the canvas differs from the drawing on the widgets. Returns
    /// false again once edits are undone back to that drawing.
    var hasUnsavedEdits: Bool {
        drawingSignature != lastSavedDrawingSignature
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

    var canvasTool: CanvasTool {
        selectedTool.canvasTool(color: selectedUIColor, width: toolWidth, lineStyle: selectedLineStyle)
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
    }

    func updateToolWidthFraction(_ fraction: CGFloat) {
        let clampedFraction = min(max(0, fraction), 1)

        guard toolWidthFraction != clampedFraction else {
            return
        }

        toolWidthFraction = clampedFraction
    }

    func setAdjustingToolWidth(_ isAdjusting: Bool) {
        isAdjustingToolWidth = isAdjusting
    }

    func selectLineStyle(_ style: InkLineStyle) {
        guard isLineStyleSelectionEnabled else {
            return
        }
        selectedLineStyle = style
    }
}

// MARK: - Sending

extension WidgetDrawingViewModel {
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
        hasSentDrawing = true
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
        if drawingSignature == sentSignature {
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
}
