import Foundation
import Testing
@testable import PaeoniaApp

/// Naming a finished story, the reveal, and the other partner's way past it.
@MainActor
struct StoryChainViewModelNamingTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    // MARK: Naming

    /// Eight lines. I wrote 1, 3, 5 and 7, the partner wrote the last, and two
    /// lines dared the next.
    private func titlingState() -> RemoteStoryChainState {
        var lines = Fixture.lines(8, starter: Fixture.me)
        lines[0] = Env.line(1, by: Fixture.me, text: "She took the night bus.", dare: "anchor")
        lines[1] = Env.line(2, by: Fixture.partner, text: "An anchor hung on the door.")
        lines[2] = Env.line(3, by: Fixture.me, text: "Nobody answered.", dare: "lamp")
        lines[3] = Env.line(4, by: Fixture.partner, text: "Then the lamp flickered.")
        return Env.titling(turn: Fixture.me, lines: lines)
    }

    @Test func aTitleMustBeOneToFortyCharacters() async {
        let viewModel = Env(state: titlingState()).viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .naming)

        let titles = [
            ("", false),
            ("   ", false),
            ("The night bus", true),
            (String(repeating: "x", count: 40), true),
            (String(repeating: "x", count: 41), false),
        ]
        for (title, canName) in titles {
            viewModel.titleDraft = title
            #expect(viewModel.canName == canName)
        }
    }

    @Test func namingQueuesTheTitleAndShowsTheRevealUntilContinue() async throws {
        let environment = Env(state: titlingState())
        let viewModel = environment.viewModel()
        await viewModel.reload()

        viewModel.titleDraft = "  The night  bus "
        await viewModel.nameStory()

        let name = try #require(await environment.queuedNames().first)
        #expect(name == StoryChainQueuedName(storyID: Fixture.storyID, title: "The night bus"))
        // The resolver already moved on to the next opening. The reveal stays.
        #expect(viewModel.phase == .finished(storyID: Fixture.storyID))
        #expect(viewModel.finished == StoryChainFinishedStory(
            storyID: Fixture.storyID,
            storyNumber: 1,
            title: "The night bus",
            finishedAt: GameFixture.now,
            lineCount: 8,
            dareCount: 2,
            isNamer: true
        ))

        // A tick or another read keeps it, and the date does not move.
        environment.clock.advance(by: 60)
        viewModel.recompute()
        await viewModel.reload()
        #expect(viewModel.phase == .finished(storyID: Fixture.storyID))
        #expect(viewModel.finished?.finishedAt == GameFixture.now)

        await viewModel.continueFromFinished()
        #expect(viewModel.phase == .chooseOpening)
        #expect(viewModel.finished == nil)
        #expect(viewModel.titleDraft.isEmpty)
        // The name already marked the story as seen.
        #expect(await environment.queuedSeenMarks().isEmpty)
    }

    @Test func namingNeedsAValidTitle() async {
        let environment = Env(state: titlingState())
        let viewModel = environment.viewModel()
        await viewModel.reload()

        await viewModel.nameStory()
        viewModel.titleDraft = String(repeating: "x", count: 41)
        await viewModel.nameStory()

        #expect(await environment.queuedNames().isEmpty)
        #expect(viewModel.phase == .naming)
    }

    @Test func whilePartnerNamesTheStoryThereIsNothingToName() async {
        let theirs = Env(state: Env.titling(turn: Fixture.partner, lines: Fixture.lines(8, starter: Fixture.partner)))
        let viewModel = theirs.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .waitingForName)
        #expect(!viewModel.canName)
    }

    // MARK: The other partner's reveal

    @Test func thePartnerWhoDidNotNameItSeesTheRevealAndContinueQueuesASeenMark() async throws {
        // The partner named the story and starts the next one. I wrote the last line.
        let finished = Fixture.story(
            .finished,
            lines: Fixture.lines(8, starter: Fixture.partner),
            titledBy: Fixture.partner,
            seenByMe: false
        )
        let state = Env.state(Fixture.game(.choosingOpening, turn: Fixture.partner), current: finished)
        let environment = Env(state: state)
        let viewModel = environment.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .finished(storyID: Fixture.storyID))
        let reveal = try #require(viewModel.finished)
        #expect(!reveal.isNamer)
        #expect(reveal.title == "The night bus")
        #expect(reveal.lineCount == 8)

        await viewModel.continueFromFinished()

        #expect(await environment.queuedSeenMarks() == [Fixture.storyID])
        #expect(viewModel.phase == .waitingForOpening)
        #expect(viewModel.finished == nil)
    }
}
