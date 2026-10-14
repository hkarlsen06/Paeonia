import Foundation
import Testing
@testable import PaeoniaApp

/// The draft this phone sends through the live room while the person writes.
@MainActor
struct StoryChainViewModelDraftTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    private func draftMessage(text: String) -> StoryChainLiveMessage {
        StoryChainLiveMessage(story: Fixture.storyID, number: 2, text: text, isLast: false)
    }

    @Test func typingSendsTheWholeDraftAtOnce() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        viewModel.draft = "H"

        #expect(environment.connection.sentMessages == [draftMessage(text: "H")])
    }

    @Test func changesInsideTheWindowSendOnlyTheLatestDraftAfterIt() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel(liveSendInterval: .milliseconds(30))
        await viewModel.reload()

        viewModel.draft = "H"
        viewModel.draft = "He"
        viewModel.draft = "Hel"
        #expect(environment.connection.sentMessages.map(\.text) == ["H"])

        let sentLatest = await waitUntil { environment.connection.sentMessages.count == 2 }
        #expect(sentLatest)
        #expect(environment.connection.sentMessages.map(\.text) == ["H", "Hel"])
    }

    @Test func deletionsAndTheLastLineSwitchGoOutToo() async throws {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: Fixture.lines(7, starter: Fixture.partner)))
        let viewModel = environment.viewModel(liveSendInterval: .milliseconds(1))
        await viewModel.reload()

        viewModel.draft = "Hi"
        try await Task.sleep(for: .milliseconds(100))
        viewModel.draft = ""
        try await Task.sleep(for: .milliseconds(100))
        viewModel.isLastLine = true

        let messages = environment.connection.sentMessages
        #expect(messages.map(\.text) == ["Hi", "", ""])
        #expect(messages.map(\.isLast) == [false, false, true])
        #expect(messages.allSatisfy { $0.number == 8 && $0.story == Fixture.storyID })
    }

    @Test func theDraftGoesAgainWhenThePartnerArrives() async throws {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel(liveSendInterval: .milliseconds(1))
        await viewModel.reload()
        viewModel.draft = "Hello"
        try await Task.sleep(for: .milliseconds(100))
        let count = environment.connection.sentMessages.count

        environment.connection.onMessage?(WidgetLiveMessage(type: .joined, id: "partner"))

        #expect(environment.connection.sentMessages.count == count + 1)
        #expect(environment.connection.sentMessages.last?.text == "Hello")
    }

    @Test func nothingGoesOutWhileThePartnerWrites() async {
        let environment = Env.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        viewModel.draft = "I am not the writer"

        #expect(environment.connection.sentMessages.isEmpty)
    }

    @Test func sendingTheLineSendsAFinalMessageAndNothingAfterIt() async throws {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "  The door\n opened. "

        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        try await Task.sleep(for: .milliseconds(150))
        let messages = environment.connection.sentMessages
        #expect(messages.last == StoryChainLiveMessage(
            story: Fixture.storyID,
            number: 2,
            text: "The door opened.",
            isLast: false,
            lineID: line.lineID,
            sent: true
        ))
        #expect(messages.filter(\.sent).count == 1)
        // The cleared draft is not sent after the line.
        #expect(messages.dropLast().allSatisfy { !$0.sent })
    }
}
