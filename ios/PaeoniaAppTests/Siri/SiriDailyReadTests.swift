import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct SiriDailyReadTests {
    private let couple = SiriCouple(
        ownerUserID: TestDailyChallengeIDs.currentUser, coupleID: TestDailyChallengeIDs.couple,
        partnerUserID: TestDailyChallengeIDs.partnerUser, partnerName: "Partner")

    @Test(arguments: [false, true])
    func askingForTodayCreatesTheQuestionWhenNoneIsActive(afterMidnight: Bool) async throws {
        let now = TestDailyChallengeIDs.startsAt
        let previous = afterMidnight
            ? makeDailySnapshot(rows: [dailyQuestionRow(endsAt: now)])
            : .empty(currentUserID: couple.ownerUserID)
        let row = dailyQuestionRow(coupleDayID: UUID(), startsAt: now)
        let current = makeDailySnapshot(rows: [row])
        let service = RecordingDailyChallengeService(
            snapshots: [previous, current], advancesSnapshotsOnLoad: true)
        let model = DailyChallengeViewModel(service: service, now: { now })
        await model.configure(currentUserID: couple.ownerUserID)
        #expect(model.snapshot.todayQuestion == nil)

        let question = try await model.todayQuestionForSiri(couple: couple) { true }

        #expect(question.id == row.instanceID)
        #expect(model.snapshot.todayQuestion?.id == question.id)
        #expect(await service.startCount == 1)
        let again = try await model.todayQuestionForSiri(couple: couple) { true }
        #expect(again.id == question.id)
        #expect(await service.startCount == 1)
    }

    @Test func overlappingStartsBothWaitForTheSameQuestion() async throws {
        let row = dailyQuestionRow()
        let probe = DailyChallengeSyncNudgeProbe()
        let service = RecordingDailyChallengeService(
            snapshots: [.empty(currentUserID: couple.ownerUserID), makeDailySnapshot(rows: [row])],
            advancesSnapshotsOnLoad: true, startProbe: probe)
        let model = DailyChallengeViewModel(service: service, now: { TestDailyChallengeIDs.startsAt })
        await model.configure(currentUserID: couple.ownerUserID)
        let first = Task { await model.startToday() }
        while await service.startCount == 0 { await Task.yield() }
        var secondEntered = false
        let second = Task {
            secondEntered = true
            await model.startToday()
            #expect(model.snapshot.todayQuestion?.id == row.instanceID)
        }
        while !secondEntered { await Task.yield() }
        await probe.release()
        await first.value
        await second.value
        #expect(model.snapshot.todayQuestion?.id == row.instanceID)
        #expect(await service.startCount == 1)
    }

    @Test func signingOutDuringAStartDoesNotRestoreTheOldQuestion() async throws {
        let row = dailyQuestionRow()
        let probe = DailyChallengeSyncNudgeProbe()
        let service = RecordingDailyChallengeService(
            snapshots: [.empty(currentUserID: couple.ownerUserID), makeDailySnapshot(rows: [row])],
            advancesSnapshotsOnLoad: true, startProbe: probe)
        let model = DailyChallengeViewModel(service: service, now: { TestDailyChallengeIDs.startsAt })
        await model.configure(currentUserID: couple.ownerUserID)
        let start = Task { await model.startToday() }
        while await service.startCount == 0 { await Task.yield() }

        await model.configure(currentUserID: nil)
        await probe.release()
        await start.value

        #expect(model.snapshot.currentUserID == nil)
        #expect(model.snapshot.todayQuestion == nil)
        #expect(!model.isStarting)
    }

    @Test func readingAnExistingQuestionDoesNotReplaceIt() async throws {
        let row = dailyQuestionRow()
        let service = RecordingDailyChallengeService(snapshots: [makeDailySnapshot(rows: [row])])
        let model = DailyChallengeViewModel(service: service, now: { TestDailyChallengeIDs.startsAt })
        await model.configure(currentUserID: couple.ownerUserID)

        let question = try await model.todayQuestionForSiri(couple: couple) { true }

        #expect(question.id == row.instanceID)
        #expect(await service.startCount == 0)
    }

    @Test func lostAccessCannotStartOrReturnAQuestion() async throws {
        let service = RecordingDailyChallengeService(snapshots: [.empty(currentUserID: couple.ownerUserID)])
        let model = DailyChallengeViewModel(service: service)
        await model.configure(currentUserID: couple.ownerUserID)

        await #expect(throws: SiriFailure.self) {
            try await model.todayQuestionForSiri(couple: couple) { false }
        }
        #expect(model.snapshot.todayQuestion == nil)
        #expect(await service.startCount == 0)
    }

    @Test(arguments: [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut])
    func failedStartDoesNotReturnYesterdaysQuestion(code: Int) async throws {
        let now = TestDailyChallengeIDs.startsAt
        let expired = makeDailySnapshot(rows: [dailyQuestionRow(endsAt: now)])
        let service = RecordingDailyChallengeService(
            snapshots: [expired], startError: NSError(domain: NSURLErrorDomain, code: code))
        let model = DailyChallengeViewModel(service: service, now: { now })
        await model.configure(currentUserID: couple.ownerUserID)

        await #expect(throws: SiriFailure.self) {
            try await model.todayQuestionForSiri(couple: couple) { true }
        }
        #expect(model.snapshot.todayQuestion == nil)
    }
}
