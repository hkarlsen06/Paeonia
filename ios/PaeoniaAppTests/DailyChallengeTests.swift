import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

/// Builds a UUID from a fixed string for deterministic fixtures without force
/// unwrapping (the literals are always valid, so the fallback never runs).
private func fixedUUID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}

struct DailyChallengeMappingTests {
    @MainActor
    @Test func noChallengeYetProducesEmptySnapshotAndHomeState() async throws {
        let service = RecordingDailyChallengeService(snapshots: [
            .empty(currentUserID: TestDailyChallengeIDs.currentUser),
        ])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)

        #expect(!viewModel.snapshot.hasAnyQuestions)
        #expect(viewModel.homeCardState.kind == .noChallenge)
    }

    @MainActor
    @Test func reloadClearsCompletedChallengeWhenNewDayHasNoStartedQuestions() async throws {
        let completedSnapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            questionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            questionRow(
                slotNumber: 3,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
        ])
        let service = RecordingDailyChallengeService(
            snapshots: [
                completedSnapshot,
                .empty(currentUserID: TestDailyChallengeIDs.currentUser),
            ],
            advancesSnapshotsOnLoad: true
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(viewModel.homeCardState.kind == .complete)

        await viewModel.reload()

        #expect(!viewModel.snapshot.hasAnyQuestions)
        #expect(viewModel.homeCardState.kind == .noChallenge)
    }

    @Test func unansweredOwnQuestionsAreVisibleAndAnswerable() {
        let snapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])

        #expect(snapshot.ownQuestions.count == 3)
        #expect(snapshot.partnerStartedQuestions.isEmpty)
        #expect(snapshot.progress.ownAnsweredCount == 0)
        #expect(snapshot.ownQuestions.allSatisfy { $0.canSubmitTextAnswer })
    }

    @Test func currentUserAnsweredQuestionCountsTowardProgress() {
        let answerID = fixedUUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
                questionRow(slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser),
                questionRow(slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser),
            ],
            details: [
                answerDetail(answerID: answerID, isOwnAnswer: true, textBody: "I thought of us at lunch."),
            ]
        )

        #expect(snapshot.progress.ownAnsweredCount == 1)
        #expect(snapshot.ownQuestions[0].hasOwnAnswer)
        #expect(!snapshot.ownQuestions[0].canSubmitTextAnswer)
        #expect(snapshot.ownQuestions[0].ownAnswerDetail?.textBody == "I thought of us at lunch.")
    }

    @Test func partnerAnsweredUnrevealedQuestionCanBeAnsweredButBodyStaysHidden() throws {
        let partnerAnswerID = fixedUUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                answerKinds: [.voice, .text],
                partnerAnswerID: partnerAnswerID,
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                canViewPartnerAnswer: false
            ),
        ])

        let question = try #require(snapshot.partnerStartedQuestions.first)

        #expect(question.origin == .partner)
        #expect(question.hasPartnerAnswer)
        #expect(question.canSubmitTextAnswer)
        #expect(!question.canViewPartnerAnswer)
        #expect(question.partnerAnswerDetail == nil)
    }

    @Test func bothAnsweredRevealedQuestionIncludesPartnerText() throws {
        let ownAnswerID = fixedUUID("cccccccc-cccc-cccc-cccc-cccccccccccc")
        let partnerAnswerID = fixedUUID("dddddddd-dddd-dddd-dddd-dddddddddddd")
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 2,
                    seededForUserID: TestDailyChallengeIDs.partnerUser,
                    ownAnswerID: ownAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate.addingTimeInterval(30),
                    partnerAnswerID: partnerAnswerID,
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                    canViewPartnerAnswer: true
                ),
            ],
            details: [
                answerDetail(answerID: ownAnswerID, isOwnAnswer: true, textBody: "Tomorrow morning."),
                answerDetail(
                    answerUserID: TestDailyChallengeIDs.partnerUser,
                    answerID: partnerAnswerID,
                    isOwnAnswer: false,
                    textBody: "A walk after school."
                ),
            ]
        )

        let question = try #require(snapshot.partnerStartedQuestions.first)

        #expect(question.hasOwnAnswer)
        #expect(question.canViewPartnerAnswer)
        #expect(question.partnerAnswerDetail?.canViewAnswer == true)
        #expect(question.partnerAnswerDetail?.textBody == "A walk after school.")
    }

    @Test func answerKindMappingPreservesBackendKindsAndUnknowns() {
        #expect(DailyChallengeAnswerKind(rawValue: "text") == .text)
        #expect(DailyChallengeAnswerKind(rawValue: "photo") == .photo)
        #expect(DailyChallengeAnswerKind(rawValue: "voice") == .voice)
        #expect(DailyChallengeAnswerKind(rawValue: "partner_choice") == .partnerChoice)
        #expect(DailyChallengeAnswerKind(rawValue: "sticker") == .unknown("sticker"))
        #expect(DailyChallengeAnswerKind(rawValue: "voice").rawValue == "voice")
    }

    @Test func challengeProgressUsesOnlyCurrentUsersThreeSeededQuestions() {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            questionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            questionRow(
                slotNumber: 3,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            questionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            questionRow(
                slotNumber: 3,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])

        #expect(snapshot.visibleQuestions.count == 6)
        #expect(snapshot.progress.ownQuestionCount == 3)
        #expect(snapshot.progress.ownAnsweredCount == 3)
        #expect(snapshot.progress.partnerQuestionCount == 3)
        #expect(snapshot.progress.isComplete)
        #expect(snapshot.hasPartnerAnswersForToday)
        #expect(snapshot.homeCardState.hasPartnerAnswersForToday)
        #expect(snapshot.hasAnswerablePartnerQuestions)
        #expect(snapshot.answerablePartnerQuestions.count == 3)
        #expect(snapshot.answerFlowQuestions.count == 6)
    }

    @Test func readOverviewOrdersPartnerQuestionsThenOwnQuestionsByPartnerAnswer() {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            questionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID(),
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            questionRow(
                slotNumber: 3,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID()
            ),
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            questionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                ownAnswerID: UUID(),
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
            questionRow(
                slotNumber: 3,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])

        let partnerReadQuestions = snapshot.partnerQuestionsForReadOverview
        #expect(partnerReadQuestions.map(\.slotNumber) == [1, 3, 2])
        #expect(partnerReadQuestions.prefix(2).allSatisfy { $0.isAvailableToAnswer })
        #expect(partnerReadQuestions.last?.isAvailableToAnswer == false)

        let ownReadQuestions = snapshot.ownQuestionsForReadOverview
        #expect(ownReadQuestions.map(\.slotNumber) == [2, 1, 3])
        #expect(ownReadQuestions.first?.hasPartnerAnswer == true)
    }

    @Test func readOverviewOrdersRevealedCardsByCompletionTimeNewestFirst() {
        let earlier = TestDailyChallengeIDs.answerDate
        let later = earlier.addingTimeInterval(3600)

        let snapshot = makeSnapshot(rows: [
            // The partner's questions you've answered (revealed) sort by when YOU
            // answered, newest first → slot 2 (later) before slot 1 (earlier).
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                ownAnswerID: UUID(),
                ownAnsweredAt: earlier,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: earlier,
                canViewPartnerAnswer: true
            ),
            questionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                ownAnswerID: UUID(),
                ownAnsweredAt: later,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: earlier,
                canViewPartnerAnswer: true
            ),
            // Your own questions the partner answered sort by when the PARTNER
            // answered, newest first → slot 4 (later) before slot 3 (earlier).
            questionRow(
                slotNumber: 3,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID(),
                ownAnsweredAt: earlier,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: earlier,
                canViewPartnerAnswer: true
            ),
            questionRow(
                slotNumber: 4,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID(),
                ownAnsweredAt: earlier,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: later,
                canViewPartnerAnswer: true
            ),
        ])

        #expect(snapshot.partnerQuestionsForReadOverview.map(\.slotNumber) == [2, 1])
        #expect(snapshot.ownQuestionsForReadOverview.map(\.slotNumber) == [4, 3])
    }

    @Test func carriedForwardQuestionsSortBelowCurrentDayQuestions() {
        let previousStart = TestDailyChallengeIDs.startsAt.addingTimeInterval(-86_400)
        let previousEnd = TestDailyChallengeIDs.startsAt
        let currentPartnerAnswer = TestDailyChallengeIDs.answerDate.addingTimeInterval(60)
        let olderPartnerAnswer = TestDailyChallengeIDs.answerDate.addingTimeInterval(-86_400)

        let snapshot = makeSnapshot(rows: [
            questionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay,
                localDate: "2026-06-26",
                startsAt: previousStart,
                endsAt: previousEnd,
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: olderPartnerAnswer,
                isCurrentDay: false
            ),
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: currentPartnerAnswer,
                isCurrentDay: true
            ),
            questionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay,
                localDate: "2026-06-26",
                startsAt: previousStart,
                endsAt: previousEnd,
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID(),
                ownAnsweredAt: olderPartnerAnswer,
                isCurrentDay: false
            ),
            questionRow(
                slotNumber: 2,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: UUID(),
                ownAnsweredAt: currentPartnerAnswer,
                isCurrentDay: true
            ),
        ])

        #expect(snapshot.partnerQuestionsForReadOverview.map(\.isCurrentDay) == [true, false])
        #expect(snapshot.ownQuestionsForReadOverview.map(\.isCurrentDay) == [true])
        #expect(snapshot.answerFlowQuestions.map(\.isCurrentDay) == [true, true, false])
    }

    @Test func homeCardIgnoresCarriedForwardQuestionsWhenTodayHasNotStarted() {
        let previousStart = TestDailyChallengeIDs.startsAt.addingTimeInterval(-86_400)
        let previousEnd = TestDailyChallengeIDs.startsAt

        let snapshot = makeSnapshot(rows: [
            questionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay,
                localDate: "2026-06-26",
                startsAt: previousStart,
                endsAt: previousEnd,
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: previousStart.addingTimeInterval(600),
                isCurrentDay: false
            ),
        ])

        #expect(snapshot.hasAnyQuestions)
        #expect(!snapshot.hasAnyCurrentDayQuestions)
        #expect(snapshot.partnerQuestionsForReadOverview.count == 1)
        #expect(snapshot.homeCardState.kind == .noChallenge)
    }

    @Test func answerFlowOrdersOwnQuestionsThenAnswerablePartnerQuestions() {
        let snapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser),
            // Partner's question that the partner answered: the current user can
            // still answer it, so it belongs at the end of the flow.
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.partnerUser,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])

        let flow = snapshot.answerFlowQuestions

        #expect(flow.count == 4)
        #expect(flow.prefix(3).map(\.slotNumber) == [1, 2, 3])
        #expect(flow.prefix(3).allSatisfy { $0.origin == .own })
        #expect(flow.last?.origin == .partner)
        #expect(flow.last?.isAvailableToAnswer == true)
    }

    @MainActor
    @Test func shuffleReplacesQuestionAndClearsDraft() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                promptEN: "Original question"
            ),
        ])
        let shuffledSnapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                promptEN: "A brand new question"
            ),
        ])
        let service = RecordingDailyChallengeService(
            snapshots: [baseSnapshot],
            shuffleSnapshot: shuffledSnapshot
        )
        let store = InMemoryDailyChallengeDraftStore()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: store
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let original = try #require(viewModel.snapshot.ownQuestions.first)
        viewModel.setDraftText("half-written", for: original.id)

        await viewModel.shuffle(original)

        #expect(await service.shuffledSlots == [1])
        #expect(viewModel.snapshot.ownQuestions.first?.prompt == "A brand new question")
        #expect(viewModel.draftText(for: original.id).isEmpty)
        #expect(store.drafts(for: TestDailyChallengeIDs.currentUser).isEmpty)
        #expect(viewModel.notice == nil)
        #expect(viewModel.shufflingSlotNumber == nil)
    }

    @MainActor
    @Test func refreshStreakLoadsTheCoupleStreak() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(
            snapshots: [snapshot],
            streak: CoupleStreak(
                currentCount: 5,
                longestCount: 9,
                lastQualifiedDate: "2026-06-27",
                restoreAvailable: true,
                restorableCount: 0,
                restoreDeadline: nil
            )
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        await viewModel.refreshStreak()

        #expect(viewModel.streak.currentCount == 5)
        #expect(viewModel.streak.longestCount == 9)
        #expect(viewModel.streak.lastQualifiedDate == "2026-06-27")
        #expect(await service.streakLoadCount == 1)
    }

    @Test func serviceLoadsAnswerDetailsForEveryReturnedCoupleDay() async throws {
        let currentAnswerID = UUID()
        let previousAnswerID = UUID()
        let previousStart = TestDailyChallengeIDs.startsAt.addingTimeInterval(-86_400)
        let previousEnd = TestDailyChallengeIDs.startsAt
        let rows = [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: currentAnswerID,
                ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                isCurrentDay: true
            ),
            questionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay,
                localDate: "2026-06-26",
                startsAt: previousStart,
                endsAt: previousEnd,
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                ownAnswerID: previousAnswerID,
                ownAnsweredAt: previousStart.addingTimeInterval(600),
                isCurrentDay: false
            ),
        ]
        let gateway = RecordingDailyChallengeReadGateway(
            rows: rows,
            detailsByCoupleDayID: [
                TestDailyChallengeIDs.coupleDay: [
                    answerDetail(answerID: currentAnswerID, isOwnAnswer: true, textBody: "Today"),
                ],
                TestDailyChallengeIDs.previousCoupleDay: [
                    answerDetail(answerID: previousAnswerID, isOwnAnswer: true, textBody: "Yesterday"),
                ],
            ]
        )
        let service = SupabaseDailyChallengeService(gateway: gateway, locale: Locale(identifier: "en_US"))

        let snapshot = try await service.loadToday(currentUserID: TestDailyChallengeIDs.currentUser)

        #expect(await gateway.loadedAnswerDetailCoupleDayIDs == [
            TestDailyChallengeIDs.coupleDay,
            TestDailyChallengeIDs.previousCoupleDay,
        ])
        #expect(snapshot.visibleQuestions.map { $0.ownAnswerDetail?.textBody } == [
            "Today",
            "Yesterday",
        ])
        #expect(snapshot.ownQuestionsForReadOverview.map { $0.ownAnswerDetail?.textBody } == ["Today"])
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
    @Test func realLoadFailureStillSurfacesTheErrorBanner() async throws {
        // A genuine load failure (anything other than cancellation) must still show
        // the friendly notice so the user knows to retry.
        let service = RecordingDailyChallengeService(
            snapshots: [],
            loadError: URLError(.timedOut)
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)

        #expect(viewModel.notice == .loadFailed)
    }

    @MainActor
    @Test func refreshingParticipantsUpdatesDisplayDataWithoutReloading() async throws {
        // Names and profile photos arrive/refresh after launch. Feeding them in must
        // update the rendered participants but must NOT re-fetch the questions — the
        // reason the load is keyed on the signed-in user alone (see AGENTS.md).
        let snapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(participants: DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            currentDisplayName: "You",
            partnerUserID: TestDailyChallengeIDs.partnerUser,
            partnerDisplayName: "Old partner name"
        ))
        let loadsAfterConfigure = await service.loadCount

        viewModel.refreshParticipants(DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            currentDisplayName: "You",
            currentProfilePhotoAssetID: UUID(),
            partnerUserID: TestDailyChallengeIDs.partnerUser,
            partnerDisplayName: "New partner name",
            partnerProfilePhotoAssetID: UUID()
        ))

        #expect(viewModel.participants.partnerDisplayName == "New partner name")
        #expect(viewModel.participants.partnerProfilePhotoAssetID != nil)
        // No additional load was triggered by the cosmetic change.
        #expect(await service.loadCount == loadsAfterConfigure)
    }

    @MainActor
    @Test func draftsSurviveReopenAndClearOnSubmit() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let store = InMemoryDailyChallengeDraftStore()
        let pendingStore = InMemoryPendingSyncOperationRepository()

        let first = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: store,
            pendingOperationStore: pendingStore
        )
        await first.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(first.snapshot.ownQuestions.first)
        first.setDraftText("Halfway through a thought", for: question.id)

        // Reopen / relaunch: a fresh view model restores the saved drafts.
        let second = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: store,
            pendingOperationStore: pendingStore
        )
        await second.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(second.draftText(for: question.id) == "Halfway through a thought")

        await second.submitAnswer(for: question)
        #expect(second.draftText(for: question.id).isEmpty)
        #expect(store.drafts(for: TestDailyChallengeIDs.currentUser).isEmpty)
    }

    @MainActor
    @Test func shuffleLimitSurfacesFriendlyNoticeAndKeepsQuestion() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                promptEN: "Original question"
            ),
        ])
        let service = RecordingDailyChallengeService(
            snapshots: [baseSnapshot],
            shuffleError: DailyChallengeShuffleLimitError()
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let original = try #require(viewModel.snapshot.ownQuestions.first)

        await viewModel.shuffle(original)

        #expect(viewModel.notice == .shuffleLimitReached)
        #expect(viewModel.snapshot.ownQuestions.first?.prompt == "Original question")
    }

    @MainActor
    @Test func shuffleIgnoresAlreadyAnsweredOwnQuestion() async throws {
        let answerID = UUID()
        let answeredSnapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [answerDetail(answerID: answerID, isOwnAnswer: true, textBody: "Done already.")]
        )
        let service = RecordingDailyChallengeService(snapshots: [answeredSnapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let answered = try #require(viewModel.snapshot.ownQuestions.first)

        await viewModel.shuffle(answered)

        #expect(await service.shuffledSlots.isEmpty)
        #expect(viewModel.notice == nil)
    }

    @Test func ownTextAnswerIsEditableOnlyWhilePrivate() {
        let privateAnswerID = UUID()
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: privateAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
                questionRow(
                    slotNumber: 2,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: UUID(),
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                    partnerAnswerID: UUID(),
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                    canViewPartnerAnswer: true
                ),
                questionRow(slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser),
            ],
            details: [answerDetail(answerID: privateAnswerID, isOwnAnswer: true, textBody: "Private draft")]
        )

        let own = snapshot.ownQuestions

        #expect(own[0].canEditOwnAnswer)   // answered, partner hasn't seen it
        #expect(!own[1].canEditOwnAnswer)  // revealed once partner answered
        #expect(!own[2].canEditOwnAnswer)  // not answered yet
    }

    @MainActor
    @Test func editTextAnswerSavesNewText() async throws {
        let answerID = UUID()
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [answerDetail(answerID: answerID, isOwnAnswer: true, textBody: "Old answer")]
        )
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(question.canEditOwnAnswer)

        viewModel.setDraftText("New answer", for: question.id)
        await viewModel.editTextAnswer(for: question)

        #expect(await service.editedTexts == ["New answer"])
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func editAfterPartnerAnsweredSurfacesLockedNotice() async throws {
        let answerID = UUID()
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [answerDetail(answerID: answerID, isOwnAnswer: true, textBody: "Old answer")]
        )
        let service = RecordingDailyChallengeService(
            snapshots: [snapshot],
            editError: DailyChallengeEditLockedError()
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        viewModel.setDraftText("New answer", for: question.id)

        await viewModel.editTextAnswer(for: question)

        #expect(viewModel.notice == .editLocked)
    }

    @Test func partnerChoiceAnswerIsEditableWhilePrivateButNotAfterReveal() throws {
        let privateAnswerID = UUID()
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: privateAnswerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
                questionRow(
                    slotNumber: 2,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: UUID(),
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                    partnerAnswerID: UUID(),
                    partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                    canViewPartnerAnswer: true
                ),
            ],
            details: [
                answerDetail(
                    answerID: privateAnswerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )

        let own = snapshot.ownQuestions
        #expect(own[0].editableAnswerKind == .partnerChoice)  // answered, still private
        #expect(own[0].canEditOwnAnswer)
        #expect(own[1].editableAnswerKind == nil)             // revealed once partner answered
        #expect(!own[1].canEditOwnAnswer)
    }

    @Test func sharedPartnerChoiceCollapsesOnlyWhenBothPickSamePersonWithNothingElse() throws {
        func question(
            ownSelection: UUID?,
            partnerSelection: UUID?,
            partnerCanView: Bool = true,
            ownText: String? = nil
        ) throws -> DailyChallengeQuestion {
            let ownAnswerID = UUID()
            let partnerAnswerID = UUID()
            let snapshot = makeSnapshot(
                rows: [
                    questionRow(
                        slotNumber: 1,
                        seededForUserID: TestDailyChallengeIDs.currentUser,
                        status: "answered",
                        answerKinds: [.partnerChoice],
                        ownAnswerID: ownAnswerID,
                        ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                        partnerAnswerID: partnerAnswerID,
                        partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                        canViewPartnerAnswer: partnerCanView
                    ),
                ],
                details: [
                    answerDetail(
                        answerUserID: TestDailyChallengeIDs.currentUser,
                        answerID: ownAnswerID,
                        isOwnAnswer: true,
                        textBody: ownText,
                        selectedUserID: ownSelection
                    ),
                    answerDetail(
                        answerUserID: TestDailyChallengeIDs.partnerUser,
                        answerID: partnerAnswerID,
                        isOwnAnswer: false,
                        canViewAnswer: partnerCanView,
                        selectedUserID: partnerSelection
                    ),
                ]
            )
            return try #require(snapshot.ownQuestions.first)
        }

        // Both picked the same person with nothing else: collapse into one shared row.
        #expect(
            try question(
                ownSelection: TestDailyChallengeIDs.partnerUser,
                partnerSelection: TestDailyChallengeIDs.partnerUser
            ).sharedPartnerChoiceUserID == TestDailyChallengeIDs.partnerUser
        )

        // Different picks stay as two separate rows.
        #expect(
            try question(
                ownSelection: TestDailyChallengeIDs.currentUser,
                partnerSelection: TestDailyChallengeIDs.partnerUser
            ).sharedPartnerChoiceUserID == nil
        )

        // Same pick but the partner's answer isn't viewable yet: nothing to merge.
        #expect(
            try question(
                ownSelection: TestDailyChallengeIDs.partnerUser,
                partnerSelection: TestDailyChallengeIDs.partnerUser,
                partnerCanView: false
            ).sharedPartnerChoiceUserID == nil
        )

        // Same pick but one side added a caption: the answers differ, so keep both.
        #expect(
            try question(
                ownSelection: TestDailyChallengeIDs.partnerUser,
                partnerSelection: TestDailyChallengeIDs.partnerUser,
                ownText: "Always you."
            ).sharedPartnerChoiceUserID == nil
        )
    }

    @MainActor
    @Test func editPartnerChoiceSavesNewSelection() async throws {
        let answerID = UUID()
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [
                answerDetail(
                    answerID: answerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(question.editableAnswerKind == .partnerChoice)

        // Switch the pick from the partner to "you", then save.
        viewModel.setPartnerChoice(TestDailyChallengeIDs.currentUser, for: question.id)
        await viewModel.editPartnerChoiceAnswer(for: question)

        #expect(await service.editedChoices == [TestDailyChallengeIDs.currentUser])
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func editPartnerChoiceAfterPartnerAnsweredSurfacesLockedNotice() async throws {
        let answerID = UUID()
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [
                answerDetail(
                    answerID: answerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )
        let service = RecordingDailyChallengeService(
            snapshots: [snapshot],
            editError: DailyChallengeEditLockedError()
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        viewModel.setPartnerChoice(TestDailyChallengeIDs.currentUser, for: question.id)

        await viewModel.editPartnerChoiceAnswer(for: question)

        #expect(viewModel.notice == .editLocked)
    }

    @Test func partnerChoiceOptionsCarryAvatarMetadata() throws {
        let currentPhoto = UUID()
        let partnerPhoto = UUID()
        let participants = DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            currentDisplayName: "Hjalmar",
            currentProfilePhotoAssetID: currentPhoto,
            partnerUserID: TestDailyChallengeIDs.partnerUser,
            partnerDisplayName: "Oda",
            partnerProfilePhotoAssetID: partnerPhoto
        )

        let options = try #require(participants.partnerChoiceOptions)
        // Current user keeps the "you" caption but uses their real name + photo for the avatar.
        #expect(options[0].label != "Hjalmar")
        #expect(options[0].avatarName == "Hjalmar")
        #expect(options[0].profilePhotoAssetID == currentPhoto)
        #expect(options[1].label == "Oda")
        #expect(options[1].avatarName == "Oda")
        #expect(options[1].profilePhotoAssetID == partnerPhoto)
    }

    @MainActor
    @Test func emptyAnswerDoesNotQueueSend() async throws {
        let question = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ]).ownQuestions[0]
        let service = RecordingDailyChallengeService(snapshots: [
            DailyChallengeSnapshot(
                currentUserID: TestDailyChallengeIDs.currentUser,
                coupleDayID: TestDailyChallengeIDs.coupleDay,
                questions: [question],
                refreshedAt: TestDailyChallengeIDs.startsAt
            ),
        ])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        await viewModel.submitAnswer(for: question)

        #expect(viewModel.notice == .emptyAnswer)
        #expect(!viewModel.isSending(question.id))
        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser,
            kind: .submitDailyAnswer
        )
        #expect(queued.isEmpty)
    }

    @MainActor
    @Test func submitAnswerQueuesTrimmedTextForBackgroundSend() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        viewModel.setDraftText("  Thinking of you  ", for: question.id)

        await viewModel.submitAnswer(for: question)

        // Saved on the device and shown as sending right away — nothing was lost and no
        // error was raised — with the trimmed text queued for the sync engine to send.
        #expect(viewModel.isSending(question.id))
        #expect(viewModel.notice == nil)
        #expect(viewModel.draftText(for: question.id).isEmpty)
        #expect(viewModel.sendingText(for: question.id) == "Thinking of you")

        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser,
            kind: .submitDailyAnswer
        )
        #expect(queued.count == 1)
        let data = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
        #expect(payload.instanceID == question.id)
        #expect(payload.content == .text("Thinking of you"))

        let relaunched = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            pendingOperationStore: pendingStore
        )
        await relaunched.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(relaunched.isSending(question.id))
        #expect(relaunched.sendingText(for: question.id) == "Thinking of you")
    }

    @MainActor
    @Test func requiredCompletionCountsQueuedOwnAnswers() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let questions = viewModel.snapshot.ownQuestions

        #expect(questions.count == DailyChallengeProgress.requiredOwnQuestionCount)
        #expect(!viewModel.snapshot.progress.isComplete)
        #expect(!viewModel.hasCompletedRequiredDailyQuestions)

        for question in questions {
            viewModel.setDraftText("Answer \(question.slotNumber)", for: question.id)
            await viewModel.submitAnswer(for: question)
        }

        #expect(!viewModel.snapshot.progress.isComplete)
        #expect(viewModel.hasCompletedRequiredDailyQuestions)
    }

    @MainActor
    @Test func submitAnswerDoesNotWaitForSyncNudge() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let syncProbe = DailyChallengeSyncNudgeProbe()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            pendingOperationStore: pendingStore
        )
        viewModel.setLocalChangeSyncHandler {
            await syncProbe.blockUntilReleased()
        }

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        viewModel.setDraftText(" Thinking of you ", for: question.id)

        let submitTask = Task { @MainActor in
            await viewModel.submitAnswer(for: question)
            await syncProbe.markSubmitReturned()
        }

        for _ in 0..<1_000 {
            if await syncProbe.didSubmitReturn() {
                break
            }
            await Task.yield()
        }

        #expect(await syncProbe.didSubmitReturn())
        #expect(viewModel.isSending(question.id))

        await syncProbe.release()
        await submitTask.value
    }

    @MainActor
    @Test func legacyTextDraftsMigrateToVersionedStore() throws {
        let suiteName = "test.dailyChallenge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = TestDailyChallengeIDs.currentUser
        let instanceID = UUID()
        let legacyKey = "paeonia.dailyChallenge.drafts.\(userID.uuidString)"
        defaults.set([instanceID.uuidString: "Half-written in the old format"], forKey: legacyKey)

        let store = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(store.drafts(for: userID)[instanceID]?.text == "Half-written in the old format")
        // The old key is cleared so the one-time migration never runs twice.
        #expect(defaults.dictionary(forKey: legacyKey) == nil)

        // A fresh store reads the migrated drafts back from the new versioned blob.
        let reopened = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(reopened.drafts(for: userID)[instanceID]?.text == "Half-written in the old format")
    }

    @MainActor
    @Test func submitAnswerQueuesPartnerChoiceForBackgroundSend() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.partnerChoice]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(question.defaultComposableKind == .partnerChoice)
        #expect(question.canSubmitAnswer)
        // A partner-choice answer isn't sendable until a person is picked.
        #expect(!viewModel.hasDraftToSubmit(for: question))

        viewModel.setPartnerChoice(TestDailyChallengeIDs.partnerUser, for: question.id)
        #expect(viewModel.hasDraftToSubmit(for: question))

        await viewModel.submitAnswer(for: question)

        #expect(viewModel.isSending(question.id))
        #expect(viewModel.notice == nil)
        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser,
            kind: .submitDailyAnswer
        )
        #expect(queued.count == 1)
        let data = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
        #expect(payload.content == .partnerChoice(TestDailyChallengeIDs.partnerUser))

        let relaunched = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            pendingOperationStore: pendingStore
        )
        await relaunched.configure(
            participants: DailyChallengeParticipants(
                currentUserID: TestDailyChallengeIDs.currentUser,
                partnerUserID: TestDailyChallengeIDs.partnerUser,
                partnerDisplayName: "Oda"
            )
        )
        #expect(relaunched.isSending(question.id))
        #expect(relaunched.sendingPartnerChoiceName(for: question.id) == "Oda")
    }

    @Test func partnerChoiceParticipantsResolveNamesAndOptions() throws {
        let participants = DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            partnerUserID: TestDailyChallengeIDs.partnerUser,
            partnerDisplayName: "Oda"
        )

        let options = try #require(participants.partnerChoiceOptions)
        #expect(options.count == 2)
        #expect(options[0].id == TestDailyChallengeIDs.currentUser)
        #expect(options[0].isCurrentUser)
        #expect(options[1].id == TestDailyChallengeIDs.partnerUser)
        #expect(options[1].label == "Oda")

        #expect(participants.name(for: TestDailyChallengeIDs.partnerUser) == "Oda")
        // The current user resolves to the localized "you" label, distinct from the partner.
        #expect(participants.name(for: TestDailyChallengeIDs.currentUser) != "Oda")
    }

    @Test func partnerChoiceOptionsHiddenWithoutPartnerIdentity() {
        let participants = DailyChallengeParticipants(
            currentUserID: TestDailyChallengeIDs.currentUser,
            partnerUserID: nil,
            partnerDisplayName: nil
        )
        #expect(participants.partnerChoiceOptions == nil)
    }

    @Test func partnerChoiceAnswerExposesSelectedUserInDetail() throws {
        let answerID = UUID()
        let snapshot = makeSnapshot(
            rows: [
                questionRow(
                    slotNumber: 1,
                    seededForUserID: TestDailyChallengeIDs.currentUser,
                    status: "answered",
                    answerKinds: [.partnerChoice],
                    ownAnswerID: answerID,
                    ownAnsweredAt: TestDailyChallengeIDs.answerDate
                ),
            ],
            details: [
                answerDetail(
                    answerID: answerID,
                    isOwnAnswer: true,
                    selectedUserID: TestDailyChallengeIDs.partnerUser
                ),
            ]
        )

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.hasOwnAnswer)
        #expect(question.ownAnswerDetail?.selectedUserID == TestDailyChallengeIDs.partnerUser)
    }

    @MainActor
    @Test func partnerChoiceDraftPersistsAcrossReopen() throws {
        let suiteName = "test.dailyChallenge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = TestDailyChallengeIDs.currentUser
        let instanceID = UUID()
        UserDefaultsDailyChallengeDraftStore(defaults: defaults)
            .setDraft(
                DailyAnswerDraft(partnerChoiceUserID: TestDailyChallengeIDs.partnerUser),
                for: instanceID,
                userID: userID
            )

        let reopened = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(reopened.drafts(for: userID)[instanceID]?.partnerChoiceUserID == TestDailyChallengeIDs.partnerUser)
    }

    @Test func photoCapableQuestionDefaultsToTextAndExposesBothKinds() throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.composableAnswerKinds == [.photo, .text])
        #expect(question.defaultComposableKind == .text)
        #expect(question.canSubmitAnswer)
    }

    @MainActor
    @Test func submitPhotoAnswerQueuesForBackgroundSendAndMarksSending() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: mediaStore,
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)

        // A two-kind question opens on text and isn't sendable until a photo is staged.
        #expect(viewModel.composeKind(for: question) == .text)
        viewModel.setComposeKind(.photo, for: question.id)
        #expect(viewModel.composeKind(for: question) == .photo)
        #expect(!viewModel.hasDraftToSubmit(for: question))

        viewModel.stagePhoto(sampleImageData(), for: question.id)
        #expect(viewModel.hasDraftToSubmit(for: question))

        await viewModel.submitAnswer(for: question)

        // Queued for background send, shown as sending, with the staged bytes kept so
        // the upload can finish.
        #expect(viewModel.isSending(question.id))
        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser,
            kind: .submitDailyAnswer
        )
        #expect(queued.count == 1)
        let queuedData = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: queuedData)
        guard case let .media(media) = payload.content else {
            Issue.record("Expected media content, got \(payload.content)")
            return
        }
        #expect(media.stagedData != nil)
        #expect(viewModel.sendingMediaData(for: question.id) != nil)
        // A photo-only answer has no caption text or partner pick.
        #expect(viewModel.sendingText(for: question.id) == nil)

        let relaunched = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore(),
            pendingOperationStore: pendingStore
        )
        await relaunched.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(relaunched.isSending(question.id))
        #expect(relaunched.sendingMediaData(for: question.id) != nil)
        #expect(relaunched.sendingText(for: question.id) == nil)
    }

    @Test func combinedComposeAppliesOnlyToTextWithPhotoOrPartnerChoice() {
        func secondaryKind(_ kinds: [DailyChallengeAnswerKind]) -> DailyChallengeAnswerKind? {
            makeSnapshot(rows: [
                questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser, answerKinds: kinds)
            ]).ownQuestions[0].combinedSecondaryKind
        }

        #expect(secondaryKind([.text, .photo]) == .photo)
        #expect(secondaryKind([.photo, .text]) == .photo)
        #expect(secondaryKind([.text, .partnerChoice]) == .partnerChoice)
        #expect(secondaryKind([.text]) == nil)
        #expect(secondaryKind([.photo]) == nil)
        #expect(secondaryKind([.text, .voice]) == nil)
    }

    @Test func combinedAnswersAreNotEditable() {
        let combined = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                answerKinds: [.photo, .text],
                ownAnswerID: UUID()
            ),
        ]).ownQuestions[0]
        #expect(combined.usesCombinedCompose)
        #expect(combined.editableAnswerKind == nil)

        // A plain text answer is still editable while it's private.
        let textOnly = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                status: "answered",
                answerKinds: [.text],
                ownAnswerID: UUID()
            ),
        ]).ownQuestions[0]
        #expect(textOnly.editableAnswerKind == .text)
    }

    @MainActor
    @Test func submitCombinedPhotoAndTextQueuesBothTogether() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: mediaStore,
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(question.usesCombinedCompose)

        // The user adds both a photo and a caption; either alone would also send.
        viewModel.setDraftText("By the lake", for: question.id)
        viewModel.stagePhoto(sampleImageData(), for: question.id)
        #expect(viewModel.hasDraftToSubmit(for: question))

        await viewModel.submitAnswer(for: question)

        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser,
            kind: .submitDailyAnswer
        )
        let queuedData = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: queuedData)
        guard case let .textAndMedia(body, media) = payload.content else {
            Issue.record("Expected combined text+media content, got \(payload.content)")
            return
        }
        #expect(body == "By the lake")
        #expect(media.stagedData != nil)

        // Both parts stay visible in the "saved, sending" preview while it uploads.
        #expect(viewModel.sendingText(for: question.id) == "By the lake")
        #expect(viewModel.sendingMediaData(for: question.id) != nil)
    }

    @MainActor
    @Test func dailySubmitAnswerHandlerUploadsThenSubmits() async throws {
        let instanceID = UUID()
        let answerID = UUID()
        let assetID = UUID()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        try mediaStore.writeStagedMedia(Data([0x09, 0x09, 0x09]), instanceID: instanceID)

        let uploader = RecordingMediaUploadService(assetID: assetID)
        let gateway = RecordingDailyChallengeGateway()
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: uploader,
            gateway: gateway,
            mediaDraftStore: mediaStore
        )

        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: answerID,
            content: .media(
                DailySubmitAnswerOperationPayload.Media(
                    draft: DailyAnswerMediaDraft(
                        purpose: .photo,
                        mimeType: "image/jpeg",
                        fileExtension: "jpg",
                        width: 10,
                        height: 8,
                        durationMs: nil
                    ),
                    coupleID: TestDailyChallengeIDs.couple,
                    reserveOperation: fixedClientOperation(),
                    finalizeOperation: fixedClientOperation()
                )
            )
        )
        let operation = pendingSnapshot(
            requestData: try JSONEncoder().encode(payload)
        )

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

        #expect(result == .succeeded)
        #expect(await uploader.uploadCount == 1)
        #expect(await uploader.lastAnswerID == answerID)
        #expect(await uploader.lastCoupleID == TestDailyChallengeIDs.couple)
        #expect(await gateway.submittedPayloads == [DailyAnswerPayload(mediaAssetIDs: [assetID])])
        #expect(await gateway.submittedAnswerIDs == [answerID])
        // The staged copy is removed once the answer is sent.
        #expect(mediaStore.stagedMediaData(instanceID: instanceID) == nil)
    }

    @MainActor
    @Test func dailySubmitAnswerHandlerRestoresQueuedMediaBytesWhenStagedFileMissing() async throws {
        let instanceID = UUID()
        let answerID = UUID()
        let assetID = UUID()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let uploader = RecordingMediaUploadService(assetID: assetID)
        let gateway = RecordingDailyChallengeGateway()
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: uploader,
            gateway: gateway,
            mediaDraftStore: mediaStore
        )

        let queuedBytes = Data([0x07, 0x08, 0x09])
        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: answerID,
            content: .media(
                DailySubmitAnswerOperationPayload.Media(
                    draft: DailyAnswerMediaDraft(
                        purpose: .voice,
                        mimeType: "audio/mp4",
                        fileExtension: "m4a",
                        width: nil,
                        height: nil,
                        durationMs: 1200
                    ),
                    coupleID: TestDailyChallengeIDs.couple,
                    reserveOperation: fixedClientOperation(),
                    finalizeOperation: fixedClientOperation(),
                    stagedData: queuedBytes
                )
            )
        )
        let operation = pendingSnapshot(requestData: try JSONEncoder().encode(payload))

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

        #expect(result == .succeeded)
        #expect(await uploader.uploadCount == 1)
        #expect(await gateway.submittedPayloads == [DailyAnswerPayload(mediaAssetIDs: [assetID])])
        #expect(mediaStore.stagedMediaData(instanceID: instanceID) == nil)
    }

    @MainActor
    @Test func dailySubmitAnswerHandlerFailsTerminallyWhenStagedMediaMissing() async throws {
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: RecordingMediaUploadService(assetID: UUID()),
            gateway: RecordingDailyChallengeGateway(),
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore()
        )
        let payload = DailySubmitAnswerOperationPayload(
            instanceID: UUID(),
            answerID: UUID(),
            content: .media(
                DailySubmitAnswerOperationPayload.Media(
                    draft: DailyAnswerMediaDraft(
                        purpose: .photo,
                        mimeType: "image/jpeg",
                        fileExtension: "jpg",
                        width: 1,
                        height: 1,
                        durationMs: nil
                    ),
                    coupleID: TestDailyChallengeIDs.couple,
                    reserveOperation: fixedClientOperation(),
                    finalizeOperation: fixedClientOperation()
                )
            )
        )
        let operation = pendingSnapshot(requestData: try JSONEncoder().encode(payload))

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

    if case .terminalFailure = result {
            // Expected: nothing to send once staged file and queued fallback are gone.
    } else {
        Issue.record("Expected terminal failure, got \(result)")
    }
    }

    @MainActor
    @Test func dailySubmitAnswerHandlerSubmitsTextWithoutUpload() async throws {
        let instanceID = UUID()
        let answerID = UUID()
        let uploader = RecordingMediaUploadService(assetID: UUID())
        let gateway = RecordingDailyChallengeGateway()
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: uploader,
            gateway: gateway,
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore()
        )

        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: answerID,
            content: .text("Thinking of you")
        )
        let operation = pendingSnapshot(requestData: try JSONEncoder().encode(payload))

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

        #expect(result == .succeeded)
        // Text goes straight to the backend — no media upload step.
        #expect(await uploader.uploadCount == 0)
        #expect(await gateway.submittedPayloads == [DailyAnswerPayload(text: "Thinking of you")])
        #expect(await gateway.submittedAnswerIDs == [answerID])
    }

    @Test func voiceQuestionIsComposableAndRevealsAsVoice() throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.voice]
            ),
        ])

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.composableAnswerKinds == [.voice])
        #expect(question.defaultComposableKind == .voice)
        #expect(question.mediaAnswerKind == .voice)
        #expect(question.canSubmitAnswer)
    }

    @Test func photoQuestionRevealsAsPhoto() throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])

        let question = try #require(snapshot.ownQuestions.first)
        #expect(question.mediaAnswerKind == .photo)
    }

    @MainActor
    @Test func stageVoiceQueuesVoiceAnswerForBackgroundSend() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.voice]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: mediaStore,
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        #expect(viewModel.composeKind(for: question) == .voice)
        #expect(!viewModel.hasDraftToSubmit(for: question))

        let voiceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-voice-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: voiceURL)
        viewModel.stageVoice(url: voiceURL, durationMs: 4200, for: question.id)

        #expect(viewModel.hasDraftToSubmit(for: question))
        #expect(viewModel.stagedVoiceDurationMs(for: question.id) == 4200)

        await viewModel.submitAnswer(for: question)

        #expect(viewModel.isSending(question.id))
        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: TestDailyChallengeIDs.currentUser,
            kind: .submitDailyAnswer
        )
        #expect(queued.count == 1)

        let data = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
        guard case let .media(media) = payload.content else {
            Issue.record("Expected media content, got \(payload.content)")
            return
        }
        #expect(media.draft.purpose == .voice)
        #expect(media.draft.durationMs == 4200)
        #expect(media.stagedData == Data([0x00, 0x01, 0x02, 0x03]))
    }

    @MainActor
    @Test func sendingVoiceNoteStaysPlayableWithDurationAfterDraftCleared() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.voice]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: mediaStore,
            pendingOperationStore: pendingStore
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)

        let voiceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-voice-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: voiceURL)
        viewModel.stageVoice(url: voiceURL, durationMs: 4200, for: question.id)

        await viewModel.submitAnswer(for: question)

        // The editable draft is gone once it's queued, but the sending preview still
        // has the bytes and the recorded length so it stays playable on both screens.
        #expect(viewModel.isSending(question.id))
        #expect(viewModel.stagedVoiceDurationMs(for: question.id) == nil)
        #expect(viewModel.sendingMediaData(for: question.id) != nil)
        #expect(viewModel.sendingVoiceDurationMs(for: question.id) == 4200)

        let relaunched = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore(),
            pendingOperationStore: pendingStore
        )
        await relaunched.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        #expect(relaunched.isSending(question.id))
        #expect(relaunched.stagedVoiceDurationMs(for: question.id) == nil)
        #expect(relaunched.sendingMediaData(for: question.id) != nil)
        #expect(relaunched.sendingVoiceDurationMs(for: question.id) == 4200)
    }

    @Test func stagedMediaDraftStoreRoundTripsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dailyChallengeMediaTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileDailyAnswerMediaDraftStore(directoryURL: directory)
        let instanceID = UUID()
        let data = Data([0x01, 0x02, 0x03, 0x04])

        try store.writeStagedMedia(data, instanceID: instanceID)
        #expect(store.stagedMediaData(instanceID: instanceID) == data)
        let reopened = FileDailyAnswerMediaDraftStore(directoryURL: directory)
        #expect(reopened.stagedMediaData(instanceID: instanceID) == data)

        store.removeStagedMedia(instanceID: instanceID)
        #expect(store.stagedMediaData(instanceID: instanceID) == nil)

        try store.writeStagedMedia(data, instanceID: instanceID)
        store.clearAll()
        #expect(store.stagedMediaData(instanceID: instanceID) == nil)
    }

    @MainActor
    @Test func mediaDraftPersistsAcrossReopen() throws {
        let suiteName = "test.dailyChallenge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = TestDailyChallengeIDs.currentUser
        let instanceID = UUID()
        let media = DailyAnswerMediaDraft(
            purpose: .photo,
            mimeType: "image/jpeg",
            fileExtension: "jpg",
            width: 100,
            height: 80,
            durationMs: nil
        )

        UserDefaultsDailyChallengeDraftStore(defaults: defaults)
            .setDraft(DailyAnswerDraft(media: media), for: instanceID, userID: userID)

        let reopened = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(reopened.drafts(for: userID)[instanceID]?.media == media)
    }

    @MainActor
    @Test func draftStoreRoundTripsAndClears() throws {
        let suiteName = "test.dailyChallenge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = TestDailyChallengeIDs.currentUser
        let instanceID = UUID()

        UserDefaultsDailyChallengeDraftStore(defaults: defaults)
            .setDraft(DailyAnswerDraft(text: "Saved across launches"), for: instanceID, userID: userID)

        let reopened = UserDefaultsDailyChallengeDraftStore(defaults: defaults)
        #expect(reopened.drafts(for: userID)[instanceID]?.text == "Saved across launches")

        reopened.clearDraft(for: instanceID, userID: userID)
        #expect(UserDefaultsDailyChallengeDraftStore(defaults: defaults).drafts(for: userID).isEmpty)
    }
}

