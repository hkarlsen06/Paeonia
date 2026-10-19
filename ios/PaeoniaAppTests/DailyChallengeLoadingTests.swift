import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeLoadingTests {
    @Test func serviceUsesSnapshotAnswerDetailsWithoutPerDayDetailFetches() async throws {
        let currentAnswerID = UUID()
        let previousAnswerID = UUID()
        let previousStart = TestDailyChallengeIDs.startsAt.addingTimeInterval(-86_400)
        let previousEnd = TestDailyChallengeIDs.startsAt
        let rows = [
            dailyQuestionRow(
                slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, status: "answered",
                ownAnswerID: currentAnswerID, ownAnsweredAt: TestDailyChallengeIDs.answerDate, isCurrentDay: true
            ),
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay, localDate: "2026-06-26", startsAt: previousStart,
                endsAt: previousEnd, slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered", ownAnswerID: previousAnswerID, ownAnsweredAt: previousStart.addingTimeInterval(600),
                isCurrentDay: false
            ),
        ]
        let gateway = RecordingDailyChallengeReadGateway(
            rows: rows,
            detailsByCoupleDayID: [
                TestDailyChallengeIDs.coupleDay: [
                    dailyAnswerDetail(answerID: currentAnswerID, isOwnAnswer: true, textBody: "Today"),
                ],
                TestDailyChallengeIDs.previousCoupleDay: [
                    dailyAnswerDetail(answerID: previousAnswerID, isOwnAnswer: true, textBody: "Yesterday"),
                ],
            ]
        )
        let service = DailyChallengeService(gateway: gateway, locale: Locale(identifier: "en_US"))

        let result = try await service.loadToday(currentUserID: TestDailyChallengeIDs.currentUser)

        #expect(await gateway.todaySnapshotLoadCount == 1)
        #expect(await gateway.loadedAnswerDetailCoupleDayIDs.isEmpty)
        #expect(result.snapshot.visibleQuestions.map { $0.ownAnswerDetail?.textBody } == [
            "Today",
            "Yesterday",
        ])
        #expect(result.snapshot.ownQuestionsForReadOverview.map { $0.ownAnswerDetail?.textBody } == ["Today"])
    }

    @MainActor
    @Test func cancelledLoadDoesNotSurfaceAnError() async throws {
        // A superseded or torn-down load reports `URLError.cancelled` (-999), not
        // Swift's `CancellationError`. It must be swallowed silently — never shown as
        // the "we couldn't load today's question" banner over otherwise-fine content.
        let service = RecordingDailyChallengeService(
            snapshots: [],
            loadError: URLError(.cancelled)
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)

        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func overlappingReloadsShareTheInFlightLoad() async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let loadProbe = DailyChallengeSyncNudgeProbe()
        let service = RecordingDailyChallengeService(
            snapshots: [snapshot],
            loadProbe: loadProbe
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        let configureTask = Task { await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser) }
        while await service.loadCount == 0 {
            await Task.yield()
        }

        let reloadTask = Task { await viewModel.reload() }
        await Task.yield()

        #expect(await service.loadCount == 1)

        await loadProbe.release()
        await configureTask.value
        await reloadTask.value

        #expect(await service.loadCount == 1)
        #expect(viewModel.snapshot.hasAnyQuestions)
    }

    @MainActor
    @Test func refreshFailureWithExistingContentKeepsStateWithoutBanner() async throws {
        // A manual refresh can lose the network after the app already has a valid
        // challenge on screen. Keep that last-known state and log the failure, but do
        // not show an error banner over usable content.
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(
            snapshots: [snapshot],
            loadErrorsByAttempt: [2: URLError(.networkConnectionLost)]
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        await viewModel.reload()

        #expect(viewModel.snapshot == snapshot)
        #expect(viewModel.notice == nil)
        #expect(await service.loadCount == 2)
    }
}
