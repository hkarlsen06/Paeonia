import Foundation
import Testing
@testable import PaeoniaApp

/// The phase a state puts the person in, from the server's rows and the moves
/// saved on the phone.
struct StoryChainResolverTests {
    private typealias Fixture = StoryChainFixture

    private let resolver = StoryChainResolver(userID: Fixture.me)

    private func resolve(
        _ state: RemoteStoryChainState?,
        settings: RemoteGameSettings? = Fixture.settings(),
        pending: StoryChainPendingWork = .none
    ) -> StoryChainResolution {
        resolver.resolve(state: state, settings: settings, pending: pending)
    }

    private func phase(_ state: RemoteStoryChainState?, pending: StoryChainPendingWork = .none) -> StoryChainPhase {
        resolve(state, pending: pending).phase
    }

    // MARK: Before the game

    @Test func noStateIsLoadingNoSettingsIsSetupAndNoGameIsPreparing() {
        #expect(phase(nil) == .loading)
        #expect(resolve(Fixture.state(nil), settings: nil).phase == .needsSetup)
        #expect(phase(Fixture.state(nil)) == .preparing)
    }

    // MARK: By game state and turn

    @Test func aChoosingGameBelongsToThePartnerWhoseTurnItIs() {
        let first = Fixture.game(.choosingOpening, turn: Fixture.me, current: nil, stories: 0)
        let theirs = Fixture.game(.choosingOpening, turn: Fixture.partner, current: nil, stories: 0)

        #expect(phase(Fixture.state(first)) == .chooseOpening)
        #expect(phase(Fixture.state(theirs)) == .waitingForOpening)
    }

    @Test func aStoryBeingWrittenBelongsToThePartnerWhoseTurnItIs() {
        let story = Fixture.story(.writing, lines: Fixture.lines(1, starter: Fixture.partner))

        #expect(phase(Fixture.state(Fixture.game(.writing, turn: Fixture.me), current: story)) == .writing)
        #expect(phase(Fixture.state(Fixture.game(.writing, turn: Fixture.partner), current: story)) == .waitingForLine)
    }

    @Test func aStoryWaitingForItsTitleBelongsToThePartnerWhoseTurnItIs() {
        let story = Fixture.story(.titling, lines: Fixture.lines(8, starter: Fixture.me))

        #expect(phase(Fixture.state(Fixture.game(.titling, turn: Fixture.me), current: story)) == .naming)
        #expect(phase(Fixture.state(Fixture.game(.titling, turn: Fixture.partner), current: story)) == .waitingForName)
    }

    @Test func theGameAndTheStoryMustAgreeOrThePersonWaitsForTheServer() {
        let writing = Fixture.story(.writing)
        let finished = Fixture.story(.finished, seenByMe: true)
        func phaseFor(_ game: StoryChainGameState, story: RemoteStoryChainStory?) -> StoryChainPhase {
            resolve(Fixture.state(Fixture.game(game, turn: Fixture.me), current: story)).phase
        }

        #expect(phaseFor(.writing, story: nil) == .waitingToSync)
        #expect(phaseFor(.titling, story: writing) == .waitingToSync)
        #expect(phaseFor(.choosingOpening, story: writing) == .waitingToSync)
        #expect(phaseFor(.writing, story: finished) == .waitingToSync)
    }

    // MARK: Finished stories

    @Test func anUnseenFinishedStoryComesFirstUntilItIsSeen() {
        let game = Fixture.game(.choosingOpening, turn: Fixture.me)
        func unseen(seenByMe: Bool) -> RemoteStoryChainState {
            Fixture.state(game, current: Fixture.story(.finished, seenByMe: seenByMe))
        }
        var marked = StoryChainPendingWork.none
        marked.seenStoryIDs = [Fixture.storyID]

        let reveal = resolve(unseen(seenByMe: false))

        #expect(reveal.phase == .finished(storyID: Fixture.storyID))
        #expect(reveal.story?.id == Fixture.storyID)
        #expect(reveal.turnPhase == .chooseOpening)
        #expect(phase(unseen(seenByMe: true)) == .chooseOpening)
        #expect(phase(unseen(seenByMe: false), pending: marked) == .chooseOpening)
        #expect(resolve(unseen(seenByMe: false), pending: marked).story?.story.seenByMe == true)
    }

    @Test func theTurnAfterTheRevealIsTheTurnOfTheGame() {
        let theirs = Fixture.state(
            Fixture.game(.choosingOpening, turn: Fixture.partner),
            current: Fixture.story(.finished, titledBy: Fixture.partner)
        )

        let resolution = resolve(theirs)

        #expect(resolution.phase == .finished(storyID: Fixture.storyID))
        #expect(resolution.turnPhase == .waitingForOpening)
    }

