import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// The idea chip, the draft on the phone, a part the server refused, and the strip
/// above the canvas. The viewer is `me`. Figure 1 starts with the partner and
/// figure 2 with `me`.
@MainActor
struct ExquisiteCorpseViewModelDraftTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private func base64(_ drawing: PKDrawing) -> String {
        drawing.dataRepresentation().base64EncodedString()
    }

    /// A drawing with the strokes of all of them, so a test can add to what is on the canvas.
    private func combined(_ drawings: PKDrawing...) -> PKDrawing {
        PKDrawing(strokes: drawings.flatMap(\.strokes))
    }

    @Test func theChipOnScreenWhenDoneIsTappedStaysWithThePart() async throws {
        let withChip = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let withChipViewModel = await withChip.loadedViewModel()
        withChipViewModel.askIdea()
        withChipViewModel.shuffleIdea()
        withChipViewModel.board.updateDrawing(CorpseDrawings.aboveFold)
        await withChipViewModel.finishDrawing()

        let removed = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let removedViewModel = await removed.loadedViewModel()
        removedViewModel.askIdea()
        removedViewModel.removeIdea()
        removedViewModel.board.updateDrawing(CorpseDrawings.aboveFold)
        await removedViewModel.finishDrawing()

        let withChipPart = try #require(await withChip.queuedParts().first)
        let removedPart = try #require(await removed.queuedParts().first)
        #expect(withChipPart.idea == Fixture.ideas[1])
        #expect(removedPart.idea == nil)
    }

    // MARK: Drafts and refusals

    @Test func aDraftAndTheChipComeBackWhenTheScreenOpensAgain() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let first = await env.loadedViewModel()
        first.askIdea()
        first.shuffleIdea()
        first.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        first.saveDraftNow()
        await first.ideaSaveTask?.value

        let second = env.viewModel()
        await second.reload()

        #expect(second.phase == .drawing)
        #expect(second.board.drawing.strokes.count == 2)
        #expect(second.idea == Fixture.ideas[1])
    }

    @Test func aDraftIsKeptForEachPart() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(CorpseDrawings.aboveFold)
        viewModel.saveDraftNow()

        let body = Fixture.partID(figure: 1, partIndex: 1)
        let legs = Fixture.partID(figure: 2, partIndex: 2)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: body) != nil)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: legs) == nil)
    }

    @Test func clearingTheCanvasRemovesTheDraft() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(CorpseDrawings.aboveFold)
        viewModel.saveDraftNow()

        viewModel.board.clear()
        viewModel.saveDraftNow()

        let body = Fixture.partID(figure: 1, partIndex: 1)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: body) == nil)
    }

    @Test func aRefusedPartComesBackOnTheCanvasWithItsChipAndANotice() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.askIdea()
        viewModel.board.updateDrawing(combined(CorpseDrawings.aboveFold, CorpseDrawings.crossingFold))
        await viewModel.finishDrawing()
        await viewModel.ideaSaveTask?.value
        #expect(viewModel.phase == .waiting)

        // The server refuses the part for good, and the handler puts it back as the draft.
        env.gateway.setSubmitError(Fixture.refusal("22023", "the head and the body need a strip"))
        let handler = ExquisiteCorpseSubmitPartHandler(
            gateway: env.gateway,
            transfer: env.transfer,
            cache: env.cache,
            drawingStore: env.drawingStore
        )
        let queued = try #require(await env.queued(.exquisiteCorpseSubmitPart).first)
        let context = SyncContext(
            session: SyncSession(userID: Fixture.me),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: env.pending
        )
        let result = try await handler.send(queued, context: context)
        expectCorpseTerminalFailure(result)
        try await env.pending.markTerminalFailure(
            clientOperationID: queued.operation.id,
            errorDescription: "refused",
            at: Fixture.now
        )
        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.board.drawing.strokes.count == 2)
        #expect(viewModel.idea == Fixture.ideas[0])
        #expect(viewModel.notice == .exquisiteCorpsePartRejected)
        #expect(!viewModel.isWaitingToSend)
        #expect(viewModel.canFinishDrawing)
    }

    // MARK: The strip above the canvas

    /// The partner drew the head of figure 1 while this phone watched. Their strip came live, and then the
    /// turn moved to the body, whose head has a strip file the phone cannot fetch yet.
    private struct HandOff {
        let env: ExquisiteCorpseTestEnvironment
        let viewModel: ExquisiteCorpseViewModel
        let stripID: UUID
        let live: PKDrawing
    }

    private func handOffToTheBody() async throws -> HandOff {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.partnerHeadTurn())
        let viewModel = env.viewModel()
        await viewModel.reload()
        env.connection.partnerJoins(role: "drawing")
        viewModel.recompute()
        #expect(viewModel.phase == .watching)

        let headID = Fixture.partID(figure: 1, partIndex: 0)
        let live = CorpseDrawings.belowFold
        env.connection.partnerSends(.strip(partID: headID, drawing: base64(live)))
        env.connection.partnerSends(.done(partID: headID))

        let current = Fixture.figure(1, parts: 1)
        await env.serverState(Fixture.state(
            game: Fixture.game(figure: 1, partIndex: 1, turn: Fixture.me),
            current: current,
            ideas: Fixture.ideas
        ))
        await viewModel.reload()
        let stripID = try #require(current.parts.first?.stripMediaAssetID)
        return HandOff(env: env, viewModel: viewModel, stripID: stripID, live: live)
    }

    @Test func aLiveStripShowsOnMyDrawingScreenUntilTheDownloadedStripArrives() async throws {
        let handOff = try await handOffToTheBody()
        let (env, viewModel, stripID, live) = (handOff.env, handOff.viewModel, handOff.stripID, handOff.live)

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.part == .body)
        #expect(viewModel.strip?.paeoniaContentSignature == live.paeoniaContentSignature)
        let failed = await waitUntil { viewModel.stripLoadFailed }
        #expect(failed)
        // The strip still shows while the file is out of reach.
        #expect(viewModel.strip?.paeoniaContentSignature == live.paeoniaContentSignature)

        let file = ExquisiteCorpseFold.strip(of: CorpseDrawings.crossingFold)
        env.transfer.setFile(file.dataRepresentation(), for: stripID)
        viewModel.retryLoadingStrip()
        let loaded = await waitUntil {
            !viewModel.stripLoadFailed && viewModel.strip?.paeoniaContentSignature == file.paeoniaContentSignature
        }

        #expect(loaded)
        #expect(!viewModel.isLoadingStrip)
        #expect(env.transfer.downloads.contains(stripID))
        // The file is kept, so the next visit does not fetch it again.
        #expect(env.drawingStore.downloadedDrawing(mediaAssetID: stripID) != nil)
    }
}