struct DailyChallengeHistoryTests {
    private static let day1 = "2026-06-25"
    private static let day2 = "2026-06-26"
    private static let day3 = "2026-06-27"

    /// An answered own-question row for `localDate`, answered at `answeredAt`.
    private func answeredOwnRow(
        localDate: String,
        slotNumber: Int,
        answeredAt: Date,
        ownAnswerID: UUID = UUID()
    ) -> DailyQuestionRow {
        // A couple day is unique per date; grouping keys on localDate, so a fresh
        // couple-day id per row keeps the fixtures realistic without affecting it.
        questionRow(
            coupleDayID: UUID(),
            localDate: localDate,
            slotNumber: slotNumber,
            seededForUserID: TestDailyChallengeIDs.currentUser,
            status: "answered",
            ownAnswerID: ownAnswerID,
            ownAnsweredAt: answeredAt
        )
    }

    private func historyQuestions(_ rows: [DailyQuestionRow], details: [DailyAnswerDetailRow] = []) -> [DailyChallengeQuestion] {
        DailyChallengeQuestion.list(
            currentUserID: TestDailyChallengeIDs.currentUser,
            rows: rows,
            answerDetails: details,
            locale: Locale(identifier: "en_US")
        )
    }

    @Test func groupsByLocalDateNewestFirst() {
        let questions = historyQuestions([
            answeredOwnRow(localDate: Self.day1, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            answeredOwnRow(localDate: Self.day2, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            answeredOwnRow(localDate: Self.day2, slotNumber: 2, answeredAt: TestDailyChallengeIDs.answerDate),
        ])

        let days = DailyChallengeHistory.grouped(questions)

        #expect(days.map(\.localDate) == [Self.day3, Self.day2, Self.day1])
        #expect(days.first(where: { $0.localDate == Self.day2 })?.questions.count == 2)
        #expect(days.first(where: { $0.localDate == Self.day3 })?.questions.count == 1)
    }

    @Test func ordersQuestionsWithinADayByAnswerTimeEarliestFirst() {
        let early = TestDailyChallengeIDs.answerDate
        let late = early.addingTimeInterval(3_600)

        // Slot 1 answered later than slot 2, so ordering must follow answer time, not slot.
        let questions = historyQuestions([
            answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: late),
            answeredOwnRow(localDate: Self.day3, slotNumber: 2, answeredAt: early),
        ])

        let days = DailyChallengeHistory.grouped(questions)

        #expect(days.count == 1)
        #expect(days[0].questions.map(\.slotNumber) == [2, 1])
    }

    @Test func emptyQuestionsProduceNoDays() {
        #expect(DailyChallengeHistory.grouped([]).isEmpty)
    }

    @Test func parsesLocalDateToUTCMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 27))

        #expect(DailyChallengeHistory.parseLocalDate("2026-06-27") == expected)
        #expect(DailyChallengeHistory.parseLocalDate("not-a-date") == nil)
    }

    @Test func groupedDayCarriesParsedDateForFormatting() {
        let questions = historyQuestions([
            answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
        ])

        let day = DailyChallengeHistory.grouped(questions).first
        #expect(day?.date == DailyChallengeHistory.parseLocalDate(Self.day3))
    }

    @Test func serviceLoadHistoryMergesRowsAndDetailsInTwoCalls() async throws {
        let ownAnswerID = UUID()
        let gateway = RecordingDailyChallengeReadGateway(
            rows: [],
            historyRows: [
                answeredOwnRow(
                    localDate: Self.day3,
                    slotNumber: 1,
                    answeredAt: TestDailyChallengeIDs.answerDate,
                    ownAnswerID: ownAnswerID
                ),
            ],
            historyDetails: [
                answerDetail(answerID: ownAnswerID, isOwnAnswer: true, textBody: "A quiet morning together"),
            ]
        )
        let service = SupabaseDailyChallengeService(gateway: gateway, locale: Locale(identifier: "en_US"))

        let questions = try await service.loadHistory(currentUserID: TestDailyChallengeIDs.currentUser)

        #expect(questions.count == 1)
        #expect(questions.first?.ownAnswerDetail?.textBody == "A quiet morning together")
        #expect(await gateway.historyQuestionLoadCount == 1)
        #expect(await gateway.historyDetailLoadCount == 1)
    }

    @MainActor
    @Test func viewModelLoadsGroupedContentAndBecomesReady() async {
        let service = RecordingDailyChallengeService(
            snapshots: [],
            historyQuestions: historyQuestions([
                answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
                answeredOwnRow(localDate: Self.day1, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            ])
        )
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: TestDailyChallengeIDs.currentUser
        )

        #expect(!viewModel.isPresentationReady)

        await viewModel.load()

        #expect(viewModel.isPresentationReady)
        guard case let .content(days) = viewModel.state else {
            Issue.record("Expected content state, got \(viewModel.state)")
            return
        }
        #expect(days.map(\.localDate) == [Self.day3, Self.day1])
    }

    @MainActor
    @Test func viewModelEmptyHistoryShowsEmptyState() async {
        let service = RecordingDailyChallengeService(snapshots: [], historyQuestions: [])
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: TestDailyChallengeIDs.currentUser
        )

        await viewModel.load()

        #expect(viewModel.state == .empty)
        #expect(viewModel.isPresentationReady)
    }

    @MainActor
    @Test func viewModelFirstLoadFailureShowsFailedStateWithoutBanner() async {
        let service = RecordingDailyChallengeService(
            snapshots: [],
            historyError: URLError(.badServerResponse)
        )
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: TestDailyChallengeIDs.currentUser
        )

        await viewModel.load()

        #expect(viewModel.state == .failed)
        #expect(viewModel.notice == nil)
        #expect(viewModel.isPresentationReady)
    }

    @MainActor
    @Test func viewModelReloadFailureKeepsContentAndShowsBanner() async {
        let service = RecordingDailyChallengeService(
            snapshots: [],
            historyQuestions: historyQuestions([
                answeredOwnRow(localDate: Self.day3, slotNumber: 1, answeredAt: TestDailyChallengeIDs.answerDate),
            ]),
            historyReloadError: URLError(.timedOut)
        )
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: TestDailyChallengeIDs.currentUser
        )

        await viewModel.load()
        await viewModel.load()

        guard case let .content(days) = viewModel.state else {
            Issue.record("Expected content to remain after a failed reload, got \(viewModel.state)")
            return
        }
        #expect(days.count == 1)
        #expect(viewModel.notice == .loadFailed)
    }

    @MainActor
    @Test func viewModelCancellationIsSwallowed() async {
        let service = RecordingDailyChallengeService(
            snapshots: [],
            historyError: CancellationError()
        )
        let viewModel = DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: TestDailyChallengeIDs.currentUser
        )

        await viewModel.load()

        // A cancelled first load leaves the loading surface up and never errors.
        #expect(viewModel.state == .loading)
        #expect(viewModel.notice == nil)
    }
}

