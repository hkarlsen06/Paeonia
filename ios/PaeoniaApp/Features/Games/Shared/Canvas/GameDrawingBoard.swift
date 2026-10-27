import Observation
import PencilKit
import SwiftUI

/// The drawer's canvas state: the drawing, the tool, and undo. The game view
/// model owns one. `PencilKitCanvasView` binds to it, and it reports each change
/// the person makes so the view model can stream it to the partner and keep a
/// draft on the phone.
@MainActor
@Observable
final class GameDrawingBoard: WidgetDrawingToolControlling {
    var drawing = PKDrawing()
    /// Changes only when the drawing was replaced from code (a restored draft or a
    /// new round), so strokes drawn on the canvas are never pushed back into it.
    private(set) var drawingRevision = 0
    private(set) var selectedTool: WidgetDrawingTool = .pen
    private(set) var selectedLineStyle: InkLineStyle = .solid
    private(set) var selectedColorChoiceID: String? = WidgetDrawingColorChoice.palette[0].id
    private(set) var selectedCGColor: CGColor = WidgetDrawingColorChoice.palette[0].uiColor.cgColor
    private(set) var toolWidthFraction = DrawingToolSizes.fraction(for: .pen)
    private(set) var isAdjustingToolWidth = false
    /// The side of the square canvas on screen, in points. Zero until laid out.
    private(set) var canvasSide: CGFloat = 0
    private var history = DrawingEditHistory()
    var canUndoDrawing: Bool { history.canUndo }
    var canRedoDrawing: Bool { history.canRedo }
    /// A stroke is being drawn right now.
    private(set) var isStrokeInProgress = false

    /// The person drew, erased, undid or cleared. Not called for changes from code.
    @ObservationIgnored var onUserChange: ((PKDrawing) -> Void)?

    @ObservationIgnored private weak var canvasView: PKCanvasView?
    /// The `drawingRevision` the canvas view shows. Until it catches up, the
    /// canvas holds an older drawing and is not read back.
    @ObservationIgnored private var canvasDrawingRevision = 0
    @ObservationIgnored private var canvasRefreshTask: Task<Void, Never>?
    /// The tool before the current one, for Apple Pencil's "last used" double tap.
    @ObservationIgnored private var previousTool: WidgetDrawingTool?
    /// The pen or pencil to go back to after the eraser.
    @ObservationIgnored private var lastDrawingTool: WidgetDrawingTool = .pen

    var isEmpty: Bool {
        drawing.strokes.isEmpty
    }

    var toolWidth: CGFloat {
        selectedTool.width(forFraction: toolWidthFraction)
    }

    var canvasTool: CanvasTool {
        selectedTool.canvasTool(
            color: UIColor(cgColor: selectedCGColor), width: toolWidth, lineStyle: selectedLineStyle
        )
    }

    /// The drawing at the size every phone exchanges.
    var canonicalDrawing: PKDrawing {
        GameCanvas.canonical(drawing, fromSide: canvasSide)
    }

    // MARK: Tools

    let colorChoices = WidgetDrawingColorChoice.palette

    var isColorSelectionEnabled: Bool {
        !selectedTool.isEraser
    }

    var isLineStyleSelectionEnabled: Bool {
        selectedTool.drawsLines
    }

    func selectTool(_ tool: WidgetDrawingTool) {
        guard selectedTool != tool else { return }
        previousTool = selectedTool
        if !selectedTool.isEraser {
            lastDrawingTool = selectedTool
        }
        selectedTool = tool
        toolWidthFraction = DrawingToolSizes.fraction(for: tool)
    }

    func selectColorChoice(_ choice: WidgetDrawingColorChoice) {
        guard isColorSelectionEnabled else { return }
        selectedCGColor = choice.uiColor.cgColor
        selectedColorChoiceID = choice.id
    }

    func selectCustomColor(_ color: CGColor) {
        guard isColorSelectionEnabled else { return }
        let uiColor = UIColor.paeoniaDrawingColor(from: color)
        selectedCGColor = uiColor.cgColor
        selectedColorChoiceID = nil
    }

    func updateToolWidthFraction(_ fraction: CGFloat) {
        let clamped = min(max(0, fraction), 1)
        guard toolWidthFraction != clamped else { return }
        toolWidthFraction = clamped
        DrawingToolSizes.save(clamped, for: selectedTool)
    }

    func setAdjustingToolWidth(_ isAdjusting: Bool) {
        isAdjustingToolWidth = isAdjusting
    }

    func selectLineStyle(_ style: InkLineStyle) {
        guard isLineStyleSelectionEnabled else { return }
        selectedLineStyle = style
    }

