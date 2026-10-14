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

    @Test func thePartnersDraftShowsAsAGhostOnTheNextLine() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.page.ghost == nil)

        environment.connection.receive(draftMessage(text: "The door"))
        #expect(viewModel.page.ghost == StoryChainGhost(text: "The door", isLast: false))

        // Deletions show too: the newest message wins.
        environment.connection.receive(draftMessage(text: "The do"))
        #expect(viewModel.page.ghost?.text == "The do")
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

    @Test func aDraftFadesOutAfterTenSeconds() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        environment.connection.receive(draftMessage())

        environment.clock.advance(by: 9)
        viewModel.recompute()
        #expect(viewModel.page.ghost != nil)

        environment.clock.advance(by: 2)
        viewModel.recompute()
        #expect(viewModel.page.ghost == nil)

        // A fresh message brings it back.
        environment.connection.receive(draftMessage(text: "The door opened"))
        #expect(viewModel.page.ghost?.text == "The door opened")
    }

    @Test func aGhostShowsOnlyWhileThePartnerWritesTheNextLine() async {
        // My turn to write: the partner's old draft for this line is not a ghost.
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .writing)

        environment.connection.receive(draftMessage())

        #expect(viewModel.page.ghost == nil)
        #expect(!viewModel.partnerIsWritingLast)
    }

    @Test func aDraftSetAsTheLastLineSaysSo() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        environment.connection.receive(draftMessage(text: "", isLast: true))
        // Nothing typed yet, so there is nothing to draw, but the status line knows.
        #expect(viewModel.page.ghost == nil)
        #expect(viewModel.partnerIsWritingLast)

        environment.connection.receive(draftMessage(text: "And so it ended", isLast: true))
        #expect(viewModel.page.ghost == StoryChainGhost(text: "And so it ended", isLast: true))
        #expect(viewModel.partnerIsWritingLast)

        environment.connection.receive(draftMessage(text: "And so it ended", isLast: false))
        #expect(!viewModel.partnerIsWritingLast)
    }

    // MARK: A line sent live

    /// The partner's phone sent line 2 live, and Convex has not delivered it.
    private func receiveLiveLine(_ lineID: UUID, in environment: Env) {
        environment.connection.receive(draftMessage(text: "It opened onto a garden."))
        environment.connection.receive(StoryChainLiveMessage(
            story: Fixture.storyID,
            number: 2,
            text: "It opened onto a garden.",
            isLast: false,
            lineID: lineID,
            sent: true
        ))
    }

    @Test func aLineSentLiveShowsBeforeConvexAndStartsToWriteIn() async {
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
        #expect(viewModel.page.arrivingLineID == lineID)
        #expect(viewModel.page.arrivalPace == .partner)
        viewModel.stop()
    }

    @Test func nothingMovesWhenConvexBringsTheLineThatWasSentLive() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        let lineID = UUID()
        receiveLiveLine(lineID, in: environment)

        // The page keeps the one write-in it started.
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
        #expect(viewModel.page.arrivingLineID == lineID)

        viewModel.arrivalFinished(lineID: lineID)
        await viewModel.reload()
        #expect(viewModel.page.arrivingLineID == nil)
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
