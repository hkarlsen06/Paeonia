import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

// MARK: - Day boundary, sending state, and refused answers

@MainActor
struct DailyChallengeDayBoundaryAndSendingTests {
    private let user = TestDailyChallengeIDs.currentUser
    private let dayEnd = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeViewModel(
        service: RecordingDailyChallengeService,
        pendingStore: any PendingSyncOperationPersisting = InMemoryPendingSyncOperationRepository(),
        mediaStore: InMemoryDailyAnswerMediaDraftStore = InMemoryDailyAnswerMediaDraftStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> DailyChallengeViewModel {
        DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaDraftStore: mediaStore,
            pendingOperationStore: pendingStore,
            now: now
        )
    }

    @Test func aDayWhoseEndHasPassedIsNotShownAsToday() async throws {
        let questionID = UUID()
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                endsAt: dayEnd,
                instanceID: questionID,
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])
        let clock = LockedBox(dayEnd.addingTimeInterval(-60))
        let before = makeViewModel(service: RecordingDailyChallengeService(snapshots: [snapshot]), now: { clock.value })
        await before.configure(currentUserID: user)
        #expect(before.snapshot.todayQuestion?.id == questionID)

        // The same day seen after it ended (for example from the cache on an offline
        // launch the next morning) is not today any more.
        clock.mutate { $0 = dayEnd.addingTimeInterval(1) }
        let after = makeViewModel(service: RecordingDailyChallengeService(snapshots: [snapshot]), now: { clock.value })
        await after.configure(currentUserID: user)

        #expect(after.snapshot.todayQuestion == nil)
        #expect(after.homeCardState.kind == .noChallenge)
        // The partner answered it, so it carries over as an earlier day's locked row.
        #expect(after.snapshot.questionsAwaitingAnswer.map(\.id) == [questionID])
        #expect(after.homeCardState.lockedPartnerQuestions.map(\.id) == [questionID])
    }

    @Test(arguments: [false, true])
    func sendingAfterTheDayEndedQueuesOnlyWhenThePartnerAnswered(partnerAnswered: Bool) async throws {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                endsAt: dayEnd,
                partnerAnswerID: partnerAnswered ? UUID() : nil,
                partnerAnsweredAt: partnerAnswered ? TestDailyChallengeIDs.answerDate : nil
            ),
        ])
        let clock = LockedBox(dayEnd.addingTimeInterval(-60))
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = makeViewModel(
            service: RecordingDailyChallengeService(snapshots: [snapshot]),
            pendingStore: pendingStore,
            now: { clock.value }
        )
        await viewModel.configure(currentUserID: user)
        let question = try #require(viewModel.snapshot.todayQuestion)
        viewModel.setDraftText("Late answer", for: question.id)

        // The screen stayed open past the end of the couple's day. After its day the
        // server takes an answer only when the partner has answered. Otherwise a queued
        // one would never send and would show as "sending" forever.
        clock.mutate { $0 = dayEnd.addingTimeInterval(1) }
        await viewModel.submitAnswer(for: question)

        let queued = try await pendingStore.inFlightOperations(ownerUserID: user, kind: .submitDailyAnswer)
        #expect(queued.count == (partnerAnswered ? 1 : 0))
        #expect(viewModel.isSending(question.id) == partnerAnswered)
        if partnerAnswered {
            #expect(viewModel.notice == nil)
        } else {
            #expect(viewModel.notice == .dayEnded)
            #expect(viewModel.draftText(for: question.id) == "Late answer")
            #expect(viewModel.snapshot.todayQuestion == nil)
        }
    }

    @Test func theCompletionDateIsTheActiveDayEvenWhenACarriedQuestionComesFirst() {
        let snapshot = makeDailySnapshot(rows: [
            dailyQuestionRow(
                coupleDayID: TestDailyChallengeIDs.previousCoupleDay,
                localDate: "2026-06-26",
                partnerAnswerID: UUID(),
                partnerAnsweredAt: TestDailyChallengeIDs.answerDate,
                isCurrentDay: false
            ),
            dailyQuestionRow(localDate: "2026-06-27", isCurrentDay: true),
        ])

        #expect(snapshot.questions.first?.localDate == "2026-06-26")
        #expect(snapshot.currentDayLocalDate == "2026-06-27")
    }

    @Test func anAnswerLongerThanTheServerAllowsCannotBeSent() async throws {
        let snapshot = makeDailySnapshot(rows: [dailyQuestionRow()])
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = makeViewModel(
            service: RecordingDailyChallengeService(snapshots: [snapshot]),
            pendingStore: pendingStore
        )
        await viewModel.configure(currentUserID: user)
        let question = try #require(viewModel.snapshot.todayQuestion)

        viewModel.setDraftText(String(repeating: "a", count: DailyAnswerDraft.maxTextLength), for: question.id)
        #expect(viewModel.hasDraftToSubmit(for: question))

        // The backend counts code points, and each family emoji is five of them, so
        // 401 of them are over the limit even though Swift counts 401 characters.
        viewModel.setDraftText(String(repeating: "👨‍👩‍👧", count: 401), for: question.id)
        #expect(viewModel.isDraftTextTooLong(for: question.id))
        #expect(!viewModel.hasDraftToSubmit(for: question))

        await viewModel.submitAnswer(for: question)

        #expect(!viewModel.isSending(question.id))
        let queued = try await pendingStore.inFlightOperations(ownerUserID: user, kind: .submitDailyAnswer)
        #expect(queued.isEmpty)
    }

    @Test func aResultThatCarriesTheSentAnswerEndsTheSendingPreview() async throws {
        let instanceID = UUID()
        let unanswered = makeDailySnapshot(rows: [
            dailyQuestionRow(instanceID: instanceID),
        ])
        let answered = makeDailySnapshot(rows: [
            dailyQuestionRow(
                instanceID: instanceID,
                ownAnswerID: UUID(),
                ownAnsweredAt: TestDailyChallengeIDs.answerDate
            ),
        ])
        let service = RecordingDailyChallengeService(
            snapshots: [unanswered, answered, answered, answered],
            advancesSnapshotsOnLoad: true
        )
        // The queued operation is never drained here, like the moment after the live
        // result lands but before the outbox marks the send finished.
        let viewModel = makeViewModel(service: service)
        await viewModel.configure(currentUserID: user)
        let question = try #require(viewModel.snapshot.todayQuestion)
        viewModel.setDraftText("On my way", for: question.id)
        await viewModel.submitAnswer(for: question)
        #expect(viewModel.isSending(question.id))

        await viewModel.reload()

        #expect(viewModel.snapshot.todayQuestion?.hasOwnAnswer == true)
        #expect(!viewModel.isSending(question.id))
        #expect(viewModel.sendingPreview(for: question) == nil)
    }

    @Test func aSendDuringAnOlderStoreReadStaysShownAsSending() async throws {
        let snapshot = makeDailySnapshot(rows: [dailyQuestionRow()])
        let pendingStore = GatedReadPendingStore()
        let viewModel = makeViewModel(
            service: RecordingDailyChallengeService(snapshots: [snapshot]),
            pendingStore: pendingStore
        )
        await viewModel.configure(currentUserID: user)
        let question = try #require(viewModel.snapshot.todayQuestion)

        // A reload reads the outbox before the answer is queued, and its result
        // arrives after the send. Other tests' outbox changes for the same test user
        // can wake the view model's observer too, so more than one read may be held.
        await pendingStore.holdReads()
        let reload = Task { await viewModel.reload() }
        #expect(await waitUntil(timeout: .seconds(30)) { await pendingStore.heldReadCount >= 1 })

        viewModel.setDraftText("Thinking of you", for: question.id)
        await viewModel.submitAnswer(for: question)
        #expect(viewModel.isSending(question.id))

        await pendingStore.releaseReads()
        await reload.value

        // The older read must not replace the list with one that misses the send. The
        // draft is already cleared, so that would make the answer look lost.
        #expect(viewModel.isSending(question.id))
        #expect(viewModel.sendingText(for: question.id) == "Thinking of you")
    }

    @Test func skippingAQuestionRemovesItsStagedPhoto() async throws {
        let question = dailyQuestionRow(answerKinds: [.photo])
        let replacement = dailyQuestionRow(answerKinds: [.photo])
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = makeViewModel(
            service: RecordingDailyChallengeService(
                snapshots: [makeDailySnapshot(rows: [question])],
                shuffleSnapshot: makeDailySnapshot(rows: [replacement])
            ),
            mediaStore: mediaStore
        )
        await viewModel.configure(currentUserID: user)
        let current = try #require(viewModel.snapshot.todayQuestion)
        await viewModel.stagePhoto(dailySampleImageData(), for: current.id)
        #expect(mediaStore.stagedMediaData(instanceID: current.id) != nil)

        await viewModel.shuffle(current)

        // The skipped question is gone for good, so its private photo shouldn't stay
        // on the phone.
        #expect(mediaStore.stagedMediaData(instanceID: current.id) == nil)
        #expect(viewModel.snapshot.todayQuestion?.id == replacement.instanceID)
    }

    @Test func removingAPhotoWhileItIsBeingPreparedDropsIt() async throws {
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let viewModel = makeViewModel(
            service: RecordingDailyChallengeService(
                snapshots: [
                    makeDailySnapshot(rows: [
                        dailyQuestionRow(answerKinds: [.photo]),
                    ]),
                ]
            ),
            mediaStore: mediaStore
        )
        await viewModel.configure(currentUserID: user)
        let question = try #require(viewModel.snapshot.todayQuestion)

        // Large enough that compressing it takes a moment.
        let photo = dailyLargeSampleImageData()
        let staging = Task { await viewModel.stagePhoto(photo, for: question.id) }
        for _ in 0..<10_000 where !viewModel.isPreparingPhoto(for: question.id) {
            await Task.yield()
        }
        try #require(viewModel.isPreparingPhoto(for: question.id))
        #expect(!viewModel.hasDraftToSubmit(for: question))
        viewModel.removeStagedMedia(for: question.id)
        await staging.value

        #expect(viewModel.stagedMediaData(for: question.id) == nil)
        #expect(mediaStore.stagedMediaData(instanceID: question.id) == nil)
        #expect(!viewModel.hasDraftToSubmit(for: question))
    }

    @Test func anAnswerTheServerRefusesForGoodStopsRetryingAndReturnsToTheDraft() async throws {
        let gateway = RecordingDailyChallengeGateway()
        await gateway.failSubmits(
            with: PaeoniaConvexError.server(
                code: "23514",
                message: "daily answer timestamp is outside the question day"
            )
        )
        let restored = LockedBox<[UUID: DailyAnswerDraft]>([:])
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: RecordingMediaUploadService(assetID: UUID()),
            gateway: gateway,
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore(),
            restoreDraft: { _, instanceID, draft in restored.mutate { $0[instanceID] = draft } }
        )
        let instanceID = UUID()
        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: UUID(),
            content: .textAndPartnerChoice("Because they plan", TestDailyChallengeIDs.partnerUser)
        )

        let result = try await handler.send(
            dailyPendingSnapshot(requestData: try JSONEncoder().encode(payload)),
            context: dailyChallengeSyncContext()
        )

        guard case .terminalFailure = result else {
            Issue.record("Expected a terminal failure, got \(result)")
            return
        }
        #expect(restored.value[instanceID] == DailyAnswerDraft(
            text: "Because they plan",
            partnerChoiceUserID: TestDailyChallengeIDs.partnerUser
        ))
    }

    @Test func anAccessErrorKeepsTheAnswerQueuedForARetry() async throws {
        let gateway = RecordingDailyChallengeGateway()
        await gateway.failSubmits(
            with: PaeoniaConvexError.server(code: "42501", message: "active entitled couple access is required")
        )
        let restored = LockedBox<[UUID: DailyAnswerDraft]>([:])
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: RecordingMediaUploadService(assetID: UUID()),
            gateway: gateway,
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore(),
            restoreDraft: { _, instanceID, draft in restored.mutate { $0[instanceID] = draft } }
        )
        let payload = DailySubmitAnswerOperationPayload(instanceID: UUID(), answerID: UUID(), content: .text("Hi"))
        let operation = dailyPendingSnapshot(requestData: try JSONEncoder().encode(payload))

        // Access can come back (for example after the subscription renews), so the
        // drain records a retry instead of dropping the answer.
        await #expect(throws: PaeoniaConvexError.self) {
            try await handler.send(operation, context: dailyChallengeSyncContext())
        }
        #expect(restored.value.isEmpty)
    }
}

