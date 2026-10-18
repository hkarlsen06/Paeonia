import Foundation
import Testing
@testable import PaeoniaApp

/// The lines that write themselves in: the partner's on open and while the
/// screen is open, and the one I just sent.
@MainActor
struct StoryChainViewModelArrivalTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    @Test func thePartnersNewestLineWritesInOnceWhenTheScreenOpensOnMyTurn() async {
        let viewModel = Env.myTurnAfterPartner().viewModel()

        await viewModel.start()
        let lineID = viewModel.page.lines.last?.id
        #expect(lineID != nil)
        #expect(viewModel.page.arrivingLineID == lineID)
        #expect(viewModel.page.arrivalPace == .partner)
        // The line arrived before the screen opened, so the composer does not wait for it.
        #expect(viewModel.bottomPhase == .writing)

        viewModel.arrivalFinished(lineID: lineID ?? UUID())
        #expect(viewModel.page.arrivingLineID == nil)

        // The same line does not write in again when the screen opens again.
        viewModel.stop()
        await viewModel.start()
        #expect(viewModel.page.arrivingLineID == nil)
        viewModel.stop()
    }

    @Test func myOwnNewestLineDoesNotWriteInOnOpen() async {
        let viewModel = Env.waitingOnPartner().viewModel()

        await viewModel.start()

        #expect(viewModel.page.arrivingLineID == nil)
        viewModel.stop()
    }

    @Test func namingWritesInThePartnersLastLine() async {
        let viewModel = Env(state: Env.titling(turn: Fixture.me, lines: Fixture.lines(8, starter: Fixture.me)))
            .viewModel()

        await viewModel.start()

        #expect(viewModel.phase == .naming)
        #expect(viewModel.page.arrivingLineID == viewModel.page.lines.last?.id)
        viewModel.stop()
    }

    @Test func choosingTheNextOpeningShowsNoArrival() async {
        let finished = Fixture.story(.finished, lines: Fixture.lines(3, starter: Fixture.me), seenByMe: true)
        let state = Env.state(Fixture.game(.choosingOpening, turn: Fixture.me), current: finished)
        let viewModel = Env(state: state).viewModel()

        await viewModel.start()

        #expect(viewModel.phase == .chooseOpening)
        #expect(viewModel.page.arrivingLineID == nil)
        viewModel.stop()
    }

    @Test func aPartnerLineThatAppearsWhileTheScreenIsOpenWritesIn() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        #expect(viewModel.page.arrivingLineID == nil)
        let lineID = UUID()

        let convex = Env.writing(
            turn: Fixture.me,
            lines: [Env.line(1, by: Fixture.me), Env.line(2, by: Fixture.partner, id: lineID)],
            version: 2
        )
        await environment.cache.saveState(convex, ownerUserID: Fixture.me)
        await viewModel.reload()

        #expect(viewModel.phase == .writing)
        #expect(viewModel.page.arrivingLineID == lineID)
        #expect(viewModel.page.arrivalPace == .partner)
        viewModel.stop()
    }

    @Test func aClosedScreenStartsNoArrival() async {
        let viewModel = Env.myTurnAfterPartner().viewModel()

        await viewModel.reload()

        #expect(viewModel.phase == .writing)
        #expect(viewModel.page.arrivingLineID == nil)
    }

    @Test func aLineISendWritesInAtMyPace() async throws {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        viewModel.draft = "The door opened."
        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        #expect(viewModel.page.lines.last?.id == line.lineID)
        #expect(viewModel.page.arrivingLineID == line.lineID)
        #expect(viewModel.page.arrivalPace == .mine)

        viewModel.arrivalFinished(lineID: line.lineID)
        #expect(viewModel.page.arrivingLineID == nil)
    }

    @Test func aLeftScreenForgetsTheLineThatWasWritingIn() async {
        let viewModel = Env.myTurnAfterPartner().viewModel()
        await viewModel.start()
        #expect(viewModel.page.arrivingLineID != nil)

        viewModel.stop()
        viewModel.recompute()

        #expect(viewModel.page.arrivingLineID == nil)
    }
}
