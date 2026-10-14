import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// What the drawer's phone tells the watching partner, and what it never does.
/// The viewer is `me`. Figure 1 starts with the partner and figure 2 with `me`.
@MainActor
struct ExquisiteCorpseViewModelLiveTests {
    private typealias Fixture = ExquisiteCorpseFixture

    /// A drawing with the strokes of all of them, so a test can add to what is on the canvas.
    private func combined(_ drawings: PKDrawing...) -> PKDrawing {
        PKDrawing(strokes: drawings.flatMap(\.strokes))
    }

    private func strips(in messages: [ExquisiteCorpseLiveMessage]) -> [(partID: UUID, drawing: PKDrawing)] {
        messages.compactMap { message in
            guard case let .strip(partID, encoded) = message,
                  let data = Data(base64Encoded: encoded),
                  let drawing = try? PKDrawing(data: data)
            else { return nil }
            return (partID, drawing)
        }
    }

    private func pens(in messages: [ExquisiteCorpseLiveMessage]) -> [[Double?]] {
        messages.compactMap { message in
            guard case let .pen(_, x, y) = message else { return nil }
            return [x, y]
        }
    }

    private func isDone(_ message: ExquisiteCorpseLiveMessage) -> Bool {
        if case .done = message { return true }
        return false
    }

    // MARK: Live

    @Test func doneSendsTheFinalStripAndDoneToAWatchingPartner() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        env.connection.partnerJoins(role: "watching")
        viewModel.recompute()
        viewModel.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        env.connection.forgetSent()

        await viewModel.finishDrawing()

        let partID = Fixture.partID(figure: 1, partIndex: 1)
        let messages = env.connection.gameMessages
        let sent = try #require(strips(in: messages).last)
        let payload = try #require(await env.queuedParts().first)
        let queuedStrip = try PKDrawing(data: try #require(payload.strip).data)
        #expect(sent.partID == partID)
        #expect(sent.drawing.paeoniaContentSignature == queuedStrip.paeoniaContentSignature)
        #expect(messages.last == .done(partID: partID))
        #expect(messages.filter(isDone).count == 1)
    }

