import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// Done: what the phone queues, and what it does at once. The viewer is `me`.
/// Figure 1 starts with the partner and figure 2 with `me`.
@MainActor
struct ExquisiteCorpseViewModelDoneTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private var foldY: CGFloat { ExquisiteCorpseFold.foldY() }

    /// A drawing with the strokes of all of them, so a test can add to what is on the canvas.
    private func combined(_ drawings: PKDrawing...) -> PKDrawing {
        PKDrawing(strokes: drawings.flatMap(\.strokes))
    }

    // MARK: Done

    @Test func doneIsOffUntilThereIsADrawing() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        #expect(!viewModel.canFinishDrawing)

        viewModel.board.updateDrawing(CorpseDrawings.aboveFold)

        #expect(viewModel.canFinishDrawing)
    }

    @Test func doneQueuesOneSubmitWithTheFigureAndPartIds() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(CorpseDrawings.crossingFold)
        viewModel.askIdea()

        await viewModel.finishDrawing()
        await viewModel.finishDrawing()

        let operations = await env.queued(.exquisiteCorpseSubmitPart)
        let payload = try #require(await env.queuedParts().first)
        #expect(operations.count == 1)
        #expect(payload.gameID == Fixture.gameID)
        #expect(payload.figureID == Fixture.figureID(1))
        #expect(payload.partID == Fixture.partID(figure: 1, partIndex: 1))
        #expect(payload.partIndex == 1)
        #expect(payload.coupleID == Fixture.couple)
        #expect(payload.idea == Fixture.ideas[0])
        #expect(operations.first?.idempotencyScope == "exquisite-corpse-part:\(payload.partID.uuidString.lowercased())")
        #expect(try PKDrawing(data: payload.drawing.data).strokes.count == 1)
        // The phone moves on at once, and the draft is not needed anymore.
        #expect(viewModel.phase == .waiting)
        #expect(viewModel.isWaitingToSend)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: payload.partID) == nil)
    }

    @Test func eachUploadAndTheSubmitHaveTheirOwnOperationsFromTheStart() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(CorpseDrawings.crossingFold)

        await viewModel.finishDrawing()

        let payload = try #require(await env.queuedParts().first)
        let strip = try #require(payload.strip)
        let queued = try #require(await env.queued(.exquisiteCorpseSubmitPart).first)
        let ids = [
            payload.drawing.reserveOperation.id,
            payload.drawing.finalizeOperation.id,
            strip.reserveOperation.id,
            strip.finalizeOperation.id,
            queued.operation.id,
        ]
        #expect(Set(ids).count == 5)
    }

    @Test func theBodyCarriesAStripCutAtTheFold() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))

        await viewModel.finishDrawing()

        let payload = try #require(await env.queuedParts().first)
        let whole = try PKDrawing(data: payload.drawing.data)
        let strip = try PKDrawing(data: try #require(payload.strip).data)
        #expect(whole.strokes.count == 2)
        // The stroke above the fold stays out, and the one across it keeps what is below.
        #expect(strip.strokes.count == 1)
        #expect(strip.strokes.allSatisfy { stroke in
            (0..<stroke.path.count).allSatisfy { stroke.path[$0].location.y >= foldY - 0.001 }
        })
    }

    @Test func theHeadHasAStripAndTheLegsHaveNone() async throws {
        let head = ExquisiteCorpseTestEnvironment(state: Fixture.myHeadTurn(figure: 2))
        let headViewModel = await head.loadedViewModel()
        headViewModel.board.updateDrawing(CorpseDrawings.crossingFold)
        await headViewModel.finishDrawing()

        let legs = ExquisiteCorpseTestEnvironment(state: Fixture.myLegsTurn())
        let legsViewModel = await legs.loadedViewModel()
        legsViewModel.board.updateDrawing(CorpseDrawings.crossingFold)
        await legsViewModel.finishDrawing()

        let headPayload = try #require(await head.queuedParts().first)
        let legsPayload = try #require(await legs.queuedParts().first)
        #expect(headPayload.partIndex == 0 && headPayload.strip != nil)
        #expect(legsPayload.partIndex == 2 && legsPayload.strip == nil)
    }

    @Test func aNewHeadNamesItsFigureFromTheGameAndTheNumber() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myHeadTurn(figure: 2))
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(CorpseDrawings.aboveFold)

        await viewModel.finishDrawing()

        let payload = try #require(await env.queuedParts().first)
        #expect(payload.figureID == Fixture.figureID(2))
        #expect(payload.partID == Fixture.partID(figure: 2, partIndex: 0))
        #expect(payload.idea == nil)
    }

    @Test func aDrawingTooBigToSendStaysOnTheCanvasWithANotice() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        let crowded = PKDrawing(strokes: (0...WidgetDrawingLimits.maxStrokes).map { index in
            CorpseDrawings.line(from: 20, to: 40, x: CGFloat(index % 300))
        })
        viewModel.board.updateDrawing(crowded)

        await viewModel.finishDrawing()

        #expect(await env.queued(.exquisiteCorpseSubmitPart).isEmpty)
        #expect(viewModel.phase == .drawing)
        #expect(viewModel.notice == .drawingTooBig)
    }
}
