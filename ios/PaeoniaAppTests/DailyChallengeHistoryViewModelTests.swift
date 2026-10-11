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

        guard case let .content(content) = viewModel.state else {
            Issue.record("Expected content state, got \(viewModel.state)")
            return
        }
        #expect(content.days.map(\.localDate) == [Self.day2])
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

        guard case let .content(content) = viewModel.state else {
            Issue.record("Expected content state, got \(viewModel.state)")
            return
        }
        #expect(content.days.map(\.localDate) == [Self.day1])
        #expect(viewModel.isPresentationReady)
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

        guard case let .content(content) = viewModel.state else {
            Issue.record("Expected content state, got \(viewModel.state)")
            return
        }
        #expect(content.days.map(\.localDate) == [Self.day1])
    }

    // MARK: - Waiting section

    @MainActor
    @Test func pendingPartnerQuestionsRefreshWithoutFetchingHistoryAgain() async {
        let completed = makeQuestion(localDate: Self.day1)
        let first = makePendingQuestion(slot: 1, partnerAnsweredAt: HistoryTestIDs.answerDate)
        let second = makePendingQuestion(
            slot: 2,
            partnerAnsweredAt: HistoryTestIDs.answerDate.addingTimeInterval(3_600)
        )
        var pending = [first]
        let service = GatedHistoryService(immediateResult: [completed])
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: HistoryTestIDs.currentUser,
            pendingPartnerQuestions: { pending }
        )

        await viewModel.load()
        #expect(pendingIDs(viewModel) == [first.id])

        // The partner answers another question while the history is open.
        pending = [first, second]
        viewModel.refreshPendingPartnerQuestions()
        #expect(pendingIDs(viewModel) == [second.id, first.id])

        // A question that is already in the completed days never shows as waiting too.
        pending = [first, completed]
        viewModel.refreshPendingPartnerQuestions()
        #expect(pendingIDs(viewModel) == [first.id])

        pending = []
        viewModel.refreshPendingPartnerQuestions()
        #expect(pendingIDs(viewModel) == [UUID]())

        guard case let .content(content) = viewModel.state else {
            Issue.record("Expected the completed days to stay, got \(viewModel.state)")
            return
        }
        #expect(content.days.map(\.localDate) == [Self.day1])
        #expect(await service.loadHistoryCount == 1)
    }

    @MainActor
    @Test func pendingPartnerQuestionsRefreshMovesBetweenEmptyAndContent() async {
        let waiting = makePendingQuestion(slot: 1, partnerAnsweredAt: HistoryTestIDs.answerDate)
        var pending: [DailyChallengeQuestion] = []
        let service = GatedHistoryService(immediateResult: [])
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: HistoryTestIDs.currentUser,
            pendingPartnerQuestions: { pending }
        )

        // Before the first load settles there is nothing to refresh.
        pending = [waiting]
        viewModel.refreshPendingPartnerQuestions()
        #expect(viewModel.state == .loading)

        pending = []
        await viewModel.load()
        #expect(viewModel.state == .empty)

        pending = [waiting]
        viewModel.refreshPendingPartnerQuestions()
        #expect(pendingIDs(viewModel) == [waiting.id])

        pending = []
        viewModel.refreshPendingPartnerQuestions()
        #expect(viewModel.state == .empty)
        #expect(await service.loadHistoryCount == 1)
    }

    @MainActor
    private func pendingIDs(_ viewModel: DailyChallengeHistoryViewModel) -> [UUID]? {
        guard case let .content(content) = viewModel.state else { return nil }
        return content.pendingPartnerQuestions.map(\.id)
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

/// A question the partner answered that the current user has not answered yet.
private func makePendingQuestion(slot: Int, partnerAnsweredAt: Date) -> DailyChallengeQuestion {
    makeQuestion(
        localDate: "2026-06-27",
        slot: slot,
        origin: .partner,
        ownAnsweredAt: nil,
        partnerAnsweredAt: partnerAnsweredAt
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
    private var gates: [Int: CheckedContinuation<[DailyChallengeQuestion], Error>] = [:]
    private(set) var loadHistoryCount = 0

    init(immediateResult: [DailyChallengeQuestion]? = nil) {
        self.immediateResult = immediateResult
    }

    func loadHistory(currentUserID _: UUID) async throws -> [DailyChallengeQuestion] {
        let call = loadHistoryCount
        loadHistoryCount += 1
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
