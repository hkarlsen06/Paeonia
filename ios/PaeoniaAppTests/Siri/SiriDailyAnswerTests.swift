import Foundation
import Testing
import SwiftData
@testable import PaeoniaApp

@MainActor
struct SiriDailyAnswerTests {
    private let couple = SiriCouple(
        ownerUserID: TestDailyChallengeIDs.currentUser, coupleID: TestDailyChallengeIDs.couple,
        partnerUserID: TestDailyChallengeIDs.partnerUser, partnerName: "Partner")

    @Test func tabsReuseTheSiriModelAndItsUnsentDraft() {
        let context = SiriAppContext()
        let siriModel = context.dailyChallengeModel()
        let questionID = UUID()
        siriModel.setDraftText("Unfinished answer", for: questionID)
        let tabs = MainTabModels(
            dependencies: RootFeatureDependencies(),
            pairingCelebrationStore: TestPairingCelebrationStore(), siriContext: context)

        #expect(tabs.dailyChallenge === siriModel)
        #expect(tabs.dailyChallenge.draftText(for: questionID) == "Unfinished answer")
        #expect(context.dailyChallengeModel() === tabs.dailyChallenge)
    }

    @Test func queuesExactQuestionAndPreservesExistingDraft() async throws {
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let store = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        let drafts = InMemoryDailyChallengeDraftStore()
        let model = DailyChallengeViewModel(
            service: RecordingDailyChallengeService(snapshots: [makeDailySnapshot(rows: [dailyQuestionRow()])]),
            draftStore: drafts, pendingOperationStore: store, now: { TestDailyChallengeIDs.startsAt })
        await model.configure(currentUserID: couple.ownerUserID)
        let question = try #require(model.snapshot.todayQuestion)
        model.setDraftText("Unfinished", for: question.id)
        await #expect(throws: SiriFailure.self) {
            try await model.submitSiriText("New answer", instanceID: question.id, couple: couple) { true }
        }
        #expect(model.draftText(for: question.id) == "Unfinished")
        model.clearDraft(for: question.id)
        try await model.submitSiriText(" New answer ", instanceID: question.id, couple: couple) { true }
        let operations = try await store.inFlightOperations(ownerUserID: couple.ownerUserID, kind: .submitDailyAnswer)
        let payload = try JSONDecoder().decode(
            DailySubmitAnswerOperationPayload.self, from: #require(operations.first?.requestData))
        #expect(payload.instanceID == question.id)
        #expect(payload.content == .text("New answer"))
        await #expect(throws: SiriFailure.self) {
            try await model.submitSiriText("Duplicate", instanceID: question.id, couple: couple) { true }
        }
    }

    @Test func refusesChangedQuestionRolloverAndLostAccess() async throws {
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let store = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        let model = DailyChallengeViewModel(
            service: RecordingDailyChallengeService(snapshots: [makeDailySnapshot(rows: [dailyQuestionRow()])]),
            draftStore: InMemoryDailyChallengeDraftStore(), pendingOperationStore: store,
            now: { TestDailyChallengeIDs.startsAt })
        await model.configure(currentUserID: couple.ownerUserID)
        let question = try #require(model.snapshot.todayQuestion)
        await #expect(throws: SiriFailure.self) {
            try await model.submitSiriText("Answer", instanceID: UUID(), couple: couple) { true }
        }
        await #expect(throws: SiriFailure.self) {
            try await model.submitSiriText("Answer", instanceID: question.id, couple: couple) { false }
        }
        model.apply(.init(snapshot: makeDailySnapshot(rows: [dailyQuestionRow(
            endsAt: TestDailyChallengeIDs.startsAt, instanceID: question.id)]), streak: .none))
        await #expect(throws: SiriFailure.self) {
            try await model.submitSiriText("Answer", instanceID: question.id, couple: couple) { true }
        }
        #expect(try await store.inFlightOperations(ownerUserID: couple.ownerUserID, kind: .submitDailyAnswer).isEmpty)
        #expect(model.draftText(for: question.id).isEmpty)
    }

    @Test(arguments: ["", String(repeating: "a", count: DailyAnswerDraft.maxTextLength + 1)])
    func refusesInvalidTextWithoutReplacingDraft(_ text: String) async throws {
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let store = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        let model = DailyChallengeViewModel(
            service: RecordingDailyChallengeService(snapshots: [makeDailySnapshot(rows: [dailyQuestionRow()])]),
            draftStore: InMemoryDailyChallengeDraftStore(), pendingOperationStore: store,
            now: { TestDailyChallengeIDs.startsAt })
        await model.configure(currentUserID: couple.ownerUserID)
        let question = try #require(model.snapshot.todayQuestion)
        await #expect(throws: SiriFailure.self) {
            try await model.submitSiriText(text, instanceID: question.id, couple: couple) { true }
        }
        #expect(try await store.inFlightOperations(ownerUserID: couple.ownerUserID, kind: .submitDailyAnswer).isEmpty)
        #expect(!model.hasDraftContent(for: question.id))
    }

    @Test(arguments: [false, true])
    func refusesNonTextQuestionAndExistingAnswer(answered: Bool) async throws {
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let store = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        let model = DailyChallengeViewModel(
            service: RecordingDailyChallengeService(snapshots: [makeDailySnapshot(rows: [dailyQuestionRow(
                answerKinds: answered ? [.text] : [.photo], ownAnswerID: answered ? UUID() : nil)])]),
            draftStore: InMemoryDailyChallengeDraftStore(), pendingOperationStore: store,
            now: { TestDailyChallengeIDs.startsAt })
        await model.configure(currentUserID: couple.ownerUserID)
        let question = try #require(model.snapshot.todayQuestion)
        await #expect(throws: SiriFailure.self) {
            try await model.submitSiriText("Answer", instanceID: question.id, couple: couple) { true }
        }
        #expect(try await store.inFlightOperations(ownerUserID: couple.ownerUserID, kind: .submitDailyAnswer).isEmpty)
        #expect(!model.hasDraftContent(for: question.id))
    }

}
