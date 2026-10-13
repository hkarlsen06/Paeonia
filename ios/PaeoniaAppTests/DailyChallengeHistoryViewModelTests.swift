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

        #expect(viewModel.state != .failed)
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

    // MARK: - Earlier days next to today's list

    @MainActor
    @Test func daysLeaveOutQuestionsTodaysListShows() async {
        let shown = makeQuestion(localDate: Self.day2, slot: 1)
        let kept = makeQuestion(localDate: Self.day2, slot: 2)
        let onlyShown = makeQuestion(localDate: Self.day1)
        let service = GatedHistoryService(immediateResult: [shown, kept, onlyShown])
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: HistoryTestIDs.currentUser
        )

        await viewModel.load()

        #expect(viewModel.days(excluding: []).map(\.localDate) == [Self.day2, Self.day1])

        // A question shown in today's list drops out of its day, and a day left with
        // nothing under it loses its divider.
        let days = viewModel.days(excluding: [shown.id, onlyShown.id])
        #expect(days.map(\.localDate) == [Self.day2])
        #expect(days.first?.questions.map(\.id) == [kept.id])
        #expect(await service.loadHistoryCount == 1)
    }

    @MainActor
    @Test func daysAreEmptyUntilContentLoads() async {
        let viewModel = DailyChallengeHistoryViewModel(
            service: GatedHistoryService(immediateResult: []),
            currentUserID: HistoryTestIDs.currentUser
        )

        #expect(viewModel.days(excluding: []).isEmpty)
        await viewModel.load()
        #expect(viewModel.state == .empty)
        #expect(viewModel.days(excluding: []).isEmpty)
    }

    @MainActor
    @Test func needsLoadUntilFirstLoadSettlesToContentOrEmpty() async {
        let failing = DailyChallengeHistoryViewModel(
            service: GatedHistoryService(failure: URLError(.notConnectedToInternet)),
            currentUserID: HistoryTestIDs.currentUser
        )
        #expect(failing.needsLoad)
        await failing.load()
        #expect(failing.state == .failed)
        #expect(failing.needsLoad)

        let loaded = DailyChallengeHistoryViewModel(
            service: GatedHistoryService(immediateResult: [makeQuestion(localDate: Self.day1)]),
            currentUserID: HistoryTestIDs.currentUser
        )
        await loaded.load()
        #expect(!loaded.needsLoad)

        let empty = DailyChallengeHistoryViewModel(
            service: GatedHistoryService(immediateResult: []),
            currentUserID: HistoryTestIDs.currentUser
        )
        await empty.load()
        #expect(!empty.needsLoad)
    }
}

// MARK: - Fixtures

private enum HistoryTestIDs {
    static let currentUser = UUID()
    static let partnerUser = UUID()
    static let startsAt = Date(timeIntervalSince1970: 1_782_432_000)
    static let answerDate = Date(timeIntervalSince1970: 1_782_450_000)
}

/// A question the current user answered on `localDate`.
private func makeQuestion(localDate: String, slot: Int = 1) -> DailyChallengeQuestion {
    makeQuestion(
        localDate: localDate,
        slot: slot,
        origin: .own,
        ownAnsweredAt: HistoryTestIDs.answerDate,
        partnerAnsweredAt: nil
    )
}

private func makeQuestion(
    localDate: String,
    slot: Int,
    origin: DailyQuestionOrigin,
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
        seededForUserID: origin == .own ? HistoryTestIDs.currentUser : HistoryTestIDs.partnerUser,
        slotNumber: slot,
        status: ownAnsweredAt == nil ? .active : .answered,
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
        origin: origin,
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

/// A history service the test steers by hand. Without `immediateResult`, each
/// `loadHistory` call waits until the test finishes it with `finish(call:with:)`, so a
/// test decides which of several overlapping loads completes first. Cancelling the
/// caller finishes the call with `CancellationError`, like a real network read.
private actor GatedHistoryService: DailyChallengeServicing {
    private let immediateResult: [DailyChallengeQuestion]?
    private let immediateFailure: Error?
    private var gates: [Int: CheckedContinuation<[DailyChallengeQuestion], Error>] = [:]
    private(set) var loadHistoryCount = 0

    init(immediateResult: [DailyChallengeQuestion]? = nil, failure: Error? = nil) {
        self.immediateResult = immediateResult
        immediateFailure = failure
    }

    func loadHistory(currentUserID _: UUID) async throws -> [DailyChallengeQuestion] {
        let call = loadHistoryCount
        loadHistoryCount += 1
        if let immediateFailure { throw immediateFailure }
        if let immediateResult { return immediateResult }
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

    func loadToday(currentUserID _: UUID) async throws -> DailyChallengeLoadResult {
        throw UnusedHistoryServiceCall()
    }

    func startToday(
        currentUserID _: UUID,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult {
        throw UnusedHistoryServiceCall()
    }

    func loadStreak() async throws -> CoupleStreak {
        throw UnusedHistoryServiceCall()
    }

    func editTextAnswer(
        instanceID _: UUID,
        text _: String,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        throw UnusedHistoryServiceCall()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        throw UnusedHistoryServiceCall()
    }

    func shuffleQuestion(
        currentUserID _: UUID,
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult {
        throw UnusedHistoryServiceCall()
    }
}