@MainActor
private func dailyLargeSampleImageData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 2_400))
    let image = renderer.image { context in
        for row in 0..<24 {
            for column in 0..<24 {
                UIColor(hue: CGFloat(row * 24 + column) / 576, saturation: 0.7, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: column * 100, y: row * 100, width: 100, height: 100))
            }
        }
    }
    return image.jpegData(compressionQuality: 1) ?? Data()
}

/// Delegates to an in-memory outbox, but can hold `inFlightOperations` reads after
/// they've read the store, like a slow read that started before a send.
private actor GatedReadPendingStore: PendingSyncOperationPersisting {
    private let base = InMemoryPendingSyncOperationRepository()
    private var holdsReads = false
    private var heldReads: [CheckedContinuation<Void, Never>] = []
    private(set) var heldReadCount = 0

    func holdReads() {
        holdsReads = true
    }

    func releaseReads() {
        holdsReads = false
        heldReads.forEach { $0.resume() }
        heldReads = []
    }

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        let snapshot = try await base.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
        if holdsReads {
            heldReadCount += 1
            await withCheckedContinuation { heldReads.append($0) }
        }
        return snapshot
    }

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        try await base.enqueue(request)
    }

    func readyOperations(ownerUserID: UUID, limit: Int, now: Date) async throws -> [PendingSyncOperationSnapshot] {
        try await base.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
        try await base.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }

    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSending(clientOperationID: clientOperationID, at: date)
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSucceeded(clientOperationID: clientOperationID, at: date)
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) async throws {
        try await base.markRetryableFailure(
            clientOperationID: clientOperationID,
            errorDescription: errorDescription,
            nextRetryAt: nextRetryAt,
            at: date
        )
    }

    func markTerminalFailure(clientOperationID: UUID, errorDescription: String, at date: Date) async throws {
        try await base.markTerminalFailure(
            clientOperationID: clientOperationID,
            errorDescription: errorDescription,
            at: date
        )
    }

    func deleteCompleted(ownerUserID: UUID) async throws {
        try await base.deleteCompleted(ownerUserID: ownerUserID)
    }

    func resetInFlight(ownerUserID: UUID) async throws {
        try await base.resetInFlight(ownerUserID: ownerUserID)
    }
}
