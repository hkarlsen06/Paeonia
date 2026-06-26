import Observation
import PencilKit
import SwiftUI
import UIKit

struct WidgetDrawingColorChoice: Identifiable, Equatable {
    let id: String
    let color: Color
    let uiColor: UIColor
    let accessibilityLabel: LocalizedStringResource

    static func == (lhs: WidgetDrawingColorChoice, rhs: WidgetDrawingColorChoice) -> Bool {
        lhs.id == rhs.id
    }
}

extension WidgetDrawingColorChoice {
    /// The fixed ink palette offered by the drawing tools.
    static let palette: [WidgetDrawingColorChoice] = [
        WidgetDrawingColorChoice(
            id: "blush",
            color: .paeoniaWidgetDrawing,
            uiColor: .paeoniaWidgetDrawing,
            accessibilityLabel: .widgetDrawingColorBlush
        ),
        WidgetDrawingColorChoice(
            id: "petal",
            color: .paeoniaAccentPrimary,
            uiColor: .paeoniaAccentPrimary,
            accessibilityLabel: .widgetDrawingColorPetal
        ),
        WidgetDrawingColorChoice(
            id: "pink",
            color: .paeoniaAccentSecondary,
            uiColor: .paeoniaAccentSecondary,
            accessibilityLabel: .widgetDrawingColorPink
        ),
        WidgetDrawingColorChoice(
            id: "warm",
            color: .paeoniaPartnerTwo,
            uiColor: .paeoniaPartnerTwo,
            accessibilityLabel: .widgetDrawingColorWarm
        ),
        WidgetDrawingColorChoice(
            id: "green",
            color: .paeoniaSuccess,
            uiColor: .paeoniaSuccess,
            accessibilityLabel: .widgetDrawingColorGreen
        ),
        WidgetDrawingColorChoice(
            id: "gold",
            color: .paeoniaInkGold,
            uiColor: .paeoniaInkGold,
            accessibilityLabel: .widgetDrawingColorGold
        ),
        WidgetDrawingColorChoice(
            id: "blue",
            color: .paeoniaInkBlue,
            uiColor: .paeoniaInkBlue,
            accessibilityLabel: .widgetDrawingColorBlue
        ),
        WidgetDrawingColorChoice(
            id: "lavender",
            color: .paeoniaInkLavender,
            uiColor: .paeoniaInkLavender,
            accessibilityLabel: .widgetDrawingColorLavender
        ),
    ]
}

enum WidgetDrawingTool: CaseIterable, Equatable, Identifiable {
    case pen
    case pencil
    case eraser

    var id: Self { self }

    var isEraser: Bool {
        self == .eraser
    }

    var systemImageName: String {
        switch self {
        case .pen:
            "pencil.tip"
        case .pencil:
            "pencil"
        case .eraser:
            "eraser.fill"
        }
    }

    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .pen:
            .widgetDrawingToolPen
        case .pencil:
            .widgetDrawingToolPencil
        case .eraser:
            .widgetDrawingToolEraser
        }
    }

    func pencilKitTool(color: UIColor, width: CGFloat) -> any PKTool {
        let clampedWidth = clampedWidth(width)

        return switch self {
        case .pen:
            PKInkingTool(.pen, color: color, width: clampedWidth)
        case .pencil:
            PKInkingTool(.pencil, color: color, width: clampedWidth)
        case .eraser:
            PKEraserTool(.bitmap, width: clampedWidth)
        }
    }

    func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(validWidthRange.lowerBound, width), validWidthRange.upperBound)
    }

    /// Maps a `0...1` slider position onto this tool's own valid width range, so
    /// the full slider travel always spans the tool's smallest-to-largest width.
    func width(forFraction fraction: CGFloat) -> CGFloat {
        let clampedFraction = min(max(0, fraction), 1)
        let range = validWidthRange
        return range.lowerBound + (range.upperBound - range.lowerBound) * clampedFraction
    }

    /// Each tool reports its own valid width range; the eraser's differs from the
    /// inking tools, which is why a single fixed slider range cannot be shared.
    var validWidthRange: ClosedRange<CGFloat> {
        switch self {
        case .pen:
            PKInkingTool.InkType.pen.validWidthRange
        case .pencil:
            PKInkingTool.InkType.pencil.validWidthRange
        case .eraser:
            PKEraserTool.EraserType.bitmap.validWidthRange
        }
    }
}

