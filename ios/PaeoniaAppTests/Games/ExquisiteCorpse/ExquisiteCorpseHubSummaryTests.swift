import Foundation
import Testing
@testable import PaeoniaApp

/// What the Games hub says about Exquisite corpse, and whether the game waits for
/// this person. The viewer is `me`. Figure 1 starts with the partner, who draws
/// its head and legs, and figure 2 starts with `me`.
@MainActor
struct ExquisiteCorpseHubSummaryTests {
    private typealias Fixture = ExquisiteCorpseFixture
    private typealias Status = ExquisiteCorpseHubSummary.Status

    private func summary(
        _ state: RemoteExquisiteCorpseState,
        hasSettings: Bool = true,
        pending: ExquisiteCorpsePendingWork = .none
    ) -> ExquisiteCorpseHubSummary {
        let resolution = Fixture.resolver.resolve(
            state: state,
            hasSettings: hasSettings,
            pending: pending,
            isPartnerDrawingLive: false
        )
        return ExquisiteCorpseHubSummary(state: state, resolution: resolution)
    }

    // MARK: Statuses

    @Test func myTurnNamesThePartIDraw() {
        #expect(summary(Fixture.myHeadTurn()).status == .yourTurn(.head))
        #expect(summary(Fixture.myBodyTurn()).status == .yourTurn(.body))
        #expect(summary(Fixture.myLegsTurn()).status == .yourTurn(.legs))
        for state in [Fixture.myHeadTurn(), Fixture.myBodyTurn(), Fixture.myLegsTurn()] {
            #expect(summary(state).status.isYourTurn)
        }
    }

    @Test func thePartnersTurnNamesThePartTheyDraw() {
        #expect(summary(Fixture.partnerHeadTurn()).status == .partnerDrawing(.head))
        #expect(summary(Fixture.partnerBodyTurn()).status == .partnerDrawing(.body))
        let legs = Fixture.state(
            game: Fixture.game(figure: 1, partIndex: 2, turn: Fixture.partner),
            current: Fixture.figure(1, parts: 2)
        )
        #expect(summary(legs).status == .partnerDrawing(.legs))
        for state in [Fixture.partnerHeadTurn(), Fixture.partnerBodyTurn(), legs] {
            #expect(!summary(state).status.isYourTurn)
        }
    }

    @Test func aFinishedCreatureIDidNotSeeComesBeforeMyTurn() {
        // Figure 1 is done, and the next head is mine.
        let beforeMyTurn = summary(Fixture.unseenReveal(figure: 1))
        #expect(beforeMyTurn.status == .revealReady)
        #expect(beforeMyTurn.status.isYourTurn)
    }

    @Test func aFinishedCreatureIDidNotSeeStillWaitsForMeWhenThePartnerHasTheNextTurn() {
        // Figure 2 is done, and the partner draws the next head.
        let state = Fixture.unseenReveal(figure: 2)
        #expect(state.game?.turnUserID == Fixture.partner)

        let result = summary(state)

        #expect(result.status == .revealReady)
        #expect(result.status.isYourTurn)
    }

    @Test func afterTheRevealTheHubShowsTheTurn() {
        let seen = Fixture.state(
            game: Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me),
            recent: [Fixture.figure(1, revealSeen: true)]
        )
        #expect(summary(seen).status == .yourTurn(.head))

