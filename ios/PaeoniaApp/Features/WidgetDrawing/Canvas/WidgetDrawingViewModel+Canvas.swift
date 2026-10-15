import PencilKit
import UIKit

extension WidgetDrawingViewModel {
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

    func currentCanvasSide() -> CGFloat {
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
    func fitDrawingToCanvas() {
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

    func setBaseline(_ baseline: PKDrawing, authorName: String?, createdAt: Date?) {
        savedBaseline = baseline
        lastSavedDrawingSignature = baseline.paeoniaContentSignature
        savedDrawingAuthorName = authorName
        savedDrawingCreatedAt = createdAt
    }

    /// Replaces the canvas content from code (not from a stroke). Undo starts
    /// over, because its steps were made on the drawing that is gone.
    func replaceDrawing(with newDrawing: PKDrawing) {
        history.removeAll()
        showOnCanvas(newDrawing)
        live?.drawingReplacedFromCode(newDrawing)
    }

    /// A change the person made with a button or a tap, not a stroke.
    func applyEdit(_ newDrawing: PKDrawing) {
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
    func applyPartnerLiveDrawing(_ merged: PKDrawing) {
        showOnCanvas(merged)
        live?.drawingReplacedFromCode(merged)
        scheduleDraftPersistence()
    }

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