private enum TestDailyChallengeIDs {
    static let currentUser = fixedUUID("11111111-1111-1111-1111-111111111111")
    static let partnerUser = fixedUUID("22222222-2222-2222-2222-222222222222")
    static let couple = fixedUUID("33333333-3333-3333-3333-333333333333")
    static let coupleDay = fixedUUID("44444444-4444-4444-4444-444444444444")
    static let previousCoupleDay = fixedUUID("55555555-5555-5555-5555-555555555555")
    static let startsAt = Date(timeIntervalSince1970: 1_782_432_000)
    static let endsAt = Date(timeIntervalSince1970: 1_782_518_400)
    static let answerDate = Date(timeIntervalSince1970: 1_782_450_000)
}

private func makeSnapshot(
    rows: [DailyQuestionRow],
    details: [DailyAnswerDetailRow] = []
) -> DailyChallengeSnapshot {
    DailyChallengeSnapshot.make(
        currentUserID: TestDailyChallengeIDs.currentUser,
        rows: rows,
        answerDetails: details,
        locale: Locale(identifier: "en_US"),
        refreshedAt: TestDailyChallengeIDs.startsAt
    )
}

private func questionRow(
    coupleDayID: UUID = TestDailyChallengeIDs.coupleDay,
    localDate: String = "2026-06-27",
    startsAt: Date = TestDailyChallengeIDs.startsAt,
    endsAt: Date = TestDailyChallengeIDs.endsAt,
    slotNumber: Int,
    seededForUserID: UUID,
    status: String = "active",
    answerKinds: [DailyChallengeAnswerKind] = [.text],
    promptEN: String = "What small moment made you think of us today?",
    ownAnswerID: UUID? = nil,
    ownAnsweredAt: Date? = nil,
    partnerAnswerID: UUID? = nil,
    partnerAnsweredAt: Date? = nil,
    canViewPartnerAnswer: Bool = false,
    isCurrentDay: Bool? = nil
) -> DailyQuestionRow {
    DailyQuestionRow(
        coupleDayID: coupleDayID,
        coupleID: TestDailyChallengeIDs.couple,
        localDate: localDate,
        startsAt: startsAt,
        endsAt: endsAt,
        instanceID: UUID(),
        seededForUserID: seededForUserID,
        slotNumber: slotNumber,
        instanceStatus: status,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "small_moment_today",
        promptEN: promptEN,
        shortPromptEN: "A small moment today",
        promptNB: "Hvilket lite oyeblikk fikk deg til a tenke pa oss i dag?",
        shortPromptNB: "Et lite oyeblikk fra i dag",
        answerKinds: answerKinds,
        ownAnswerID: ownAnswerID,
        ownAnsweredAt: ownAnsweredAt,
        partnerAnswerID: partnerAnswerID,
        partnerAnsweredAt: partnerAnsweredAt,
        canViewPartnerAnswer: canViewPartnerAnswer,
        isCurrentDay: isCurrentDay
    )
}