/// Identifies a save failure so the view can route it to the shared banner. A
/// fresh value each time guarantees `onChange` fires on repeated failures.
struct WidgetDrawingSaveFailure: Equatable, Identifiable {
    let id = UUID()
}

@MainActor
@Observable
final class WidgetDrawingViewModel {
    /// Used to render previews when the canvas has not laid out yet (for
    /// example, during tests). Production saves read the live canvas bounds.
    nonisolated static let fallbackCanvasSide: CGFloat = 320
    private static let savedConfirmationDuration: Duration = .seconds(1.8)

    let colorChoices = WidgetDrawingColorChoice.palette

    var drawing = PKDrawing()
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

    private(set) var isSaving = false
    private(set) var recentlySaved = false
    private(set) var saveFailure: WidgetDrawingSaveFailure?
    /// Attribution of the drawing currently on the canvas (the last saved or
    /// loaded one). Both nil until something has been saved or loaded.
    private(set) var savedDrawingAuthorName: String?
    private(set) var savedDrawingCreatedAt: Date?
    @ObservationIgnored private let service: any WidgetCanvasManaging
    @ObservationIgnored private let uploader: any WidgetCanvasUploading
    @ObservationIgnored private let authorName: String?
    @ObservationIgnored private var hasLoadedSavedDrawing = false
    @ObservationIgnored private var savedConfirmationTask: Task<Void, Never>?
    /// Content signature of the drawing as it was last saved (or loaded). Used
    /// to keep Save disabled, and the attribution un-struck, until the canvas
    /// actually differs from what's stored. Derived from the strokes' geometry
    /// and ink rather than `PKDrawing.dataRepresentation()`, because the byte
    /// representation also encodes session state and is re-encoded by PencilKit
    /// after every commit, so identical content would otherwise stop comparing
    /// equal right after a save (re-enabling Save and striking the attribution
    /// with no real edit).
    @ObservationIgnored private var lastSavedDrawingSignature: Int?

    init(
        authorName: String? = nil,
        service: any WidgetCanvasManaging = WidgetCanvasService.shared,
        uploader: any WidgetCanvasUploading = WidgetCanvasUploadServiceFactory.makeDefault()
    ) {
        self.authorName = authorName
        self.service = service
        self.uploader = uploader
    }

    var isColorSelectionEnabled: Bool {
        !selectedTool.isEraser
    }

    /// True when the canvas differs from what's saved. Drives both the Save
    /// button and the struck-out attribution shown until the next save.
    /// Returns false again once edits are undone back to the saved state.
    var hasUnsavedEdits: Bool {
        Self.drawingSignature(for: drawing) != lastSavedDrawingSignature
    }

    /// A stable signature of just the visible strokes, so add-then-undo returns
    /// to the same value and a re-encode after saving does not. Built from each
    /// stroke's geometry and ink instead of the serialized bytes, which are not
    /// stable for identical content. See `lastSavedDrawingSignature`.
    private static func drawingSignature(for drawing: PKDrawing) -> Int {
        var hasher = Hasher()
        hasher.combine(drawing.strokes.count)
        for stroke in drawing.strokes {
            hasher.combine(stroke.path.count)
            hasher.combine(stroke.ink.inkType)

            // Round to whole points so sub-pixel re-rendering noise after a
            // commit never reads as a change.
            let bounds = stroke.renderBounds
            hasher.combine(Int(bounds.minX.rounded()))
            hasher.combine(Int(bounds.minY.rounded()))
            hasher.combine(Int(bounds.width.rounded()))
            hasher.combine(Int(bounds.height.rounded()))

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            hasher.combine(Int((red * 255).rounded()))
            hasher.combine(Int((green * 255).rounded()))
            hasher.combine(Int((blue * 255).rounded()))
            hasher.combine(Int((alpha * 255).rounded()))
        }
        return hasher.finalize()
    }

    /// True when there is drawn content that differs from what's already saved.
    var canSave: Bool {
        !isSaving && !drawing.strokes.isEmpty && hasUnsavedEdits
    }

    /// True when a non-cleared canvas has saved attribution to show.
    var isShowingSavedAttribution: Bool {
        !drawing.strokes.isEmpty && savedDrawingCreatedAt != nil
    }

    /// True when there is drawn content the user can clear from the canvas.
    var canClear: Bool {
        !isSaving && !drawing.strokes.isEmpty
    }

    var pencilKitTool: any PKTool {
        selectedTool.pencilKitTool(
            color: selectedUIColor,
            width: toolWidth
        )
    }

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
        refreshUndoRedoAvailability(using: undoManager)

