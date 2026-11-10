import Foundation
import Testing
@testable import PaeoniaApp

struct DailyChallengeHistoryViewModelTests {
    private static let day1 = "2026-06-25"
    private static let day2 = "2026-06-26"

    // MARK: - Overlapping loads

    @MainActor
    @Test func newerLoadKeepsItsResultWhenOlderLoadFinishesLast() async {
        let service = GatedHistoryService()
        let older = makeQuestion(localDate: Self.day1)
        let newer = makeQuestion(localDate: Self.day2)
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: HistoryTestIDs.currentUser
        )

        let olderLoad = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 1 }
        let newerLoad = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 2 }

        await service.finish(call: 1, with: .success([newer]))
        await newerLoad.value
        await service.finish(call: 0, with: .success([older]))
        await olderLoad.value

        guard case let .content(days) = viewModel.state else {
            Issue.record("Expected content state, got \(viewModel.state)")
            return
        }
        #expect(days.map(\.localDate) == [Self.day2])
    }

    @MainActor
    @Test func olderLoadFailingAfterNewerLoadSucceededKeepsContentAndShowsNoBanner() async {
        let service = GatedHistoryService()
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: HistoryTestIDs.currentUser
        )

        let olderLoad = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 1 }
        let newerLoad = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 2 }

        await service.finish(call: 1, with: .success([makeQuestion(localDate: Self.day2)]))
        await newerLoad.value
        await service.finish(call: 0, with: .failure(URLError(.timedOut)))
        await olderLoad.value

        #expect(viewModel.state != .failed(.other))
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func cancelledFirstLoadLeavesLoadingUntilTheNextLoadSettlesIt() async {
        let service = GatedHistoryService()
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: HistoryTestIDs.currentUser
        )

        let firstLoad = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 1 }
        firstLoad.cancel()
        await firstLoad.value

        // A cancelled load is not a failure: no error state, no banner, and the screen
        // keeps its loading surface until another load runs.
        #expect(viewModel.state == .loading)
        #expect(viewModel.notice == nil)

        let reload = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 2 }
        await service.finish(call: 1, with: .success([makeQuestion(localDate: Self.day1)]))
        await reload.value

        guard case let .content(days) = viewModel.state else {
            Issue.record("Expected content state, got \(viewModel.state)")
            return
        }
        #expect(days.map(\.localDate) == [Self.day1])
    }

    @MainActor
    @Test func cancelledNewerLoadDoesNotStrandTheOlderLoadsResult() async {
        let service = GatedHistoryService()
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: HistoryTestIDs.currentUser
        )

        let olderLoad = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 1 }
        let newerLoad = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 2 }
        newerLoad.cancel()
        await newerLoad.value
        #expect(viewModel.state == .loading)

        await service.finish(call: 0, with: .success([makeQuestion(localDate: Self.day1)]))
        await olderLoad.value

        guard case let .content(days) = viewModel.state else {
            Issue.record("Expected content state, got \(viewModel.state)")
            return
        }
        #expect(days.map(\.localDate) == [Self.day1])
    }

    @MainActor
    @Test func historyLoadWithoutConnectionFailsAsOffline() async {
        let service = GatedHistoryService()
        let viewModel = DailyChallengeHistoryViewModel(service: service, currentUserID: HistoryTestIDs.currentUser)
        let load = Task { await viewModel.load() }
        await waitForHistory { await service.loadHistoryCount == 1 }
        await service.finish(call: 0, with: .failure(URLError(.notConnectedToInternet)))
        await load.value
        #expect(viewModel.state == .failed(.offline))
    }
}

// MARK: - Fixtures

private enum HistoryTestIDs {
    static let currentUser = UUID()
    static let startsAt = Date(timeIntervalSince1970: 1_782_432_000)
}

/// A question the current user answered on `localDate`.
private func makeQuestion(localDate: String) -> DailyChallengeQuestion {
    makeQuestion(
        localDate: localDate,
        ownAnsweredAt: DailyChallengeHistory.parseLocalDate(localDate)?.addingTimeInterval(43_200),
        partnerAnsweredAt: nil
    )
}

private func makeQuestion(
    localDate: String,
    ownAnsweredAt: Date?,
    partnerAnsweredAt: Date?
) -> DailyChallengeQuestion {
    DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: UUID(),
        coupleID: UUID(),
        localDate: localDate,
        effectiveLocalDate: localDate,
        startsAt: HistoryTestIDs.startsAt,
        endsAt: HistoryTestIDs.startsAt.addingTimeInterval(86_400),
        status: .active,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "history_test_question",
        prompt: "What small moment made you think of us today?",
        shortPrompt: "A small moment today",
        answerKinds: [.text],
        ownAnswer: ownAnsweredAt.map { DailyQuestionAnswerSummary(id: UUID(), answeredAt: $0) },
        partnerAnswer: partnerAnsweredAt.map { DailyQuestionAnswerSummary(id: UUID(), answeredAt: $0) },
        canViewPartnerAnswer: false,
        ownAnswerDetail: nil,
        partnerAnswerDetail: nil,
        isCurrentDay: false
    )
}

/// Polls until `condition` holds, so a test can wait for a load to reach the service
/// without sleeping for a fixed time. Gives up after about two seconds and lets the
/// test's own expectations report the failure.
@MainActor
private func waitForHistory(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<400 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private struct UnusedHistoryServiceCall: Error {}

/// A history service the test steers by hand. Each `loadHistory` call waits until the
/// test finishes it with `finish(call:with:)`, so a test decides which of several
/// overlapping loads completes first. Cancelling the caller finishes the call with
/// `CancellationError`, like a real network read.
private actor GatedHistoryService: DailyChallengeServicing {
    private var gates: [Int: CheckedContinuation<[DailyChallengeQuestion], Error>] = [:]
    private(set) var loadHistoryCount = 0

    func loadHistory(currentUserID _: UUID) async throws -> [DailyChallengeQuestion] {
        let call = loadHistoryCount
        loadHistoryCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gates[call] = continuation
            }
        } onCancel: {
            Task { await self.finish(call: call, with: .failure(CancellationError())) }
        }
    }

    func finish(call: Int, with result: Result<[DailyChallengeQuestion], Error>) {
        gates.removeValue(forKey: call)?.resume(with: result)
    }

    func loadToday(currentUserID _: UUID) throws -> DailyChallengeLoadResult {
        throw UnusedHistoryServiceCall()
    }

    func startToday(
        currentUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        throw UnusedHistoryServiceCall()
    }

    func loadStreak() throws -> CoupleStreak {
        throw UnusedHistoryServiceCall()
    }

    func shuffleQuestion(
        currentUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        throw UnusedHistoryServiceCall()
    }
}
