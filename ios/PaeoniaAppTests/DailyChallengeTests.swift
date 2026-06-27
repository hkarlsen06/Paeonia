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

    @Test func unansweredOwnQuestionsAreVisibleAndAnswerable() {
        let snapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 2, seededForUserID: TestDailyChallengeIDs.currentUser),
            questionRow(slotNumber: 3, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])

        #expect(snapshot.ownQuestions.count == 3)
        #expect(snapshot.partnerStartedQuestions.isEmpty)
        #expect(snapshot.progress.ownAnsweredCount == 0)
        #expect(snapshot.ownQuestions.allSatisfy(\.canSubmitTextAnswer))
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

    @Test func partnerAnsweredUnrevealedQuestionCanBeAnsweredButBodyStaysHidden() {
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
    @Test func draftsSurviveReopenAndClearOnSubmit() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let store = InMemoryDailyChallengeDraftStore()

        let first = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: store
        )
        await first.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(first.snapshot.ownQuestions.first)
        first.setDraftText("Halfway through a thought", for: question.id)

        // Reopen / relaunch: a fresh view model restores the saved drafts.
        let second = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: store
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

    @MainActor
    @Test func emptyAnswerDoesNotCallSubmitService() async throws {
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
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        await viewModel.submitAnswer(for: question)

        #expect(viewModel.notice == .emptyAnswer)
        #expect(await service.submittedTexts.isEmpty)
    }

    @MainActor
    @Test func submitAnswerSendsTrimmedTextPayload() async throws {
        let baseSnapshot = makeSnapshot(rows: [
            questionRow(slotNumber: 1, seededForUserID: TestDailyChallengeIDs.currentUser),
        ])
        let service = RecordingDailyChallengeService(snapshots: [baseSnapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
        )

        await viewModel.configure(currentUserID: TestDailyChallengeIDs.currentUser)
        let question = try #require(viewModel.snapshot.ownQuestions.first)
        viewModel.setDraftText("  Thinking of you  ", for: question.id)

        await viewModel.submitAnswer(for: question)

        #expect(await service.submittedPayloads == [.text("Thinking of you")])
        #expect(viewModel.draftText(for: question.id).isEmpty)
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
    @Test func submitAnswerSendsPartnerChoicePayload() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.partnerChoice]
            ),
        ])
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore()
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
        #expect(await service.submittedPayloads == [.partnerChoice(TestDailyChallengeIDs.partnerUser)])
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
    @Test func submitPhotoAnswerUploadsThenSubmitsMediaPayload() async throws {
        let snapshot = makeSnapshot(rows: [
            questionRow(
                slotNumber: 1,
                seededForUserID: TestDailyChallengeIDs.currentUser,
                answerKinds: [.photo, .text]
            ),
        ])
        let assetID = UUID()
        let service = RecordingDailyChallengeService(snapshots: [snapshot])
        let uploader = RecordingMediaUploadService(assetID: assetID)
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: InMemoryDailyChallengeDraftStore(),
            mediaUploadService: uploader,
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore()
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
        #expect(viewModel.stagedPhotoData(for: question.id) != nil)

        await viewModel.submitAnswer(for: question)

        #expect(await uploader.uploadCount == 1)
        #expect(await service.submittedPayloads == [.media([assetID])])
        // The same answer id is reserved for the media and submitted with it.
        #expect(await uploader.lastAnswerID != nil)
        // Staged bytes are cleaned up once the photo is sent.
        #expect(viewModel.stagedPhotoData(for: question.id) == nil)
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

private enum TestDailyChallengeIDs {
    static let currentUser = fixedUUID("11111111-1111-1111-1111-111111111111")
    static let partnerUser = fixedUUID("22222222-2222-2222-2222-222222222222")
    static let couple = fixedUUID("33333333-3333-3333-3333-333333333333")
    static let coupleDay = fixedUUID("44444444-4444-4444-4444-444444444444")
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
    slotNumber: Int,
    seededForUserID: UUID,
    status: String = "active",
    answerKinds: [DailyChallengeAnswerKind] = [.text],
    promptEN: String = "What small moment made you think of us today?",
    ownAnswerID: UUID? = nil,
    ownAnsweredAt: Date? = nil,
    partnerAnswerID: UUID? = nil,
    partnerAnsweredAt: Date? = nil,
    canViewPartnerAnswer: Bool = false
) -> DailyQuestionRow {
    DailyQuestionRow(
        coupleDayID: TestDailyChallengeIDs.coupleDay,
        coupleID: TestDailyChallengeIDs.couple,
        localDate: "2026-06-27",
        startsAt: TestDailyChallengeIDs.startsAt,
        endsAt: TestDailyChallengeIDs.endsAt,
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
        canViewPartnerAnswer: canViewPartnerAnswer
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
    private let shuffleSnapshot: DailyChallengeSnapshot?
    private let shuffleError: Error?
    private let editError: Error?
    private(set) var submittedPayloads: [DailyAnswerPayload] = []
    private(set) var editedTexts: [String] = []
    private(set) var shuffledSlots: [Int] = []

    /// Convenience for the text-answer assertions: the submitted text payloads only.
    var submittedTexts: [String] {
        submittedPayloads.compactMap { payload in
            if case let .text(body) = payload { return body }
            return nil
        }
    }

    init(
        snapshots: [DailyChallengeSnapshot],
        shuffleSnapshot: DailyChallengeSnapshot? = nil,
        shuffleError: Error? = nil,
        editError: Error? = nil
    ) {
        self.snapshots = snapshots
        self.shuffleSnapshot = shuffleSnapshot
        self.shuffleError = shuffleError
        self.editError = editError
    }

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeSnapshot {
        snapshots.first ?? .empty(currentUserID: currentUserID)
    }

    func startToday(
        currentUserID: UUID,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeSnapshot {
        snapshots.first ?? .empty(currentUserID: currentUserID)
    }

    func submitAnswer(
        instanceID _: UUID,
        answerID _: UUID,
        payload: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        submittedPayloads.append(payload)
        return UUID()
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

    init(assetID: UUID) {
        self.assetID = assetID
    }

    func uploadMedia(
        _: DailyAnswerUploadMedia,
        answerID: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        uploadCount += 1
        lastAnswerID = answerID
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