        Task { @MainActor in
            self.refreshUndoRedoAvailability()
        }
    }

    /// Loads the last saved drawing into the canvas once, so the user continues
    /// from where they left off. Never clobbers in-progress work.
    func loadSavedDrawingIfNeeded() async {
        guard !hasLoadedSavedDrawing else {
            return
        }
        hasLoadedSavedDrawing = true

        guard drawing.strokes.isEmpty,
              let snapshot = await service.loadSavedSnapshot(),
              let savedDrawing = try? PKDrawing(data: snapshot.drawingData)
        else {
            return
        }

        drawing = savedDrawing
        lastSavedDrawingSignature = Self.drawingSignature(for: savedDrawing)
        savedDrawingAuthorName = snapshot.authorName
        savedDrawingCreatedAt = snapshot.createdAt
        refreshUndoRedoAvailability()
    }

    /// Re-loads the saved drawing when a partner's update has synced in (the
    /// screen was already open). Skips when the user has unsaved edits, so
    /// in-progress work is never clobbered, and no-ops when nothing changed.
    func reloadSavedDrawingFromSyncIfSafe() async {
        guard drawing.strokes.isEmpty || !hasUnsavedEdits else {
            return
        }

        guard let snapshot = await service.loadSavedSnapshot(),
              let savedDrawing = try? PKDrawing(data: snapshot.drawingData)
        else {
            return
        }

        let signature = Self.drawingSignature(for: savedDrawing)
        guard signature != lastSavedDrawingSignature else {
            return
        }

        drawing = savedDrawing
        lastSavedDrawingSignature = signature
        savedDrawingAuthorName = snapshot.authorName
        savedDrawingCreatedAt = snapshot.createdAt
        hasLoadedSavedDrawing = true
        refreshUndoRedoAvailability()
    }

    /// Persists the current drawing and publishes it to the widget.
    func save() async {
        guard canSave else {
            return
        }

        isSaving = true
        saveFailure = nil
        let drawingData = drawing.dataRepresentation()
        let savedAt = Date()
        let canvasSize = currentCanvasSize()
        // Snapshot the PencilKit-derived metadata now (on the main actor) so the
        // upload uses values consistent with the bytes we're saving.
        let uploadPayload = WidgetDrawingUploadPayload(
            drawingData: drawingData,
            canvasSide: canvasSize.width,
            strokeCount: drawing.strokes.count,
            pointCount: drawing.strokes.reduce(0) { $0 + $1.path.count },
            bounds: drawing.bounds
        )

        do {
            try await service.saveDrawing(
                drawingData,
                canvasSize: canvasSize,
                authorName: authorName,
                createdAt: savedAt
            )
            lastSavedDrawingSignature = Self.drawingSignature(for: drawing)
            savedDrawingAuthorName = authorName
            savedDrawingCreatedAt = savedAt
            isSaving = false
            showSavedConfirmation()
            // Local widget already updated; send to the partner in the background.
            await uploader.enqueueUpload(uploadPayload)
        } catch {
            isSaving = false
            saveFailure = WidgetDrawingSaveFailure()
        }
    }

    /// Empties the canvas as a local editing action. The widget keeps showing
    /// the last saved drawing until the user saves again.
    func clearCanvas() {
        drawing = PKDrawing()
        canvasView?.drawing = PKDrawing()
        canvasView?.undoManager?.removeAllActions()
        refreshUndoRedoAvailability()
    }

    private func currentCanvasSize() -> CGSize {
        let bounds = canvasView?.bounds.size ?? .zero
        guard bounds.width > 0, bounds.height > 0 else {
            return CGSize(width: Self.fallbackCanvasSide, height: Self.fallbackCanvasSide)
        }
        return bounds
    }

    private func showSavedConfirmation() {
        recentlySaved = true
        savedConfirmationTask?.cancel()
        savedConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.savedConfirmationDuration)
            guard !Task.isCancelled else {
                return
            }
            self?.recentlySaved = false
        }
    }

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

private extension UIColor {
    static func paeoniaDrawingColor(from cgColor: CGColor) -> UIColor {
        let resolvedColor = UIColor(cgColor: cgColor).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let convertedColor = resolvedColor.cgColor.converted(
                  to: colorSpace,
                  intent: .defaultIntent,
                  options: nil
              )
        else {
            return resolvedColor
        }

        return UIColor(cgColor: convertedColor)
    }
}
