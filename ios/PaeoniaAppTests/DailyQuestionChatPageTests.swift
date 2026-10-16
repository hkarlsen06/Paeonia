import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DailyQuestionChatPageTests {
    @Test func theConversationOpensWithBothAnswersOldestFirst() {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()

        let round = viewModel.chatRounds().first
        #expect(viewModel.chatRounds().count == 1)
        #expect(round?.answers.count == 2)
        #expect(round?.answers.map(\.answeredAt) == round?.answers.map(\.answeredAt).sorted())
        #expect(round?.waiting == nil)
    }

    @Test func thePageKnowsWhenItHasReadThePhonesCopyOfTheChat() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let viewModel = fixture.makeViewModel()
        #expect(!viewModel.hasReadStore)

        await viewModel.load()

        #expect(viewModel.hasReadStore)
        #expect(viewModel.messages.isEmpty)
    }

    @Test func preparingReadsThePhonesCopyWithoutTheNetwork() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.saveMessages(
            [fixture.remoteMessage(body: "Saved earlier")],
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID
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
            questionID: fixture.question.questionID
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.prepare()
        let target = try #require(viewModel.messages.first)

        viewModel.setReplyTarget(target)
        #expect(viewModel.replyTarget?.id == target.id)
        #expect(await viewModel.send("Answering that"))
        #expect(viewModel.replyTarget == nil)

        let queued = try #require(
            try await fixture.queuedOperations(.sendThreadMessage)
                .first
        )
        _ = try await SendDailyChatMessageOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        ).send(queued, context: chatSyncContext(ownerUserID: fixture.ownerUserID))
        #expect(await fixture.gateway.lastReplyToMessageID == target.id)
    }

    @Test func aMessageStillSendingCannotBeRepliedTo() {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let sending = DailyQuestionChatMessage(
            id: UUID(), threadID: nil, questionID: fixture.question.questionID, senderUserID: fixture.ownerUserID,
            body: "Hi", createdAt: .now, clientOperationID: UUID(), isSending: true
        )

        viewModel.setReplyTarget(sending)

        #expect(viewModel.replyTarget == nil)
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
            questionID: fixture.question.questionID
        ))

        #expect(viewModel.rounds.map(\.id) == [fixture.question.id])
        await viewModel.load()

        #expect(viewModel.rounds.map(\.id) == [earlierID, fixture.question.id])
        #expect(viewModel.threadID == fixture.threadID)
        #expect(viewModel.chatRounds().count == 2)
    }

    @Test func aPageOpenedOnAnEarlierDayScrollsToItAndTheNewestDayIsTheDefault() async throws {
        let fixture = ChatTestFixture()
        let newestID = UUID()
        await fixture.gateway.setRounds(try decodedChatRounds(
            threadID: nil,
            rounds: [
                ChatRoundDay(instance: fixture.question.id, date: "1970-01-01", startsAt: "1970-01-01T00:00:01.000Z"),
                ChatRoundDay(instance: newestID, date: "2026-10-09", startsAt: "2026-10-09T00:00:00.000Z"),
            ],
            user: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            questionID: fixture.question.questionID
        ))
        let focusedOnEarlier = fixture.makeViewModel()
        await focusedOnEarlier.load()
        let focusedOnNewest = fixture.makeViewModel(focusesNewest: true)
        await focusedOnNewest.load()

        #expect(focusedOnEarlier.openingScroll == .oldestRow)
        #expect(focusedOnNewest.openingScroll == .questionRow(newestID))
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
