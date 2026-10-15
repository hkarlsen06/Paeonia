import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DailyQuestionChatViewModelLoadTests {
    @Test func openingAnEmptyChatOfflineDoesNotReportALoadError() async {
        let fixture = ChatTestFixture()
        await fixture.gateway.setFailure(true)
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        // No thread exists yet, so nothing failed to load and the composer still works.
        #expect(viewModel.notice == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func aKnownThreadThatCannotBeLoadedReportsALoadError() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.gateway.setFailure(true)
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        #expect(viewModel.notice == .loadFailed(.other))
    }

    @Test func theEmptyStateWaitsForTheFirstLoadAndEndsEvenWhenChatIsUnavailable() async {
        let fixture = ChatTestFixture(question: makeChatQuestion(revealed: false))
        let viewModel = fixture.makeViewModel()
        #expect(viewModel.isLoading)

        await viewModel.load()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.notice == .unavailable)
    }

    @Test func aReadThatFinishesLateDoesNotReplaceNewerMessages() async throws {
        let fixture = ChatTestFixture()
        let service = PausingChatService(base: fixture.makeService())
        let viewModel = fixture.makeViewModel(service: service)
        await service.pauseNextRead()

        // The first read has the empty chat when it stops.
        let loading = Task { await viewModel.load() }
        #expect(await waitUntil { await service.isPaused })

        #expect(await viewModel.send("Hello"))
        #expect(viewModel.messages.map(\.body) == ["Hello"])
        // Let the reads that the send starts finish first, so only the paused one is left.
        try await Task.sleep(for: .milliseconds(50))
        await service.resumePausedRead()
        await loading.value

        #expect(viewModel.messages.map(\.body) == ["Hello"])
    }

    @Test func chatRejectsSendUntilPartnerAnswerIsRevealed() async throws {
        let fixture = ChatTestFixture(question: makeChatQuestion(revealed: false))
        let viewModel = fixture.makeViewModel()

        #expect(viewModel.isChatAvailable == false)
        #expect(await viewModel.send("Hello") == false)
        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        #expect(creates.isEmpty)
    }

    @Test func openingChatNeverCreatesAnEmptyThread() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        #expect(await fixture.gateway.createCallCount == 0)
        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        #expect(creates.isEmpty)
    }
}
