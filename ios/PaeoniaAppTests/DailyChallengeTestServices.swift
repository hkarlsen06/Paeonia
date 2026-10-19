import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

actor RecordingDailyChallengeService: DailyChallengeServicing {
    private var snapshots: [DailyChallengeSnapshot]
    private let advancesSnapshotsOnLoad: Bool
    private let shuffleSnapshot: DailyChallengeSnapshot?
    private let loadError: Error?
    private let loadErrorsByAttempt: [Int: Error]
    private let loadProbe: DailyChallengeSyncNudgeProbe?
    private let historyQuestions: [DailyChallengeQuestion]
    private let historyReloadError: Error?
    private let streak: CoupleStreak
    private var historyLoadCount = 0
    private(set) var shuffledSlots: [Int] = []
    private(set) var loadCount = 0

    init(
        snapshots: [DailyChallengeSnapshot],
        advancesSnapshotsOnLoad: Bool = false,
        shuffleSnapshot: DailyChallengeSnapshot? = nil,
        loadError: Error? = nil,
        loadErrorsByAttempt: [Int: Error] = [:],
        loadProbe: DailyChallengeSyncNudgeProbe? = nil,
        historyQuestions: [DailyChallengeQuestion] = [],
        historyReloadError: Error? = nil,
        streak: CoupleStreak = .none
    ) {
        self.snapshots = snapshots
        self.advancesSnapshotsOnLoad = advancesSnapshotsOnLoad
        self.shuffleSnapshot = shuffleSnapshot
        self.loadError = loadError
        self.loadErrorsByAttempt = loadErrorsByAttempt
        self.loadProbe = loadProbe
        self.historyQuestions = historyQuestions
        self.historyReloadError = historyReloadError
        self.streak = streak
    }

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeLoadResult {
        loadCount += 1
        if let loadError {
            throw loadError
        }
        if let loadError = loadErrorsByAttempt[loadCount] {
            throw loadError
        }
        await loadProbe?.blockUntilReleased()
        let snapshot: DailyChallengeSnapshot
        if advancesSnapshotsOnLoad, !snapshots.isEmpty {
            snapshot = snapshots.removeFirst()
        } else {
            snapshot = snapshots.first ?? .empty(currentUserID: currentUserID)
        }
        return DailyChallengeLoadResult(snapshot: snapshot, streak: streak)
    }

    func loadHistory(currentUserID _: UUID) throws -> [DailyChallengeQuestion] {
        historyLoadCount += 1
        if historyLoadCount > 1, let historyReloadError {
            throw historyReloadError
        }
        return historyQuestions
    }

    func loadStreak() throws -> CoupleStreak {
        streak
    }

    func startToday(
        currentUserID: UUID,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(
            snapshot: snapshots.first ?? .empty(currentUserID: currentUserID),
            streak: streak
        )
    }

    func editTextAnswer(
        instanceID _: UUID,
        text _: String,
        operation _: SyncClientOperation
    ) throws -> UUID {
        UUID()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> UUID {
        UUID()
    }

    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber: Int,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        shuffledSlots.append(slotNumber)
        return DailyChallengeLoadResult(
            snapshot: shuffleSnapshot ?? snapshots.first ?? .empty(currentUserID: currentUserID),
            streak: streak
        )
    }
}

