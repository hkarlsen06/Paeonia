import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct FirstDayAnswerDraftAdoptionTests {
    private let userID = TestDailyChallengeIDs.currentUser
    private let versionID = firstDayUUID(1)

    private func configuredViewModel(
        row: DailyQuestionRow,
        draftStore: InMemoryDailyChallengeDraftStore,
        firstDayStore: UserDefaultsFirstDayAnswerDraftStore,
        snapshotCache: InMemoryDailyChallengeSnapshotCache = InMemoryDailyChallengeSnapshotCache()
    ) async -> DailyChallengeViewModel {
        let viewModel = DailyChallengeViewModel(
            service: RecordingDailyChallengeService(snapshots: [makeDailySnapshot(rows: [row])]),
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: draftStore,
            firstDayDraftStore: firstDayStore,
            snapshotCache: snapshotCache
        )
        await viewModel.configure(currentUserID: userID)
        return viewModel
    }

    @Test func theDailyQuestionTakesTheUnsentFirstDayTextOnce() async throws {
        let firstDayStore = UserDefaultsFirstDayAnswerDraftStore(defaults: try firstDayTestDefaults())
        firstDayStore.setText("Half written", for: versionID, userID: userID)
        let draftStore = InMemoryDailyChallengeDraftStore()
        let instanceID = UUID()

        let viewModel = await configuredViewModel(
            row: dailyQuestionRow(
                instanceID: instanceID,
                questionVersionID: versionID
            ),
            draftStore: draftStore,
            firstDayStore: firstDayStore
        )

        #expect(viewModel.draftText(for: instanceID) == "Half written")
        #expect(draftStore.drafts(for: userID)[instanceID]?.text == "Half written")
        #expect(firstDayStore.texts(for: userID).isEmpty)
    }

    /// The copy of an earlier day saved on this phone shows first. Its questions
    /// must not use up the first day text before the server's answer arrives.
    @Test func aCachedEarlierDayLeavesTheFirstDayTextForTheServerLoad() async throws {
        let firstDayStore = UserDefaultsFirstDayAnswerDraftStore(defaults: try firstDayTestDefaults())
        firstDayStore.setText("Half written", for: versionID, userID: userID)
        let cache = InMemoryDailyChallengeSnapshotCache()
        cache.save(
            DailyChallengeRemoteSnapshotRow(
                questions: [
                    dailyQuestionRow(questionVersionID: firstDayUUID(2)),
                ],
                answerDetails: [],
                streak: CoupleStreakRow(
                    currentCount: 0,
                    longestCount: 0,
                    lastQualifiedDate: nil,
                    restoreAvailable: false,
                    restorableCount: 0,
                    restoreDeadline: nil
                ),
                generatedAt: TestDailyChallengeIDs.startsAt
            ),
            ownerUserID: userID
        )
        let instanceID = UUID()

        let viewModel = await configuredViewModel(
            row: dailyQuestionRow(
                instanceID: instanceID,
                questionVersionID: versionID
            ),
            draftStore: InMemoryDailyChallengeDraftStore(),
            firstDayStore: firstDayStore,
            snapshotCache: cache
        )

        #expect(viewModel.draftText(for: instanceID) == "Half written")
    }

    @Test func theQuestionsOwnDraftWinsAndTheFirstDayTextIsStillTaken() async throws {
        let firstDayStore = UserDefaultsFirstDayAnswerDraftStore(defaults: try firstDayTestDefaults())
        firstDayStore.setText("From before pairing", for: versionID, userID: userID)
        let draftStore = InMemoryDailyChallengeDraftStore()
        let instanceID = UUID()
        draftStore.setDraft(DailyAnswerDraft(text: "Typed today"), for: instanceID, userID: userID)

        let viewModel = await configuredViewModel(
            row: dailyQuestionRow(
                instanceID: instanceID,
                questionVersionID: versionID
            ),
            draftStore: draftStore,
            firstDayStore: firstDayStore
        )

        #expect(viewModel.draftText(for: instanceID) == "Typed today")
        #expect(firstDayStore.texts(for: userID).isEmpty)
    }

    /// A first day question missing from the questions has ended. Its text must not
    /// wait for the same question to come back on a later day.
    @Test func textForAFirstDayQuestionThatEndedIsNotKept() async throws {
        let firstDayStore = UserDefaultsFirstDayAnswerDraftStore(defaults: try firstDayTestDefaults())
        firstDayStore.setText("From an earlier day", for: firstDayUUID(2), userID: userID)
        let instanceID = UUID()

        let viewModel = await configuredViewModel(
            row: dailyQuestionRow(
                instanceID: instanceID,
                questionVersionID: versionID
            ),
            draftStore: InMemoryDailyChallengeDraftStore(),
            firstDayStore: firstDayStore
        )

        #expect(viewModel.draftText(for: instanceID).isEmpty)
        #expect(firstDayStore.texts(for: userID).isEmpty)
    }
}