private func answerDetail(
    answerUserID: UUID = TestDailyChallengeIDs.currentUser,
    answerID: UUID,
    isOwnAnswer: Bool,
    canViewAnswer: Bool = true,
    textBody: String? = nil,
    selectedUserID: UUID? = nil,
    mediaAssetIDs: [UUID] = []
) -> DailyAnswerDetailRow {
    DailyAnswerDetailRow(
        coupleDayID: TestDailyChallengeIDs.coupleDay,
        instanceID: UUID(),
        seededForUserID: TestDailyChallengeIDs.currentUser,
        slotNumber: 1,
        answerUserID: answerUserID,
        answerID: answerID,
        answeredAt: TestDailyChallengeIDs.answerDate,
        isOwnAnswer: isOwnAnswer,
        canViewAnswer: canViewAnswer,
        textBody: textBody,
        selectedUserID: selectedUserID,
        mediaAssetIDs: mediaAssetIDs
    )
}

private actor RecordingDailyChallengeService: DailyChallengeServicing {
    private var snapshots: [DailyChallengeSnapshot]
    private let advancesSnapshotsOnLoad: Bool
    private let shuffleSnapshot: DailyChallengeSnapshot?
    private let shuffleError: Error?
    private let editError: Error?
    private let loadError: Error?
    private let historyQuestions: [DailyChallengeQuestion]
    private let historyError: Error?
    private let historyReloadError: Error?
    private let streak: CoupleStreak
    private(set) var editedTexts: [String] = []
    private(set) var editedChoices: [UUID] = []
    private(set) var shuffledSlots: [Int] = []
    private(set) var streakLoadCount = 0
    private(set) var loadCount = 0
    private(set) var historyLoadCount = 0

    init(
        snapshots: [DailyChallengeSnapshot],
        advancesSnapshotsOnLoad: Bool = false,
        shuffleSnapshot: DailyChallengeSnapshot? = nil,
        shuffleError: Error? = nil,
        editError: Error? = nil,
        loadError: Error? = nil,
        historyQuestions: [DailyChallengeQuestion] = [],
        historyError: Error? = nil,
        historyReloadError: Error? = nil,
        streak: CoupleStreak = .none
    ) {
        self.snapshots = snapshots
        self.advancesSnapshotsOnLoad = advancesSnapshotsOnLoad
        self.shuffleSnapshot = shuffleSnapshot
        self.shuffleError = shuffleError
        self.editError = editError
        self.loadError = loadError
        self.historyQuestions = historyQuestions
        self.historyError = historyError
        self.historyReloadError = historyReloadError
        self.streak = streak
    }

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeSnapshot {
        loadCount += 1
        if let loadError {
            throw loadError
        }
        if advancesSnapshotsOnLoad, !snapshots.isEmpty {
            return snapshots.removeFirst()
        }
        return snapshots.first ?? .empty(currentUserID: currentUserID)
    }

    func loadHistory(currentUserID _: UUID) async throws -> [DailyChallengeQuestion] {
        historyLoadCount += 1
        if historyLoadCount > 1, let historyReloadError {
            throw historyReloadError
        }
        if let historyError {
            throw historyError
        }
        return historyQuestions
    }

    func loadStreak() async throws -> CoupleStreak {
        streakLoadCount += 1
        return streak
    }

    func startToday(
        currentUserID: UUID,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeSnapshot {
        snapshots.first ?? .empty(currentUserID: currentUserID)
    }

    func editTextAnswer(
        instanceID _: UUID,
        text: String,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        editedTexts.append(text)
        if let editError {
            throw editError
        }
        return UUID()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID: UUID,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        editedChoices.append(selectedUserID)
        if let editError {
            throw editError
        }
        return UUID()
    }

    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber: Int,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeSnapshot {
        shuffledSlots.append(slotNumber)
        if let shuffleError {
            throw shuffleError
        }
        return shuffleSnapshot ?? snapshots.first ?? .empty(currentUserID: currentUserID)
    }
}

private actor RecordingDailyChallengeReadGateway: SupabaseDailyChallengeGateway {
    private let rows: [DailyQuestionRow]
    private let detailsByCoupleDayID: [UUID: [DailyAnswerDetailRow]]
    private let historyRows: [DailyQuestionRow]
    private let historyDetails: [DailyAnswerDetailRow]
    private(set) var loadedAnswerDetailCoupleDayIDs: [UUID] = []
    private(set) var historyQuestionLoadCount = 0
    private(set) var historyDetailLoadCount = 0

    init(
        rows: [DailyQuestionRow],
        detailsByCoupleDayID: [UUID: [DailyAnswerDetailRow]] = [:],
        historyRows: [DailyQuestionRow] = [],
        historyDetails: [DailyAnswerDetailRow] = []
    ) {
        self.rows = rows
        self.detailsByCoupleDayID = detailsByCoupleDayID
        self.historyRows = historyRows
        self.historyDetails = historyDetails
    }

    func loadTodayQuestions() async throws -> [DailyQuestionRow] {
        rows
    }

    func startDailyChallenge(operation _: SyncClientOperation) async throws -> [DailyQuestionRow] {
        rows
    }

    func loadHistoryQuestions() async throws -> [DailyQuestionRow] {
        historyQuestionLoadCount += 1
        return historyRows
    }

    func loadHistoryAnswerDetails() async throws -> [DailyAnswerDetailRow] {
        historyDetailLoadCount += 1
        return historyDetails
    }

    func loadCoupleStreak() async throws -> CoupleStreak {
        .none
    }

    func loadAnswerDetails(coupleDayID: UUID) async throws -> [DailyAnswerDetailRow] {
        loadedAnswerDetailCoupleDayIDs.append(coupleDayID)
        return detailsByCoupleDayID[coupleDayID] ?? []
    }

    func submitAnswer(
        instanceID _: UUID,
        answerID: UUID,
        payload _: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        answerID
    }

    func editTextAnswer(
        instanceID _: UUID,
        text _: String,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        UUID()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        UUID()
    }

    func shuffleQuestion(
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) async throws -> [DailyQuestionRow] {
        rows
    }
}

@MainActor
private final class InMemoryDailyChallengeDraftStore: DailyChallengeDraftStoring {
    private var storage: [UUID: [UUID: DailyAnswerDraft]] = [:]

    func drafts(for userID: UUID) -> [UUID: DailyAnswerDraft] {
        storage[userID] ?? [:]
    }

    func setDraft(_ draft: DailyAnswerDraft, for instanceID: UUID, userID: UUID) {
        if draft.hasContent {
            storage[userID, default: [:]][instanceID] = draft
        } else {
            storage[userID]?[instanceID] = nil
        }
    }

    func clearDraft(for instanceID: UUID, userID: UUID) {
        storage[userID]?[instanceID] = nil
    }
}

@MainActor
private final class FixedDailyChallengeOperationProvider: SyncClientOperationProviding {
    func makeOperation() -> SyncClientOperation {
        SyncClientOperation(
            id: fixedUUID("55555555-5555-5555-5555-555555555555"),
            clientID: fixedUUID("66666666-6666-6666-6666-666666666666"),
            clientSequence: 1,
            localCreatedAt: TestDailyChallengeIDs.answerDate
        )
    }
}

private actor RecordingMediaUploadService: DailyAnswerMediaUploading {
    let assetID: UUID
    private(set) var uploadCount = 0
    private(set) var lastAnswerID: UUID?
    private(set) var lastCoupleID: UUID?

    init(assetID: UUID) {
        self.assetID = assetID
    }

    func uploadMedia(
        _: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        uploadCount += 1
        lastAnswerID = answerID
        lastCoupleID = coupleID
        return assetID
    }
}

private final class InMemoryDailyAnswerMediaDraftStore: DailyAnswerMediaDraftStoring, @unchecked Sendable {
    private var storage: [UUID: Data] = [:]

    func writeStagedMedia(_ data: Data, instanceID: UUID) throws {
        storage[instanceID] = data
    }

    func stagedMediaData(instanceID: UUID) -> Data? {
        storage[instanceID]
    }

    func removeStagedMedia(instanceID: UUID) {
        storage[instanceID] = nil
    }

    func clearAll() {
        storage.removeAll()
    }
}

@MainActor
private func sampleImageData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
    let image = renderer.image { context in
        UIColor.systemPink.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    return image.jpegData(compressionQuality: 0.9) ?? image.pngData() ?? Data()
}

private actor RecordingDailyChallengeGateway: SupabaseDailyChallengeGateway {
    private(set) var submittedPayloads: [DailyAnswerPayload] = []
    private(set) var submittedAnswerIDs: [UUID] = []

    func loadTodayQuestions() async throws -> [DailyQuestionRow] { [] }

    func startDailyChallenge(operation _: SyncClientOperation) async throws -> [DailyQuestionRow] { [] }

    func loadHistoryQuestions() async throws -> [DailyQuestionRow] { [] }

    func loadHistoryAnswerDetails() async throws -> [DailyAnswerDetailRow] { [] }

    func loadCoupleStreak() async throws -> CoupleStreak { .none }

    func loadAnswerDetails(coupleDayID _: UUID) async throws -> [DailyAnswerDetailRow] { [] }

    func submitAnswer(
        instanceID _: UUID,
        answerID: UUID,
        payload: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        submittedPayloads.append(payload)
        submittedAnswerIDs.append(answerID)
        return UUID()
    }

    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) async throws -> UUID {
        UUID()
    }

    func editPartnerChoice(instanceID _: UUID, selectedUserID _: UUID, operation _: SyncClientOperation) async throws -> UUID {
        UUID()
    }

    func shuffleQuestion(slotNumber _: Int, operation _: SyncClientOperation) async throws -> [DailyQuestionRow] { [] }
}

