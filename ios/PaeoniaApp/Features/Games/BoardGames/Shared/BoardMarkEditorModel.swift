import Observation
import PencilKit
import UIKit

/// The state of the "Your mark" sheet: the drawing, undo, the live preview and
/// the save. The canvas draws at whatever size fits the screen. The model keeps
/// the drawing at that size and scales it to `BoardMarkRenderer.canvasSide`
/// when it saves or renders, so every phone stores the same square.
@MainActor
@Observable
final class BoardMarkEditorModel {
    enum Failure: Equatable {
        /// The drawing holds more data than the server keeps. The sheet says so inline.
        case tooBig
        /// The save did not go through. The drawing stays, and the sheet shows the
        /// top banner and then calls `clearFailure()`.
        case couldNotSave(PaeoniaFailure)
    }

    /// The ink width in canvas points, before the canvas is scaled.
    private static let inkWidth: CGFloat = 10

    /// The drawing at the size of the canvas on screen.
    private(set) var drawing: PKDrawing
    /// Changes only when the drawing was replaced from code (undo, clear or a
    /// resize), so strokes drawn on the canvas are never pushed back into it.
    private(set) var drawingRevision = 0
    private(set) var isSaving = false
    private(set) var failure: Failure?
    /// The mark as a template image for the piece previews. Nil while the canvas
    /// is empty, which previews the initial. It trails the drawing by a moment.
    private(set) var previewMark: UIImage?
    /// The person already has a drawn mark, so "Use my initial" has something to remove.
    let hasSavedMark: Bool
    /// The person's initial, shown on the previews while the canvas is empty.
    let initial: String

    private var history = DrawingEditHistory()
    @ObservationIgnored private var canvasSide: CGFloat = 0
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private let saveMark: (Data?) async throws -> Void

    /// - Parameters:
    ///   - initialMarkData: The saved mark's `PKDrawing` data, or nil without one.
    ///   - initial: The person's initial, for the previews.
    ///   - save: Stores the mark, or clears it when given nil. It throws when the
    ///     mark did not reach the server.
    init(initialMarkData: Data?, initial: String, save: @escaping (Data?) async throws -> Void) {
        drawing = initialMarkData.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        hasSavedMark = initialMarkData != nil
        self.initial = initial
        saveMark = save
        schedulePreview(after: .zero)
    }

    var isEmpty: Bool {
        drawing.strokes.isEmpty
    }

    var canUndo: Bool {
        history.canUndo
    }

    var canSave: Bool {
        !isEmpty && !isSaving
    }

    /// One ink in one width. White, because the boards tint the mark and only
    /// its shape matters. It uses the app's pen, which draws exactly the width it
    /// is given. PencilKit's own pen sizes finger strokes by speed.
    var tool: CanvasTool {
        WidgetDrawingTool.pen.canvasTool(color: .white, width: Self.inkWidth)
    }

    // MARK: Canvas

    /// The canvas was laid out at `side` points. A drawing made at another size is
    /// scaled with it, so the resize is never mistaken for an edit. The saved mark
    /// is at the canonical size until the first layout.
    func canvasDidLayout(side: CGFloat) {
        guard side > 0, abs(side - canvasSide) >= 0.5 else { return }
        let previous = canvasSide > 0 ? canvasSide : BoardMarkRenderer.canvasSide
        canvasSide = side
        guard !isEmpty else { return }
        history.scale(fromSide: previous, toSide: side)
        show(drawing.scaled(fromSide: previous, toSide: side))
    }

    /// The person drew a stroke on the canvas.
    func drawingChanged(_ newDrawing: PKDrawing) {
        history.record(from: drawing, to: newDrawing)
        drawing = newDrawing
        drawingEdited()
    }

    // MARK: Undo and clear

    func undo() {
        guard let previous = history.undo(drawing) else { return }
        show(previous)
        PaeoniaHaptics.selection()
        drawingEdited()
    }

    /// Clears the canvas. Undo brings the strokes back.
    func clear() {
        guard !isEmpty else { return }
        let cleared = PKDrawing()
        history.record(from: drawing, to: cleared)
        show(cleared)
        PaeoniaHaptics.selection()
        drawingEdited()
    }

    // MARK: Saving

    /// Saves the drawing as the person's mark. Returns true when it is saved, so
    /// the sheet can close. A drawing over the server's limit is refused, and a
    /// failed save keeps the drawing on the canvas. Both set `failure`.
    func save() async -> Bool {
        guard canSave else { return false }
        let data = drawing.scaled(fromSide: canvasSide, toSide: BoardMarkRenderer.canvasSide).dataRepresentation()
        guard BoardMarkRenderer.fits(data) else {
            failure = .tooBig
            PaeoniaHaptics.validationError()
            return false
        }
        return await commit(data)
    }

    /// Removes the drawn mark, so the person's initial shows on their pieces
    /// again. Returns true when it is removed.
    func useInitial() async -> Bool {
        guard !isSaving else { return false }
        return await commit(nil)
    }

    func clearFailure() {
        failure = nil
    }

    private func commit(_ data: Data?) async -> Bool {
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            try await saveMark(data)
            PaeoniaHaptics.drawingSent()
            return true
        } catch is CancellationError {
            return false
        } catch {
            failure = .couldNotSave(PaeoniaFailure(error))
            return false
        }
    }

    // MARK: Changes from code

    private func show(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        drawingRevision += 1
    }

    private func drawingEdited() {
        if failure == .tooBig {
            failure = nil
        }
        schedulePreview()
    }

    /// Draws the preview image shortly after the last change, off the main actor.
    private func schedulePreview(after delay: Duration = .milliseconds(150)) {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let canonical = drawing.scaled(fromSide: canvasSide, toSide: BoardMarkRenderer.canvasSide)
            guard !canonical.strokes.isEmpty else {
                previewMark = nil
                return
            }
            let image = await BoardMarkRenderer.image(from: canonical.dataRepresentation())
            guard !Task.isCancelled else { return }
            previewMark = image
        }
    }
}

extension BoardMarkEditorModel {
    /// The sheet for the signed-in person's mark, which every board game shares.
    /// A save goes to the server and then re-reads the marks, so open boards
    /// show the new mark.
    static func live(
        savedMark: RemoteBoardGameMark?,
        initial: String,
        userID: UUID?,
        dependencies: GamesDependencies
    ) -> BoardMarkEditorModel {
        let gateway = dependencies.boardGamesGateway
        let cache = dependencies.boardGamesCache
        let existing = savedMark.flatMap { BoardMarkRenderer.data(fromBase64: $0.drawing) }
        return BoardMarkEditorModel(initialMarkData: existing, initial: initial) { data in
            _ = try await gateway.setMark(data)
            if let userID {
                _ = try? await cache.fetchMarks(from: gateway, ownerUserID: userID)
                LocalStoreChanges.post(.games, ownerUserID: userID)
            }
        }
    }
}