actor RecordingDailyChallengeReadGateway: DailyChallengeGateway {
    private let rows: [DailyQuestionRow]
    private let detailsByCoupleDayID: [UUID: [DailyAnswerDetailRow]]
    private let historyRows: [DailyQuestionRow]
    private let historyDetails: [DailyAnswerDetailRow]
    private(set) var loadedAnswerDetailCoupleDayIDs: [UUID] = []
    private(set) var todaySnapshotLoadCount = 0
    private(set) var startSnapshotLoadCount = 0
    private(set) var shuffleSnapshotLoadCount = 0
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

    func loadTodaySnapshot() throws -> DailyChallengeRemoteSnapshotRow {
        todaySnapshotLoadCount += 1
        return snapshotRow(rows: rows)
    }

    func startDailyChallenge(operation _: SyncClientOperation) throws -> DailyChallengeRemoteSnapshotRow {
        startSnapshotLoadCount += 1
        return snapshotRow(rows: rows)
    }

    func loadHistoryQuestions() throws -> [DailyQuestionRow] {
        historyQuestionLoadCount += 1
        return historyRows
    }

    func loadHistoryAnswerDetails() throws -> [DailyAnswerDetailRow] {
        historyDetailLoadCount += 1
        return historyDetails
    }

    func loadCoupleStreak() throws -> CoupleStreak {
        .none
    }

    func loadAnswerDetails(coupleDayID: UUID) throws -> [DailyAnswerDetailRow] {
        loadedAnswerDetailCoupleDayIDs.append(coupleDayID)
        return detailsByCoupleDayID[coupleDayID] ?? []
    }

    func submitAnswer(
        instanceID _: UUID,
        answerID: UUID,
        payload _: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) throws -> UUID {
        answerID
    }

    func editTextAnswer(
        instanceID _: UUID,
        text _: String,
        operation _: SyncClientOperation
    ) throws -> UUID {
        UUID()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> UUID {
        UUID()
    }

    func shuffleQuestion(
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeRemoteSnapshotRow {
        shuffleSnapshotLoadCount += 1
        return snapshotRow(rows: rows)
    }

    private func snapshotRow(rows: [DailyQuestionRow]) -> DailyChallengeRemoteSnapshotRow {
        var seenCoupleDayIDs = Set<UUID>()
        let answerDetails = rows
            .map(\.coupleDayID)
            .filter { seenCoupleDayIDs.insert($0).inserted }
            .flatMap { detailsByCoupleDayID[$0] ?? [] }

        return DailyChallengeRemoteSnapshotRow(
            questions: rows,
            answerDetails: answerDetails,
            streak: CoupleStreakRow(
                currentCount: 0,
                longestCount: 0,
                lastQualifiedDate: nil,
                restoreAvailable: false,
                restorableCount: 0,
                restoreDeadline: nil
            ),
            generatedAt: Date()
        )
    }
}

actor RecordingDailyChallengeGateway: DailyChallengeGateway {
    private(set) var submittedPayloads: [DailyAnswerPayload] = []
    private(set) var submittedAnswerIDs: [UUID] = []
    /// Topic answers, as (question id, instance id).
    private(set) var submittedTopicAnswers: [(questionID: UUID, instanceID: UUID)] = []
    private var submitError: (any Error)?

    func failSubmits(with error: any Error) {
        submitError = error
    }

    func loadTodaySnapshot() throws -> DailyChallengeRemoteSnapshotRow {
        DailyChallengeRemoteSnapshotRow(questions: [], answerDetails: [], streak: nil, generatedAt: Date())
    }

    func startDailyChallenge(operation _: SyncClientOperation) throws -> DailyChallengeRemoteSnapshotRow {
        DailyChallengeRemoteSnapshotRow(questions: [], answerDetails: [], streak: nil, generatedAt: Date())
    }

    func loadHistoryQuestions() throws -> [DailyQuestionRow] { [] }

    func loadHistoryAnswerDetails() throws -> [DailyAnswerDetailRow] { [] }

    func loadCoupleStreak() throws -> CoupleStreak { .none }

    func loadAnswerDetails(coupleDayID _: UUID) throws -> [DailyAnswerDetailRow] { [] }

    func submitAnswer(
        instanceID _: UUID,
        answerID: UUID,
        payload: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) throws -> UUID {
        if let submitError {
            throw submitError
        }
        submittedPayloads.append(payload)
        submittedAnswerIDs.append(answerID)
        return UUID()
    }

    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) throws -> UUID {
        UUID()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> UUID {
        UUID()
    }

    func shuffleQuestion(
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeRemoteSnapshotRow {
        DailyChallengeRemoteSnapshotRow(questions: [], answerDetails: [], streak: nil, generatedAt: Date())
    }

    func submitTopicAnswer(
        questionID: UUID,
        instanceID: UUID,
        answerID: UUID,
        payload: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) throws {
        if let submitError {
            throw submitError
        }
        submittedPayloads.append(payload)
        submittedAnswerIDs.append(answerID)
        submittedTopicAnswers.append((questionID, instanceID))
    }
}

actor DailyChallengeSyncNudgeProbe {
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