private actor DailyChallengeSyncNudgeProbe {
    private var isReleased = false
    private var submitReturned = false

    func blockUntilReleased() async {
        while !isReleased {
            await Task.yield()
        }
    }

    func markSubmitReturned() {
        submitReturned = true
    }

    func didSubmitReturn() -> Bool {
        submitReturned
    }

    func release() {
        isReleased = true
    }
}

private func fixedClientOperation() -> SyncClientOperation {
    SyncClientOperation(id: UUID(), clientID: UUID(), clientSequence: 1, localCreatedAt: Date())
}

private func pendingSnapshot(requestData: Data) -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: TestDailyChallengeIDs.currentUser,
        operation: fixedClientOperation(),
        operationKind: .submitDailyAnswer,
        idempotencyScope: "daily-answer-test",
        requestHash: nil,
        requestData: requestData,
        status: .queued,
        attemptCount: 0,
        lastAttemptAt: nil,
        nextRetryAt: nil,
        lastError: nil,
        completedAt: nil
    )
}

private func dailyChallengeSyncContext() -> SyncContext {
    SyncContext(
        session: SyncSession(userID: TestDailyChallengeIDs.currentUser, activeCoupleID: TestDailyChallengeIDs.couple),
        reason: .localChange,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository()
    )
}
