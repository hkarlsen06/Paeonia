import Foundation
import PencilKit
@testable import PaeoniaApp

/// What a person has on the canvas of a part.
struct CorpseSimDrawing: Equatable {
    let partID: UUID
    let strokes: Int
    let ideaID: String?
}

extension CorpseSimPhone {
    // MARK: - Drawing

    /// SwiftUI's part: the canvas lays out when the drawing screen shows, and a
    /// notice goes to the banner once.
    func updateScreens() {
        guard isAlive, let viewModel else { return }
        if isScreenOpen, viewModel.phase == .drawing {
            viewModel.board.canvasDidLayout(side: canvasSide)
        }
        if let notice = viewModel.notice {
            notices.append(notice)
            log.add("\(name) notice \(notice)")
            viewModel.clearNotice()
        }
    }

    /// A stroke with the pen: the pen moves along it, the canvas reports the new
    /// drawing, and the pen lifts.
    func draw(_ stroke: PKStroke) {
        guard let viewModel else { return }
        updateScreens()
        let board = viewModel.board
        let size = CGSize(width: canvasSide, height: canvasSide)
        board.setStrokeInProgress(true)
        for index in 0..<stroke.path.count {
            penClock.advance(by: 0.2)
            viewModel.penMoved(to: stroke.path[index].location, in: size)
        }
        board.updateDrawing(PKDrawing(strokes: board.drawing.strokes + [stroke]))
        board.setStrokeInProgress(false)
        viewModel.penLifted()
    }

    /// "Try again" on a strip or a reveal that could not be fetched.
    func retryFailedLoads() {
        guard let viewModel = activeViewModel else { return }
        if viewModel.stripLoadFailed { viewModel.retryLoadingStrip() }
        if viewModel.revealLoadFailed { viewModel.retryLoadingReveal() }
    }

    func erase(strokeAt index: Int) {
        guard let board = viewModel?.board, board.drawing.strokes.indices.contains(index) else { return }
        var strokes = board.drawing.strokes
        strokes.remove(at: index)
        board.updateDrawing(PKDrawing(strokes: strokes))
    }

    /// The canvas, the part and the idea as the person sees them while drawing.
    var drawingRecord: CorpseSimDrawing? {
        guard let viewModel = activeViewModel, viewModel.phase == .drawing, let partID = viewModel.ownPartID,
              viewModel.boardPartID == partID
        else { return nil }
        let strokes = viewModel.board.drawing.strokes.count
        return CorpseSimDrawing(partID: partID, strokes: strokes, ideaID: viewModel.idea?.id)
    }

    /// The game's own messages may carry the strip and nothing above the fold.
    func inspect(gameData data: Data) {
        guard let envelope = try? JSONDecoder().decode(GameLiveEnvelope<ExquisiteCorpseLiveMessage>.self, from: data),
              case let .strip(_, encoded) = envelope.message
        else { return }
        stripsSent += 1
        guard let bytes = Data(base64Encoded: encoded), let drawing = try? PKDrawing(data: bytes) else {
            leaks.append("\(name) sent a strip that does not decode")
            return
        }
        if let leak = CorpseSimFold.leak(in: drawing) {
            leaks.append("\(name) sent a live strip with \(leak)")
        }
    }

    /// The relay's own stroke messages carry the canvas, so a game that hides part
    /// of it must never send them.
    func inspect(_ message: WidgetLiveMessage) {
        if [.live, .liveEnd, .ops].contains(message.type) {
            leaks.append("\(name) sent a room \(message.type.rawValue) message")
        }
    }
}

/// What may leave a phone: a strip holds nothing above the fold.
enum CorpseSimFold {
    /// How far above the fold a point may be. `TEST_RUNNER_CORPSE_SIM_FOLD_TOLERANCE` widens it.
    static let tolerance: CGFloat = ProcessInfo.processInfo.environment["CORPSE_SIM_FOLD_TOLERANCE"]
        .flatMap(Double.init).map { CGFloat($0) } ?? 0.5

    /// A description of the stroke that reaches above the fold, or nil when the drawing is clean.
    static func leak(in drawing: PKDrawing) -> String? {
        let fold = ExquisiteCorpseFold.foldY()
        for stroke in drawing.strokes {
            let ys = (0..<stroke.path.count).map { stroke.path[$0].location.applying(stroke.transform).y }
            if let top = ys.min(), top < fold - tolerance {
                let list = ys.map { String(format: "%.1f", $0) }.joined(separator: ", ")
                return "a point at y \(top), above the fold at \(fold) (control points \(list) of \(ys.count))"
            }
        }
        return nil
    }
}
