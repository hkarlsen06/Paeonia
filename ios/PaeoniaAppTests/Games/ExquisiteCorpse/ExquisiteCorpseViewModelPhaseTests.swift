import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// What the screen is in, what this phone tells the partner, and what the folded
/// paper shows while the partner draws. The viewer is `me`. Figure 1 starts with
/// the partner and figure 2 with `me`.
@MainActor
struct ExquisiteCorpseViewModelPhaseTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private func base64(_ drawing: PKDrawing) -> String {
        drawing.dataRepresentation().base64EncodedString()
    }

    /// A view model that watches the partner draw the body of figure 2.
    private func watchingTheBody() async -> (env: ExquisiteCorpseTestEnvironment, viewModel: ExquisiteCorpseViewModel) {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.partnerBodyTurn())
        let viewModel = env.viewModel()
        await viewModel.reload()
        env.connection.partnerJoins(role: "drawing")
        viewModel.recompute()
        return (env, viewModel)
    }

    @Test func aDrawerWithAQueuedPartStaysDrawingUntilTheServerHasIt() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        try await env.queue(Fixture.queuedPart(figure: 1, partIndex: 1))
        let viewModel = env.viewModel()
        await viewModel.reload()

        // The screen shows the partner's turn, and the watcher keeps the folded paper.
        #expect(viewModel.phase == .waiting)
        #expect(viewModel.part == .legs)
        #expect(viewModel.isWaitingToSend)
        #expect(env.room.role == .drawing)

        // The server has the part, the queue is empty, and the role follows the phase.
        let queued = try #require(await env.queued(.exquisiteCorpseSubmitPart).first)
        try await env.pending.markSucceeded(clientOperationID: queued.operation.id, at: Fixture.now)
        await env.serverState(Fixture.state(
            game: Fixture.game(figure: 1, partIndex: 2, turn: Fixture.partner),
            current: Fixture.figure(1, parts: 2)
        ))
        await viewModel.reload()

        #expect(!viewModel.isWaitingToSend)
        #expect(env.room.role == .watching)
    }

    @Test func aQueuedLegsStaysDrawingWhileTheRevealWaitsForTheServer() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myLegsTurn())
        try await env.queue(Fixture.queuedPart(figure: 2, partIndex: 2))
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .waitingToSync)
        #expect(viewModel.part == nil)
        #expect(env.room.role == .drawing)
        #expect(viewModel.revealContent == nil)
    }

    @Test func theLegsDrawerSeesTheRevealOnceTheServerHasTheLegs() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myLegsTurn())
        try await env.queue(Fixture.queuedPart(figure: 2, partIndex: 2))
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .waitingToSync)

        let finished = Fixture.unseenReveal(figure: 2)
        env.seedDrawings(of: finished.recentFigures[0])
        let queued = try #require(await env.queued(.exquisiteCorpseSubmitPart).first)
        try await env.pending.markSucceeded(clientOperationID: queued.operation.id, at: Fixture.now)
        await env.serverState(finished)
        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(env.room.role == .result)
        let ready = await waitUntil { viewModel.revealContent?.isReady == true }
        #expect(ready)
    }

    @Test func messagesAboutAnotherPartAreIgnored() async {
        let (env, viewModel) = await watchingTheBody()
        let earlier = Fixture.partID(figure: 1, partIndex: 0)

        for other in [UUID(), earlier] {
            env.connection.partnerSends(.pen(partID: other, x: 0.5, y: 0.5))
            env.connection.partnerSends(.strip(partID: other, drawing: base64(CorpseDrawings.belowFold)))
            env.connection.partnerSends(.done(partID: other))
        }

        #expect(viewModel.partnerPen == nil)
        #expect(viewModel.partnerStrip == nil)
        #expect(viewModel.partnerDonePulse == 0)
        #expect(viewModel.partnerFinishedPart == nil)
        #expect(viewModel.phase == .watching)
    }

    @Test func theWatcherKeepsWatchingAfterDoneUntilTheServerMovesTheTurn() async {
        let (env, viewModel) = await watchingTheBody()
        let partID = Fixture.partID(figure: 2, partIndex: 1)

        env.connection.partnerSends(.done(partID: partID))
        #expect(viewModel.phase == .watching)
        #expect(viewModel.partnerFinishedPart == .body)
        #expect(viewModel.partnerDonePulse == 1)

        // Their phone moves on to the next screen before ours has the new turn.
        env.connection.partnerAnnounces(role: "watching")
        viewModel.recompute()
        env.connection.partnerSends(.done(partID: partID))
        #expect(viewModel.phase == .watching)
        #expect(viewModel.partnerFinishedPart == .body)
        // The same Done again is no second pulse.
        #expect(viewModel.partnerDonePulse == 1)

        await env.serverState(Fixture.myLegsTurn())
        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.part == .legs)
        #expect(viewModel.partnerFinishedPart == nil)
    }
}
