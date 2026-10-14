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

    private func announcedRole(
        for state: RemoteExquisiteCorpseState?,
        hasSettings: Bool = true
    ) async -> WidgetLivePresence.Role {
        let env = ExquisiteCorpseTestEnvironment(state: state, hasSettings: hasSettings)
        await env.viewModel().reload()
        return env.room.role
    }

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

    // MARK: Phases

    @Test func theViewModelReadsThePhaseThePartAndTheFigure() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myBodyTurn())
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.part == .body)
        #expect(viewModel.figureNumber == 1)
        #expect(viewModel.figure?.id == Fixture.figureID(1))
        #expect(viewModel.ownPartID == Fixture.partID(figure: 1, partIndex: 1))
        #expect(!viewModel.isFirstFigure)
    }

    @Test func theFirstHeadOfAGameIsTheFirstFigure() async {
        let firstHead = Fixture.state(game: Fixture.game(figure: 1, partIndex: 0, turn: Fixture.me))
        let first = ExquisiteCorpseTestEnvironment(state: firstHead)
        let firstViewModel = first.viewModel()
        await firstViewModel.reload()
        let later = ExquisiteCorpseTestEnvironment(state: Fixture.myHeadTurn(figure: 2))
        let laterViewModel = later.viewModel()
        await laterViewModel.reload()

        #expect(firstViewModel.phase == .drawing && firstViewModel.isFirstFigure)
        #expect(laterViewModel.phase == .drawing && !laterViewModel.isFirstFigure)
    }

    @Test func theScreenIsBlankUntilBothTheStateAndTheSettingsHaveLoaded() async {
        let nothing = ExquisiteCorpseTestEnvironment(state: nil)
        let noNews = nothing.viewModel()
        await noNews.reload()
        #expect(noNews.phase == .loading)

        // A state without the shared overview is still loading, and not waiting for setup.
        let noOverview = ExquisiteCorpseTestEnvironment(state: Fixture.partnerHeadTurn())
        await noOverview.gamesCache.clearAll()
        let noOverviewViewModel = noOverview.viewModel()
        await noOverviewViewModel.reload()
        #expect(noOverviewViewModel.phase == .loading)

        let noSettings = ExquisiteCorpseTestEnvironment(state: Fixture.partnerHeadTurn(), hasSettings: false)
        let noSettingsViewModel = noSettings.viewModel()
        await noSettingsViewModel.reload()
        #expect(noSettingsViewModel.phase == .needsSetup)

        let noGame = ExquisiteCorpseTestEnvironment(state: Fixture.state(game: nil))
        let noGameViewModel = noGame.viewModel()
        await noGameViewModel.reload()
        #expect(noGameViewModel.phase == .preparing)
    }

    // MARK: Relay roles

    @Test func eachPhaseAnnouncesWhatTheScreenIsDoing() async {
        #expect(await announcedRole(for: Fixture.myBodyTurn()) == .drawing)
        #expect(await announcedRole(for: Fixture.partnerBodyTurn()) == .watching)
        #expect(await announcedRole(for: Fixture.unseenReveal(figure: 1)) == .result)
        #expect(await announcedRole(for: nil) == .present)
        #expect(await announcedRole(for: Fixture.partnerHeadTurn(), hasSettings: false) == .present)
        #expect(await announcedRole(for: Fixture.state(game: nil)) == .present)
    }

    @Test func aWatcherAnnouncesWatchingAndTheRoleFollowsThePhase() async {
        let (env, viewModel) = await watchingTheBody()

        #expect(viewModel.phase == .watching)
        #expect(env.room.role == .watching)
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

    // MARK: The partner's part

    @Test func aPartnerDrawingLiveIsWatchedAndTheirPenAndStripShow() async {
        let (env, viewModel) = await watchingTheBody()
        let partID = Fixture.partID(figure: 2, partIndex: 1)

        env.connection.partnerSends(.pen(partID: partID, x: 0.3, y: 0.4))
        #expect(viewModel.partnerPen == CGPoint(x: 0.3, y: 0.4))
        env.connection.partnerSends(.pen(partID: partID, x: nil, y: nil))
        #expect(viewModel.partnerPen == nil)

        let strip = CorpseDrawings.belowFold
        env.connection.partnerSends(.strip(partID: partID, drawing: base64(strip)))
        #expect(viewModel.partnerStrip?.paeoniaContentSignature == strip.paeoniaContentSignature)
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

    @Test func aStripThatIsNotADrawingIsIgnored() async {
        let (env, viewModel) = await watchingTheBody()

        env.connection.partnerSends(.strip(partID: Fixture.partID(figure: 2, partIndex: 1), drawing: "not a drawing"))

        #expect(viewModel.partnerStrip == nil)
    }

    @Test func aPenOutsideTheSquareIsKeptInsideIt() async {
        let (env, viewModel) = await watchingTheBody()

        env.connection.partnerSends(.pen(partID: Fixture.partID(figure: 2, partIndex: 1), x: 1.7, y: -0.4))

        #expect(viewModel.partnerPen == CGPoint(x: 1, y: 0))
    }

    @Test func thePenAndTheStripGoWhenThePartnerLeaves() async {
        let (env, viewModel) = await watchingTheBody()
        let partID = Fixture.partID(figure: 2, partIndex: 1)
        env.connection.partnerSends(.pen(partID: partID, x: 0.3, y: 0.4))
        env.connection.partnerSends(.strip(partID: partID, drawing: base64(CorpseDrawings.belowFold)))

        env.connection.partnerLeaves()
        viewModel.recompute()

        #expect(viewModel.phase == .waiting)
        #expect(viewModel.partnerPen == nil)
        #expect(viewModel.partnerStrip == nil)
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

    @Test func aPartnerWhoDrawsAgainAfterDoneIsNotFinished() async {
        let (env, viewModel) = await watchingTheBody()
        let partID = Fixture.partID(figure: 2, partIndex: 1)
        env.connection.partnerSends(.done(partID: partID))
        #expect(viewModel.partnerFinishedPart == .body)

        // Their part was refused and came back to their canvas.
        env.connection.partnerSends(.pen(partID: partID, x: 0.2, y: 0.2))

        #expect(viewModel.partnerFinishedPart == nil)
        #expect(viewModel.phase == .watching)
    }

    @Test func aWatcherForgetsThePartWhenTheTurnMovesOn() async {
        let (env, viewModel) = await watchingTheBody()
        let partID = Fixture.partID(figure: 2, partIndex: 1)
        env.connection.partnerSends(.pen(partID: partID, x: 0.3, y: 0.4))
        env.connection.partnerSends(.strip(partID: partID, drawing: base64(CorpseDrawings.belowFold)))

        await env.serverState(Fixture.myLegsTurn())
        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.partnerPen == nil)
        #expect(viewModel.partnerStrip == nil)
    }

    @Test func afterMyHeadTheWaitingScreenSaysItWasSent() async {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.partnerBodyTurn())
        let viewModel = env.viewModel()
        await viewModel.reload()
        let freshHead = ExquisiteCorpseTestEnvironment(state: Fixture.partnerHeadTurn())
        let freshViewModel = freshHead.viewModel()
        await freshViewModel.reload()

        #expect(viewModel.phase == .waiting)
        #expect(viewModel.didSendPreviousPart)
        #expect(!freshViewModel.didSendPreviousPart)
    }

    @Test func aQueuedPartIsNotSentYet() async throws {
        let env = ExquisiteCorpseTestEnvironment(state: Fixture.myHeadTurn(figure: 2))
        try await env.queue(Fixture.queuedPart(figure: 2, partIndex: 0))
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .waiting)
        #expect(viewModel.part == .body)
        #expect(viewModel.didSendPreviousPart)
        #expect(viewModel.isWaitingToSend)
    }
}