    /// Apple Pencil double tap. It switches between the drawing tool and the
    /// eraser, or back to the last tool, following the Settings choice.
    func handlePencilDoubleTap(_ action: PencilPreferredAction) {
        if action == .ignore { return }
        if action == .switchPrevious, let previousTool {
            selectTool(previousTool)
            return
        }
        selectTool(selectedTool.isEraser ? lastDrawingTool : .eraser)
    }

    func setStrokeInProgress(_ isInProgress: Bool) {
        isStrokeInProgress = isInProgress
        if !isInProgress {
            scheduleCanvasRefreshes()
        }
    }

    // MARK: Canvas wiring

    func bindCanvasView(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
    }

    /// The canvas was laid out at `side` points. A drawing made at another size is
    /// scaled with it, so it is never mistaken for an edit.
    func canvasDidLayout(side: CGFloat) {
        guard side > 0, abs(side - canvasSide) >= 0.5 else { return }
        // A drawing restored before the first layout is at the canonical size.
        let previous = canvasSide > 0 ? canvasSide : GameCanvas.canonicalSide
        canvasSide = side
        if !drawing.strokes.isEmpty {
            history.scale(fromSide: previous, toSide: side)
            show(drawing.scaled(fromSide: previous, toSide: side))
        }
    }

    /// A stroke or an erase on the canvas.
    func updateDrawing(_ newDrawing: PKDrawing) {
        history.record(from: drawing, to: newDrawing)
        drawing = newDrawing
        onUserChange?(newDrawing)
    }

    func canvasDidApplyDrawing(revision: Int) {
        canvasDrawingRevision = revision
    }

    func canvasDidFinishRendering() {
        refreshDrawingFromCanvas()
    }

    /// The pixel eraser can finish changing the drawing after the last
    /// `canvasViewDrawingDidChange`. This reads the canvas again, so the partner,
    /// the draft and Done get the erase too.
    func refreshDrawingFromCanvas() {
        guard let canvasView, !isStrokeInProgress, canvasDrawingRevision == drawingRevision else { return }
        let canvasDrawing = canvasView.drawing
        guard canvasDrawing != drawing else { return }
        updateDrawing(canvasDrawing)
    }

    /// The drawing at the canonical size, with a late eraser change and the
    /// stroke being drawn right now included. It waits up to `strokeWait` for
    /// that stroke to end, then reads the canvas.
    func finishedCanonicalDrawing(strokeWait: Duration = .seconds(2)) async -> PKDrawing {
        let deadline = ContinuousClock.now + strokeWait
        while isStrokeInProgress, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        refreshDrawingFromCanvas()
        return canonicalDrawing
    }

    /// Rendering callbacks usually catch the late eraser change. These reads
    /// make sure of it.
    private func scheduleCanvasRefreshes() {
        canvasRefreshTask?.cancel()
        canvasRefreshTask = Task { [weak self] in
            for delay in [Duration.milliseconds(100), .milliseconds(500)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.refreshDrawingFromCanvas()
            }
        }
    }

    // MARK: Changes from code

    /// Puts a drawing on the canvas without telling the partner, for a restored
    /// draft or a new round. Undo starts over.
    func replace(with newDrawing: PKDrawing) {
        history.removeAll()
        show(newDrawing)
    }

    private func show(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        drawingRevision += 1
    }

    func reset() {
        replace(with: PKDrawing())
    }

    /// Puts a drawing kept at the canonical size on the canvas, scaled to the
    /// canvas when it is already laid out.
    func restore(canonical saved: PKDrawing) {
        let side = canvasSide > 0 ? canvasSide : GameCanvas.canonicalSide
        replace(with: saved.scaled(fromSide: GameCanvas.canonicalSide, toSide: side))
    }

    // MARK: Undo, clear and fill

    func undoDrawing() {
        refreshDrawingFromCanvas()
        if let previous = history.undo(drawing) {
            showEdit(previous)
        }
    }

    func redoDrawing() {
        refreshDrawingFromCanvas()
        if let next = history.redo(drawing) {
            showEdit(next)
        }
    }

    func clear() {
        guard !isEmpty else { return }
        applyEdit(PKDrawing())
    }

    /// The paint bucket was tapped at `point`, in canvas points.
    func fill(at point: CGPoint) {
        refreshDrawingFromCanvas()
        guard let stroke = DrawingFloodFill.fillStroke(
            in: drawing,
            side: canvasSide,
            at: point,
            color: UIColor(cgColor: selectedCGColor)
        ) else { return }
        applyEdit(PKDrawing(strokes: drawing.strokes + [stroke]))
    }

    /// A change the person made with a button or a tap, not a stroke.
    private func applyEdit(_ newDrawing: PKDrawing) {
        history.record(from: drawing, to: newDrawing)
        showEdit(newDrawing)
    }

    private func showEdit(_ newDrawing: PKDrawing) {
        show(newDrawing)
        onUserChange?(newDrawing)
    }
}