/// Drawings that never reached the server wait for the next empty canvas.
extension ExquisiteCorpseViewModelDraftTests {
    @Test func aPartRefusedAfterItsTurnMovedOnComesBackOnTheNextEmptyCanvas() async throws {
        // This person's head of figure 2 was refused, also sent from their other phone,
        // and the turn is their legs now.
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myLegsTurn())
        let head = Fixture.partID(figure: 2, partIndex: 0)
        let drawing = CorpseDrawings.crossingFold.dataRepresentation()
        env.drawingStore.saveDraft(drawing, ownerUserID: Fixture.me, roundID: head)

        let viewModel = await env.loadedViewModel()

        let legs = Fixture.partID(figure: 2, partIndex: 2)
        #expect(viewModel.phase == .drawing)
        #expect(viewModel.board.drawing.strokes.count == CorpseDrawings.crossingFold.strokes.count)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: legs) != nil)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: head) == nil)
    }

    @Test func leftoverDrawingsComeBackOldestFirstOnePerEmptyCanvas() async {
        // Figure 1's body and figure 2's head are this person's, and neither reached the server.
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myLegsTurn())
        let older = Fixture.partID(figure: 1, partIndex: 1)
        let newer = Fixture.partID(figure: 2, partIndex: 0)
        let store = env.drawingStore
        store.saveDraft(CorpseDrawings.crossingFold.dataRepresentation(), ownerUserID: Fixture.me, roundID: older)
        store.saveDraft(CorpseDrawings.aboveFold.dataRepresentation(), ownerUserID: Fixture.me, roundID: newer)

        let viewModel = await env.loadedViewModel()

        #expect(viewModel.board.drawing.strokes.count == CorpseDrawings.crossingFold.strokes.count)
        #expect(store.draft(ownerUserID: Fixture.me, roundID: older) == nil)
        #expect(store.draft(ownerUserID: Fixture.me, roundID: newer) != nil)
    }

    @Test func thePartnersDraftsAndThisPartsOwnDraftAreNeverTaken() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myLegsTurn())
        let partnersBody = Fixture.partID(figure: 2, partIndex: 1)
        let legs = Fixture.partID(figure: 2, partIndex: 2)
        let store = env.drawingStore
        let drawing = CorpseDrawings.crossingFold.dataRepresentation()
        store.saveDraft(drawing, ownerUserID: Fixture.me, roundID: partnersBody)
        store.saveDraft(CorpseDrawings.aboveFold.dataRepresentation(), ownerUserID: Fixture.me, roundID: legs)

        let viewModel = await env.loadedViewModel()

        #expect(viewModel.board.drawing.strokes.count == CorpseDrawings.aboveFold.strokes.count)
        #expect(store.draft(ownerUserID: Fixture.me, roundID: partnersBody) != nil)
    }

    @Test func aCanvasTheTurnLeftWithoutASendIsKeptAsItsDraft() async {
        // This person draws the body here, and sends it from their other phone first.
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(CorpseDrawings.crossingFold)
        let body = Fixture.partID(figure: 1, partIndex: 1)

        await env.serverState(Fixture.state(
            game: Fixture.game(figure: 1, partIndex: 2, turn: Fixture.partner),
            current: Fixture.figure(1, parts: 2)
        ))
        await viewModel.reload()

        #expect(viewModel.phase != .drawing)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: body) != nil)
    }

    @Test func aTurnThatJumpsToAnotherOfMyPartsKeepsTheCanvas() async {
        // This person draws the head here. Their other phone sends it, the partner sends
        // the body, and this phone next reads the legs turn.
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myHeadTurn(figure: 2))
        let viewModel = await env.loadedViewModel()
        viewModel.board.updateDrawing(CorpseDrawings.crossingFold)

        await env.serverState(Fixture.myLegsTurn())
        await viewModel.reload()

        let head = Fixture.partID(figure: 2, partIndex: 0)
        let legs = Fixture.partID(figure: 2, partIndex: 2)
        #expect(viewModel.phase == .drawing)
        #expect(viewModel.part == .legs)
        #expect(viewModel.board.drawing.strokes.count == CorpseDrawings.crossingFold.strokes.count)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: legs) != nil)
        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: head) == nil)
    }

    @Test func aCanvasClearedJustBeforeTheTurnLeftLeavesNoDraft() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let body = Fixture.partID(figure: 1, partIndex: 1)
        let drawing = CorpseDrawings.crossingFold.dataRepresentation()
        env.drawingStore.saveDraft(drawing, ownerUserID: Fixture.me, roundID: body)
        let viewModel = await env.loadedViewModel()
        viewModel.board.clear()

        await env.serverState(Fixture.state(
            game: Fixture.game(figure: 1, partIndex: 2, turn: Fixture.partner),
            current: Fixture.figure(1, parts: 2)
        ))
        await viewModel.reload()

        #expect(env.drawingStore.draft(ownerUserID: Fixture.me, roundID: body) == nil)
    }
}