    @Test func thePreviousStoryComesFirstWhenTheNextOneAlreadyStarted() {
        let finished = Fixture.story(.finished, lines: Fixture.lines(8, starter: Fixture.partner))
        func afterNext(lines: Int, turn: UUID) -> RemoteStoryChainState {
            Fixture.state(
                Fixture.game(.writing, turn: turn, current: Fixture.nextStoryID, stories: 2),
                current: Fixture.story(
                    .writing,
                    id: Fixture.nextStoryID,
                    number: 2,
                    lines: Fixture.lines(lines, starter: Fixture.partner)
                ),
                previous: finished
            )
        }
        var seenOnPhone = StoryChainPendingWork.none
        seenOnPhone.seenStoryIDs = [Fixture.storyID]

        let partnerStarted = resolve(afterNext(lines: 0, turn: Fixture.partner))
        let myLineIsNext = resolve(afterNext(lines: 1, turn: Fixture.me))

        #expect(partnerStarted.phase == .finished(storyID: Fixture.storyID))
        #expect(partnerStarted.story?.id == Fixture.storyID)
        #expect(partnerStarted.turnPhase == .waitingForLine)
        #expect(myLineIsNext.phase == .finished(storyID: Fixture.storyID))
        #expect(myLineIsNext.turnPhase == .writing)
        #expect(phase(afterNext(lines: 1, turn: Fixture.me), pending: seenOnPhone) == .writing)
    }

    @Test func aStoryTheServerSaysIsSeenNeverShowsAgain() {
        let seen = Fixture.story(.finished, lines: Fixture.lines(8, starter: Fixture.partner), seenByMe: true)
        let state = Fixture.state(
            Fixture.game(.writing, turn: Fixture.partner, current: Fixture.nextStoryID, stories: 2),
            current: Fixture.story(.writing, id: Fixture.nextStoryID, number: 2),
            previous: seen
        )

        #expect(phase(state) == .waitingForLine)
    }

    // MARK: Unsent moves

    @Test func aQueuedLineShowsOnThePageAndPassesTheTurnToThePartner() {
        let story = Fixture.story(.writing, lines: Fixture.lines(1, starter: Fixture.partner))
        let state = Fixture.state(Fixture.game(.writing, turn: Fixture.me), current: story)
        let queued = Fixture.queuedLine()
        var pending = StoryChainPendingWork.none
        pending.lines = [queued]

        let resolution = resolve(state, pending: pending)

        #expect(resolution.phase == .waitingForLine)
        #expect(resolution.isWaitingToSend)
        #expect(resolution.story?.story.lines.count == 2)
        #expect(resolution.story?.story.lines.last?.number == 2)
        #expect(resolution.story?.story.lines.last?.authorUserID == Fixture.me)
        #expect(resolution.story?.unsentLineIDs == [queued.lineID])
        #expect(resolution.story?.story.state == .writing)
        #expect(state.currentStory?.lines.count == 1)
    }

    @Test func aLineTheServerAlreadyHasIsNotAddedAgain() {
        let lines = Fixture.lines(2, starter: Fixture.partner)
        let state = Fixture.state(
            Fixture.game(.writing, turn: Fixture.partner),
            current: Fixture.story(.writing, lines: lines)
        )
        var pending = StoryChainPendingWork.none
        pending.lines = [Fixture.queuedLine(id: lines[1].id)]

        let resolution = resolve(state, pending: pending)

        #expect(resolution.phase == .waitingForLine)
        #expect(resolution.story?.story.lines.count == 2)
        #expect(resolution.story?.unsentLineIDs.isEmpty == true)
    }

    @Test func aQueuedLastLineMovesTheStoryToTitlingAndPassesNamingToThePartner() {
        let story = Fixture.story(.writing, lines: Fixture.lines(7, starter: Fixture.partner))
        let state = Fixture.state(Fixture.game(.writing, turn: Fixture.me), current: story)
        var pending = StoryChainPendingWork.none
        pending.lines = [Fixture.queuedLine(isLast: true)]

        let resolution = resolve(state, pending: pending)

        #expect(resolution.phase == .waitingForName)
        #expect(resolution.story?.story.state == .titling)
        #expect(resolution.story?.story.lastLineUserID == Fixture.me)
        #expect(resolution.story?.story.lines.count == 8)
    }

    @Test func aQueuedNameFinishesTheStoryMarksItSeenAndGivesMeTheNextOpening() {
        let story = Fixture.story(.titling, starter: Fixture.me, lines: Fixture.lines(8, starter: Fixture.me))
        let state = Fixture.state(Fixture.game(.titling, turn: Fixture.me), current: story)
        var pending = StoryChainPendingWork.none
        pending.names = [StoryChainQueuedName(storyID: Fixture.storyID, title: "Night bus")]

        let resolution = resolve(state, pending: pending)

        #expect(resolution.phase == .chooseOpening)
        #expect(resolution.story?.story.state == .finished)
        #expect(resolution.story?.story.title == "Night bus")
        #expect(resolution.story?.story.titledByUserID == Fixture.me)
        #expect(resolution.story?.story.seenByMe == true)
        #expect(resolution.story?.hasUnsentName == true)
        #expect(resolution.story?.isWaitingToSend == true)
    }

