import Foundation
import Testing
@testable import PaeoniaApp

/// The live room: the partner's draft as a ghost, a line sent live, the lines
/// that write themselves in, and the draft this phone sends.
@MainActor
struct StoryChainViewModelLiveTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    private func draftMessage(
        story: UUID = Fixture.storyID,
        number: Int = 2,
        text: String = "The door",
        isLast: Bool = false
    ) -> StoryChainLiveMessage {
        StoryChainLiveMessage(story: story, number: number, text: text, isLast: isLast)
    }

    // MARK: The partner's draft

    @Test func theWatcherSeesOverflowAndItsRemovalThroughTheLiveChannel() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        let atLimit = String(repeating: "a", count: 240)

        environment.connection.receive(draftMessage(text: atLimit + " too long"))

        #expect(viewModel.page.ghost?.text == atLimit + " too long")
        let overflow = StoryChainParagraph.segments(for: viewModel.page).filter { $0.role == .ghostOverflow }
        #expect(overflow.map(\.string) == [" too long"])

        environment.connection.receive(draftMessage(text: atLimit))

        #expect(viewModel.page.ghost?.text == atLimit)
        #expect(!StoryChainParagraph.segments(for: viewModel.page).contains { $0.role == .ghostOverflow })
    }

    @Test func aDraftAboutAnotherStoryOrLineIsIgnored() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        environment.connection.receive(draftMessage(story: UUID()))
        #expect(viewModel.page.ghost == nil)
        environment.connection.receive(draftMessage(number: 1))
        #expect(viewModel.page.ghost == nil)
        environment.connection.receive(draftMessage(number: 3))
        #expect(viewModel.page.ghost == nil)
        environment.connection.receive(draftMessage(number: 2))
        #expect(viewModel.page.ghost != nil)
    }

    // MARK: A line sent live

    /// The partner's phone sent line 2 live, and Convex has not delivered it.
    private func receiveLiveLine(_ lineID: UUID, in environment: Env, showDraft: Bool = true) {
        if showDraft {
            environment.connection.receive(draftMessage(text: "It opened onto a garden."))
        }
        environment.connection.receive(StoryChainLiveMessage(
            story: Fixture.storyID,
            number: 2,
            text: "It opened onto a garden.",
            isLast: false,
            lineID: lineID,
            sent: true
        ))
    }

    @Test func aLineWatchedLiveSettlesBeforeConvexWithoutReplaying() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        let lineID = UUID()

        receiveLiveLine(lineID, in: environment)

        #expect(viewModel.phase == .waitingForLine)
        #expect(viewModel.page.lines.count == 2)
        let live = viewModel.page.lines.last
        #expect(live?.id == lineID)
        #expect(live?.text == "It opened onto a garden.")
        #expect(live?.number == 2)
        #expect(live?.isMine == false)
        #expect(live?.authorName == "Robin")
        #expect(viewModel.page.ghost == nil)
        #expect(viewModel.page.arrivingLineID == nil)
        viewModel.stop()
    }

    @Test(arguments: [false, true])
    func aWatchedLineDoesNotReplayRegardlessOfWhichConfirmationArrivesFirst(convexFirst: Bool) async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        let lineID = UUID()
        environment.connection.receive(draftMessage(text: "It opened onto a garden."))
        if !convexFirst {
            receiveLiveLine(lineID, in: environment, showDraft: false)
        }

        let convex = Env.writing(
            turn: Fixture.me,
            lines: [
                Env.line(1, by: Fixture.me),
                Env.line(2, by: Fixture.partner, text: "It opened onto a garden.", id: lineID),
            ],
            version: 2
        )
        await environment.cache.saveState(convex, ownerUserID: Fixture.me)
        await viewModel.reload()

        #expect(viewModel.phase == .writing)
        #expect(viewModel.page.lines.map(\.id).last == lineID)
        #expect(viewModel.page.lines.count == 2)
        #expect(viewModel.page.arrivingLineID == nil)
        #expect(viewModel.bottomPhase == .writing)

        if convexFirst {
            receiveLiveLine(lineID, in: environment, showDraft: false)
        }
        await viewModel.reload()
        #expect(viewModel.page.arrivingLineID == nil)
        viewModel.stop()
    }

    @Test func aLiveSubmissionWithoutAVisibleDraftStillWritesIn() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        let lineID = UUID()

        receiveLiveLine(lineID, in: environment, showDraft: false)

        #expect(viewModel.page.lines.last?.id == lineID)
        #expect(viewModel.page.arrivingLineID == lineID)
        viewModel.stop()
    }

    @Test func aWatchedLineDoesNotReplayAfterAPauseInTyping() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        let lineID = UUID()
        environment.connection.receive(draftMessage())
        environment.clock.advance(by: StoryChainViewModel.draftLifetime + 1)
        viewModel.recompute()
        #expect(viewModel.page.ghost == nil)

        receiveLiveLine(lineID, in: environment, showDraft: false)

        #expect(viewModel.page.arrivingLineID == nil)
        viewModel.stop()
    }

    @Test func aLineReceivedInTheBackgroundWritesInOnReturn() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        environment.connection.receive(draftMessage())
        viewModel.scenePhaseChanged(isActive: false)
        let lineID = UUID()
        let convex = Env.writing(
            turn: Fixture.me,
            lines: [Env.line(1, by: Fixture.me), Env.line(2, by: Fixture.partner, id: lineID)],
            version: 2
        )
        await environment.cache.saveState(convex, ownerUserID: Fixture.me)
        await viewModel.reload()
        #expect(viewModel.page.arrivingLineID == nil)

        viewModel.scenePhaseChanged(isActive: true)

        #expect(viewModel.page.arrivingLineID == lineID)
        viewModel.stop()
    }

    @Test func aSentLineThatConvexAlreadyHasMovesNothing() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        let lineID = UUID()
        let convex = Env.writing(
            turn: Fixture.me,
            lines: [Env.line(1, by: Fixture.me), Env.line(2, by: Fixture.partner, id: lineID)],
            version: 2
        )
        await environment.cache.saveState(convex, ownerUserID: Fixture.me)
        await viewModel.reload()
        viewModel.arrivalFinished(lineID: lineID)

        environment.connection.receive(StoryChainLiveMessage(
            story: Fixture.storyID,
            number: 2,
            text: "Line 2.",
            isLast: false,
            lineID: lineID,
            sent: true
        ))

        #expect(viewModel.page.lines.count == 2)
        #expect(viewModel.page.arrivingLineID == nil)
        viewModel.stop()
    }

    @Test func aSentLineForAnotherStoryOrLineIsIgnored() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        for (story, number) in [(UUID(), 2), (Fixture.storyID, 3), (Fixture.storyID, 1)] {
            environment.connection.receive(StoryChainLiveMessage(
                story: story,
                number: number,
                text: "Not for this page.",
                isLast: false,
                lineID: UUID(),
                sent: true
            ))
        }

        #expect(viewModel.page.lines.count == 1)
        #expect(viewModel.page.arrivingLineID == nil)
    }
}
