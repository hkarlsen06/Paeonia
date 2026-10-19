import Foundation
import Testing
@testable import PaeoniaApp

/// What the Games hub shows for Story Chain: the status, whose turn it is, and
/// the stories finished.
@MainActor
struct StoryChainHubModelTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    private func game(
        _ state: StoryChainGameState,
        turn: UUID,
        finished: Int = 0,
        current: UUID? = Fixture.storyID
    ) -> RemoteStoryChainGame {
        RemoteStoryChainGame(
            id: Fixture.gameID,
            state: state,
            turnUserID: turn,
            turnNumber: 3,
            currentStoryID: current,
            storyCount: finished + 1,
            finishedCount: finished,
            turnStartedAt: Fixture.now,
            version: 1
        )
    }

    private func openHub(_ environment: Env) async -> StoryChainHubModel {
        let hub = environment.hubModel()
        hub.configure(participants: Env.participants)
        await hub.reload()
        return hub
    }

    private func summaryOf(_ state: RemoteStoryChainState?) async -> StoryChainHubSummary? {
        await openHub(Env(state: state)).summary
    }

    // MARK: Status

    private struct TurnCase {
        let state: RemoteStoryChainState
        let status: StoryChainHubSummary.Status
        let isYourTurn: Bool

        init(_ state: RemoteStoryChainState, _ status: StoryChainHubSummary.Status, _ isYourTurn: Bool) {
            self.state = state
            self.status = status
            self.isYourTurn = isYourTurn
        }
    }

    @Test func theStatusFollowsTheTurn() async {
        let theirLine = [Env.line(1, by: Fixture.me)]
        let myLine = [Env.line(1, by: Fixture.partner)]
        let partnerLines = Fixture.lines(8, starter: Fixture.partner)
        let myLines = Fixture.lines(8, starter: Fixture.me)
        let cases = [
            TurnCase(Env.state(game(.choosingOpening, turn: Fixture.me, current: nil)), .yourTurnToStart, true),
            TurnCase(Env.state(game(.choosingOpening, turn: Fixture.partner, current: nil)), .waitingForPartner, false),
            TurnCase(Env.writing(turn: Fixture.me, lines: myLine), .yourTurnToWrite, true),
            TurnCase(Env.writing(turn: Fixture.partner, lines: theirLine), .partnerTurn, false),
            TurnCase(Env.titling(turn: Fixture.me, lines: myLines), .yourTurnToName, true),
            TurnCase(Env.titling(turn: Fixture.partner, lines: partnerLines), .waitingForPartner, false),
        ]

        for turnCase in cases {
            let hub = await openHub(Env(state: turnCase.state))
            #expect(hub.summary?.status == turnCase.status)
            #expect(hub.isYourTurn == turnCase.isYourTurn)
        }
    }

    @Test func aFinishedStoryIAmYetToReadComesFirst() async {
        // The partner named the story and starts the next one. I have not read the ending.
        let unseen = Fixture.story(.finished, lines: Fixture.lines(8, starter: Fixture.partner), seenByMe: false)
        let seen = Fixture.story(.finished, lines: Fixture.lines(8, starter: Fixture.partner), seenByMe: true)
        let choosing = game(.choosingOpening, turn: Fixture.partner)

        let unseenHub = await openHub(Env(state: Env.state(choosing, current: unseen)))
        #expect(unseenHub.summary?.status == .readEnding)
        #expect(unseenHub.isYourTurn)

        let seenHub = await openHub(Env(state: Env.state(choosing, current: seen)))
        #expect(seenHub.summary?.status == .waitingForPartner)
        #expect(!seenHub.isYourTurn)
    }

    @Test func aMoveSavedOnThePhoneMovesTheTurn() async throws {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: [Env.line(1, by: Fixture.partner)]))
        let hub = await openHub(environment)
        #expect(hub.summary?.status == .yourTurnToWrite)

        try await StoryChainMoveQueue(dependencies: environment.dependencies())
            .addLine(Fixture.queuedLine(), ownerUserID: Fixture.me)
        await hub.reload()

        #expect(hub.summary?.status == .partnerTurn)
        #expect(!hub.isYourTurn)
    }

    // MARK: Finished stories

    @Test func theCardCountsTheStoriesFinished() async {
        let state = Env.state(
            game(.choosingOpening, turn: Fixture.me, finished: 3),
            current: Fixture.story(.finished, number: 3, seenByMe: true)
        )

        let summary = await summaryOf(state)

        #expect(summary?.finishedCount == 3)
        #expect(summary?.hasHistory == true)
        #expect(summary?.status == .yourTurnToStart)
    }

    @Test func aTitleSavedOnThePhoneCountsAsFinished() async throws {
        let environment = Env(state: Env.state(
            game(.titling, turn: Fixture.me, finished: 2),
            current: Fixture.story(.titling, number: 3, lines: Fixture.lines(8, starter: Fixture.me))
        ))
        let hub = await openHub(environment)
        #expect(hub.summary?.finishedCount == 2)
        #expect(hub.summary?.status == .yourTurnToName)

        try await StoryChainMoveQueue(dependencies: environment.dependencies())
            .name(StoryChainQueuedName(storyID: Fixture.storyID, title: "The night bus"), ownerUserID: Fixture.me)
        await hub.reload()

        #expect(hub.summary?.finishedCount == 3)
        #expect(hub.summary?.status == .yourTurnToStart)
    }

    // MARK: The card, the screens, and notices

    @Test func aNoticeLeftByABackgroundSendIsGivenOnce() async {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: [Env.line(1, by: Fixture.partner)]))
        let hub = await openHub(environment)
        await environment.cache.recordNotice(.moveRejected, ownerUserID: Fixture.me)

        #expect(await hub.takeNotice() == .moveRejected)
        #expect(await hub.takeNotice() == nil)
    }
}
