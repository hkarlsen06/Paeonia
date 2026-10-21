import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct ThreadChatPageTests {
    @Test func preparingReadsThePhonesCopyWithoutTheNetwork() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.saveMessages(
            [fixture.remoteMessage(body: "Saved earlier")],
            ownerUserID: fixture.ownerUserID,
            subjectID: fixture.question.questionID
        )
        let viewModel = fixture.makeViewModel()

        await viewModel.prepare()

        #expect(viewModel.hasReadStore)
        #expect(viewModel.messages.map(\.body) == ["Saved earlier"])
        #expect(await fixture.gateway.loadCallCount == 0)
    }

    @Test func aReplyGoesOutWithItsTargetAndClearsTheBanner() async throws {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.saveMessages(
            [fixture.remoteMessage(body: "Earlier")],
            ownerUserID: fixture.ownerUserID,
            subjectID: fixture.question.questionID
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.prepare()
        let target = try #require(viewModel.messages.first)

        viewModel.setReplyTarget(target)
        #expect(viewModel.replyTarget == .message(target))
        #expect(await viewModel.send("Answering that"))
        #expect(viewModel.replyTarget == nil)

        let queued = try #require(
            try await fixture.queuedOperations(.sendThreadMessage)
                .first
        )
        _ = try await SendChatMessageOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        ).send(queued, context: chatSyncContext(ownerUserID: fixture.ownerUserID))
        #expect(await fixture.gateway.lastReplyTo == .message(target.id))
    }

    @Test func thePageStacksEveryDayTheServerSendsAndTakesTheThreadFromThem() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let earlierID = UUID()
        await fixture.gateway.setRounds(try decodedChatRounds(
            threadID: fixture.threadID,
            rounds: [
                // The fixture's question begins in 1970, so the earlier day is older still.
                ChatRoundDay(instance: earlierID, date: "1960-03-03", startsAt: "1960-03-03T00:00:00.000Z"),
                ChatRoundDay(instance: fixture.question.id, date: "1970-01-01", startsAt: "1970-01-01T00:00:01.000Z"),
            ],
            user: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            subjectID: fixture.question.questionID
        ))

        #expect(viewModel.rounds.map(\.id) == [fixture.question.id])
        await viewModel.load()

        #expect(viewModel.rounds.map(\.id) == [earlierID, fixture.question.id])
        #expect(viewModel.threadID == fixture.threadID)
        #expect(viewModel.chatRounds().count == 2)
    }

    @Test func aHiddenPartnerAnswerStaysOutAndThePageSaysWhoItWaitsFor() {
        let fixture = ChatTestFixture(question: makeChatQuestion(revealed: false))
        let viewModel = fixture.makeViewModel()

        let round = viewModel.chatRounds().first
        #expect(round?.answers.map(\.isOwnAnswer) == [true])
        #expect(!viewModel.isChatAvailable)
        #expect(round?.waiting == .reveal)
    }
}