    @Test func doneOnTheLegsSendsNoStrip() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myLegsTurn())
        let viewModel = await env.loadedViewModel()
        env.connection.partnerJoins(role: "watching")
        viewModel.recompute()
        viewModel.board.updateDrawing(CorpseDrawings.crossingFold)
        env.connection.forgetSent()

        await viewModel.finishDrawing()

        #expect(strips(in: env.connection.gameMessages).isEmpty)
        #expect(env.connection.gameMessages.last == .done(partID: Fixture.partID(figure: 2, partIndex: 2)))
    }

    @Test func theCanvasIsNeverAttachedToTheLiveRoom() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        env.connection.partnerJoins(role: "watching")
        viewModel.recompute()
        let canvasView = PKCanvasView()
        viewModel.canvasReady(canvasView)
        viewModel.canvasReady(canvasView)

        viewModel.board.updateDrawing(CorpseDrawings.aboveFold)
        viewModel.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        viewModel.penMoved(x: 0.4, y: 0.4)
        viewModel.penLifted()
        await viewModel.finishDrawing()

        // Only the pen listener is on the canvas, once.
        #expect(canvasView.gestureRecognizers?.filter { $0 is WidgetLiveTouchRecognizer }.count == 1)
        // The relay's own stroke messages never carry the part: only `hello`.
        #expect(env.connection.roomMessages.allSatisfy { $0.type == .hello })
        #expect(env.connection.roomMessages.allSatisfy { $0.upserts == nil && $0.points == nil })
        #expect(!env.room.hasSentCanvasToPartner)
    }

    @Test func aPartnerWhoAsksForTheCanvasGetsNoStrokes() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        env.connection.partnerJoins(role: "watching")
        // A watching phone that joins asks the drawing phone for its canvas.
        env.connection.onMessage?(WidgetLiveMessage(type: .hello, needsCanvas: true, from: "partner", role: "watching"))

        #expect(env.connection.roomMessages.allSatisfy { $0.type == .hello })
        #expect(!env.room.hasSentCanvasToPartner)
    }

    @Test func penMessagesAreQuantizedAndThrottled() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        env.connection.partnerJoins(role: "watching")
        viewModel.recompute()
        env.connection.forgetSent()

        viewModel.penMoved(x: 0.123, y: 0.456)
        env.clock.advance(by: 0.05)
        viewModel.penMoved(x: 0.9, y: 0.9)
        env.clock.advance(by: 0.1)
        viewModel.penMoved(x: 0.9, y: 0.9)
        viewModel.penMoved(x: 0.91, y: 0.91)
        viewModel.penLifted()

        let positions = pens(in: env.connection.gameMessages)
        #expect(positions.count == 3)
        // The centers of cells on a 20 by 20 grid, a first position, a second one after a pause, and the lift.
        #expect(positions.first == [0.125, 0.475])
        #expect(positions.dropFirst().first == [0.925, 0.925])
        #expect(positions.last == [nil, nil])
    }

    @Test func theMessagesNameThePartBeingDrawn() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        env.connection.partnerJoins(role: "watching")
        viewModel.recompute()
        env.connection.forgetSent()

        viewModel.penMoved(x: 0.5, y: 0.5)

        let partID = Fixture.partID(figure: 1, partIndex: 1)
        #expect(env.connection.gameMessages.first == .pen(partID: partID, x: 0.525, y: 0.525))
    }

    @Test func noPenMessagesGoOutWhenThePartnerIsNotInTheRoom() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()

        viewModel.penMoved(x: 0.2, y: 0.2)
        viewModel.penLifted()
        viewModel.board.updateDrawing(CorpseDrawings.crossingFold)

        #expect(env.connection.gameMessages.isEmpty)
    }

    @Test func theStripGoesOutOnlyWhenItChanges() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        env.connection.partnerJoins(role: "watching")
        viewModel.recompute()
        env.connection.forgetSent()
        let board = viewModel.board

        // Nothing above the fold is the partner's to see.
        board.updateDrawing(CorpseDrawings.aboveFold)
        #expect(strips(in: env.connection.gameMessages).isEmpty)

        board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        #expect(strips(in: env.connection.gameMessages).count == 1)

        // Another stroke up top changes nothing in the strip.
        board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold, CorpseDrawings.part(1)))
        #expect(strips(in: env.connection.gameMessages).count == 1)

        board.updateDrawing(combined(
            CorpseDrawings.aboveFold, CorpseDrawings.crossingFold, CorpseDrawings.part(1), CorpseDrawings.belowFold
        ))
        #expect(strips(in: env.connection.gameMessages).count == 2)

        // Erasing everything below the fold empties the strip, and the partner is told.
        board.updateDrawing(CorpseDrawings.aboveFold)
        let all = strips(in: env.connection.gameMessages)
        #expect(all.count == 3)
        #expect(all.last?.drawing.strokes.isEmpty == true)
    }

    @Test func aPartnerWhoArrivesGetsTheWholeStripAndAPenLift() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        #expect(env.connection.gameMessages.isEmpty)

        env.connection.partnerJoins(role: "watching")

        let partID = Fixture.partID(figure: 1, partIndex: 1)
        let sent = try #require(strips(in: env.connection.gameMessages).first)
        #expect(sent.partID == partID)
        #expect(sent.drawing.strokes.count == 1)
        #expect(env.connection.gameMessages.contains(.pen(partID: partID, x: nil, y: nil)))
    }

    @Test func aPartnerWhoStartsWatchingOnAnOpenConnectionGetsTheStrip() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        env.connection.partnerJoins(role: "present")
        viewModel.recompute()
        viewModel.board.updateDrawing(CorpseDrawings.crossingFold)
        env.connection.forgetSent()

        env.connection.partnerAnnounces(role: "watching")
        viewModel.recompute()

        #expect(strips(in: env.connection.gameMessages).count == 1)
    }

    @Test func aPartnerWhoArrivesAfterDoneGetsTheStripAndDoneAgainFromTheQueuedPart() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        await viewModel.finishDrawing()
        #expect(viewModel.phase == .waiting)
        env.connection.forgetSent()

        env.connection.partnerJoins(role: "watching")

        let partID = Fixture.partID(figure: 1, partIndex: 1)
        #expect(strips(in: env.connection.gameMessages).first?.partID == partID)
        #expect(env.connection.gameMessages.last == .done(partID: partID))
    }
}