        // A mark that waits on the phone counts the same way.
        let unsent = Fixture.pending(revealsSeen: [Fixture.figureID(1)])
        #expect(summary(Fixture.unseenReveal(figure: 1), pending: unsent).status == .yourTurn(.head))
    }

    @Test func aPartSavedOnThePhoneMovesTheTurnToThePartner() {
        let body = Fixture.pending(parts: [Fixture.queuedPart(figure: 1, partIndex: 1)])

        let result = summary(Fixture.myBodyTurn(), pending: body)

        #expect(result.status == .partnerDrawing(.legs))
        #expect(!result.status.isYourTurn)
    }

    @Test func legsSavedOnThePhoneWaitForTheCreatureToFinish() {
        let legs = Fixture.pending(parts: [Fixture.queuedPart(figure: 2, partIndex: 2)])

        let result = summary(Fixture.myLegsTurn(), pending: legs)

        #expect(result.status == .partnerStarting)
        #expect(!result.status.isYourTurn)
    }

    @Test func aCoupleThatHasNotPlayedIsNotStarted() {
        let noGame = Fixture.state(game: nil)
        #expect(summary(noGame).status == .notStarted)
        // Setup comes first, and the hub only shows after it.
        #expect(summary(Fixture.myHeadTurn(), hasSettings: false).status == .notStarted)
        #expect(!summary(noGame).status.isYourTurn)
    }

    // MARK: Count and link

    @Test func theCountIsTheFinishedCreatures() {
        // Figure 4 is in progress, so three are finished.
        let state = Fixture.state(
            game: Fixture.game(figure: 4, partIndex: 0, turn: Fixture.me),
            recent: [Fixture.figure(3, revealSeen: true)]
        )

        let result = summary(state)

        #expect(result.figuresFinished == 3)
        #expect(result.hasCreatures)
    }

    @Test func theHistoryLinkNeedsAFinishedCreature() {
        #expect(!summary(Fixture.partnerHeadTurn()).hasCreatures)
        #expect(!summary(Fixture.state(game: nil)).hasCreatures)
        #expect(summary(Fixture.myHeadTurn()).hasCreatures)
    }

    // MARK: Hub model

    private func makeModel(
        _ state: RemoteExquisiteCorpseState?
    ) -> (ExquisiteCorpseHubModel, ExquisiteCorpseTestEnvironment) {
        let environment = ExquisiteCorpseTestEnvironment(state: state)
        let model = ExquisiteCorpseHubModel(dependencies: environment.dependencies(withRoom: false))
        model.configure(participants: ExquisiteCorpseTestEnvironment.participants)
        return (model, environment)
    }

    @Test func theModelReadsTheCacheAndTheBadgeFollowsMyTurn() async {
        let (model, _) = makeModel(Fixture.myBodyTurn())
        #expect(model.summary == nil)
        #expect(!model.isYourTurn)

        await model.reload()

        #expect(model.summary?.status == .yourTurn(.body))
        #expect(model.isYourTurn)
        #expect(model.kind == .exquisiteCorpse)
    }

    @Test func theModelCountsAPartSavedOnThePhone() async throws {
        let (model, environment) = makeModel(Fixture.myBodyTurn())
        await model.reload()
        #expect(model.isYourTurn)

        try await environment.queue(Fixture.queuedPart(figure: 1, partIndex: 1))
        await model.reload()

        #expect(model.summary?.status == .partnerDrawing(.legs))
        #expect(!model.isYourTurn)
    }

    @Test func theModelFollowsAServerStateThatMovesOn() async {
        let (model, environment) = makeModel(Fixture.partnerBodyTurn())
        await model.reload()
        #expect(!model.isYourTurn)

        await environment.serverState(Fixture.unseenReveal(figure: 2))
        await model.reload()

        #expect(model.summary?.status == .revealReady)
        #expect(model.isYourTurn)
    }

    @Test func noStateMeansNoCardAndNoBadge() async {
        let (model, _) = makeModel(nil)

        await model.reload()

        #expect(model.summary == nil)
        #expect(!model.isYourTurn)
    }

    @Test func anotherPersonStartsFromAnEmptyHub() async {
        let (model, _) = makeModel(Fixture.myBodyTurn())
        await model.reload()
        #expect(model.summary != nil)

        model.configure(participants: GameParticipants(currentUserID: Fixture.partner, coupleID: Fixture.couple))

        #expect(model.summary == nil)
        #expect(!model.isYourTurn)
    }

    @Test func aStoredNoticeReachesTheTab() async {
        let (model, environment) = makeModel(Fixture.myBodyTurn())
        await environment.cache.recordNotice(.partRejected, ownerUserID: Fixture.me)

        let notice = await model.takeNotice()

        #expect(notice == .exquisiteCorpsePartRejected)
        // The notice shows once.
        #expect(await model.takeNotice() == nil)
    }

    @Test func theModelOwnsTheScreensOfItsGame() {
        let (model, _) = makeModel(nil)

        #expect(model.screen(for: .game(.exquisiteCorpse)) != nil)
        #expect(model.screen(for: .exquisiteCorpseHistory) != nil)
        #expect(model.screen(for: .game(.drawAndGuess)) == nil)
        #expect(model.screen(for: .drawAndGuessHistory) == nil)
    }
}