    @Test func aQueuedStartMovesTheStarterToTheFirstLineOfTheNewStory() {
        let named = Fixture.story(.finished, starter: Fixture.partner, titledBy: Fixture.me, seenByMe: true)
        let state = Fixture.state(Fixture.game(.choosingOpening, turn: Fixture.me, stories: 1), current: named)
        let start = Fixture.queuedStart()
        var pending = StoryChainPendingWork.none
        pending.starts = [start]

        let resolution = resolve(state, pending: pending)

        #expect(resolution.phase == .writing)
        #expect(resolution.story?.id == Fixture.nextStoryID)
        #expect(resolution.story?.story.storyNumber == 2)
        #expect(resolution.story?.story.starterUserID == Fixture.me)
        #expect(resolution.story?.story.openingText == "A key opened nothing in town.")
        #expect(resolution.story?.story.lines.isEmpty == true)
        #expect(resolution.story?.isOnlyOnThisPhone == true)

        pending.lines = [Fixture.queuedLine(story: Fixture.nextStoryID)]
        let withFirstLine = resolve(state, pending: pending)
        #expect(withFirstLine.phase == .waitingForLine)
        #expect(withFirstLine.story?.story.lines.count == 1)
    }

    @Test func aStartForAnotherGameOrOneTheServerHasIsNotAppliedTwice() {
        let named = Fixture.story(.finished, starter: Fixture.partner, titledBy: Fixture.me, seenByMe: true)
        let choosing = Fixture.state(Fixture.game(.choosingOpening, turn: Fixture.me, stories: 1), current: named)
        var otherGame = StoryChainPendingWork.none
        otherGame.starts = [Fixture.queuedStart(game: UUID())]
        let started = Fixture.state(
            Fixture.game(.writing, turn: Fixture.me, current: Fixture.nextStoryID, stories: 2),
            current: Fixture.story(.writing, id: Fixture.nextStoryID, number: 2, starter: Fixture.me),
            previous: named
        )
        var known = StoryChainPendingWork.none
        known.starts = [Fixture.queuedStart()]

        let resolution = resolve(started, pending: known)

        #expect(phase(choosing, pending: otherGame) == .chooseOpening)
        #expect(resolution.phase == .writing)
        #expect(resolution.story?.isOnlyOnThisPhone == false)
        #expect(resolution.story?.story.storyNumber == 2)
    }

    @Test func aNameAndTheNextStartQueuedTogetherLeaveThePersonOnTheNewStory() {
        let story = Fixture.story(.titling, starter: Fixture.me, lines: Fixture.lines(8, starter: Fixture.me))
        let state = Fixture.state(Fixture.game(.titling, turn: Fixture.me), current: story)
        var pending = StoryChainPendingWork.none
        pending.names = [StoryChainQueuedName(storyID: Fixture.storyID, title: "Night bus")]
        pending.starts = [Fixture.queuedStart()]
        pending.lines = [Fixture.queuedLine(story: Fixture.nextStoryID)]

        let resolution = resolve(state, pending: pending)

        // The named story is seen, so no reveal comes first.
        #expect(resolution.phase == .waitingForLine)
        #expect(resolution.story?.id == Fixture.nextStoryID)
        #expect(resolution.story?.story.storyNumber == 2)
        #expect(resolution.story?.story.lines.count == 1)
    }

    @Test func aQueuedLineForAStoryThatIsNoLongerBeingWrittenIsIgnored() {
        let story = Fixture.story(.titling, starter: Fixture.me, lines: Fixture.lines(8, starter: Fixture.me))
        let state = Fixture.state(Fixture.game(.titling, turn: Fixture.me), current: story)
        var pending = StoryChainPendingWork.none
        pending.lines = [Fixture.queuedLine()]

        let resolution = resolve(state, pending: pending)

        #expect(resolution.phase == .naming)
        #expect(resolution.story?.story.lines.count == 8)
    }

    // MARK: Waiting to send

    @Test func onlyQueuedMovesCountAsWaitingToSend() {
        let state = Fixture.state(Fixture.game(.choosingOpening, turn: Fixture.partner, current: nil, stories: 0))
        var marks = StoryChainPendingWork.none
        marks.seenStoryIDs = [UUID()]
        var move = StoryChainPendingWork.none
        move.names = [StoryChainQueuedName(storyID: UUID(), title: "Night bus")]

        #expect(!resolve(state).isWaitingToSend)
        #expect(!resolve(state, pending: marks).isWaitingToSend)
        #expect(resolve(state, pending: move).isWaitingToSend)
        #expect(marks.hasMoveWaiting == false)
        #expect(marks.isEmpty == false)
        #expect(move.hasMoveWaiting)
        #expect(StoryChainPendingWork.none.isEmpty)
    }

    // MARK: Live role

    @Test func theLiveRoleFollowsThePhase() {
        let cases: [(StoryChainPhase, WidgetLivePresence.Role)] = [
            (.writing, .drawing),
            (.waitingForLine, .watching),
            (.chooseOpening, .choosing),
            (.naming, .choosing),
            (.finished(storyID: Fixture.storyID), .result),
            (.loading, .present),
            (.needsSetup, .present),
            (.preparing, .present),
            (.waitingForOpening, .present),
            (.waitingForName, .present),
            (.waitingToSync, .present),
        ]

        for (phase, role) in cases {
            #expect(StoryChainResolver.liveRole(for: phase) == role)
        }
    }
}
