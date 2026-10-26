import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

/// Builds a UUID from a fixed string for deterministic fixtures without force
/// unwrapping (the literals are always valid, so the fallback never runs).
func dailyFixedUUID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}

enum TestDailyChallengeIDs {
    static let currentUser = dailyFixedUUID("11111111-1111-1111-1111-111111111111")
    static let partnerUser = dailyFixedUUID("22222222-2222-2222-2222-222222222222")
    static let couple = dailyFixedUUID("33333333-3333-3333-3333-333333333333")
    static let coupleDay = dailyFixedUUID("44444444-4444-4444-4444-444444444444")
    static let previousCoupleDay = dailyFixedUUID("55555555-5555-5555-5555-555555555555")
    static let startsAt = Date(timeIntervalSince1970: 1_782_432_000)
    /// Far in the future, so the view model (which drops a day once its end passes)
    /// never treats the fixture day as ended.
    static let endsAt = Date(timeIntervalSince1970: 4_102_444_800)
    static let answerDate = Date(timeIntervalSince1970: 1_782_450_000)
}

/// The chat about a partner's story posted at `postedAt`, with one message from the partner.
func storyConversation(postedAt: Date, isUnread: Bool = false) -> SubjectConversation {
    let story = Story(
        id: UUID(),
        authorUserID: TestDailyChallengeIDs.partnerUser,
        mediaAssetID: UUID(),
        caption: nil,
        createdAt: postedAt
    )
    return SubjectConversation(
        subject: .story(story),
        summary: chatSummary(.story(story.id), at: postedAt),
        isUnread: isUnread
    )
}

/// The chat about a memory the partner added at `addedAt`, dated `memoryDate`, with one
/// message from the partner.
func memoryConversation(addedAt: Date, memoryDate: String, isUnread: Bool = false) -> SubjectConversation {
    let memoryID = UUID()
    let snapshot = MemorySnapshot(
        ownerUserID: TestDailyChallengeIDs.currentUser,
        memoryID: memoryID,
        coupleID: TestDailyChallengeIDs.couple,
        title: "Cabin weekend",
        memoryDate: memoryDate,
        place: nil,
        createdByUserID: TestDailyChallengeIDs.partnerUser,
        lastEditedByUserID: TestDailyChallengeIDs.partnerUser,
        revision: 1,
        moderationStatus: .visible,
        deletedAt: nil,
        createdAt: addedAt,
        updatedAt: addedAt,
        syncUpdatedAt: addedAt,
        ownNote: nil,
        partnerNote: nil,
        visibleMemoryMediaIDs: [],
        visibleMediaAssetIDs: [],
        media: [],
        threadID: UUID()
    )
    return SubjectConversation(
        subject: .memory(MemoryRecord(snapshot: snapshot)),
        summary: chatSummary(.memory(memoryID), at: addedAt),
        isUnread: isUnread
    )
}

private func chatSummary(_ subject: ThreadChatSubject, at date: Date) -> ThreadChatSummary {
    ThreadChatSummary(
        threadID: UUID(),
        coupleID: TestDailyChallengeIDs.couple,
        subject: subject,
        createdAt: date,
        updatedAt: date,
        lastMessageID: UUID(),
        lastMessageAt: date,
        lastMessageSenderUserID: TestDailyChallengeIDs.partnerUser,
        lastMessageBody: "Lovely"
    )
}

func makeDailySnapshot(
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

func dailyQuestionRow(
    coupleDayID: UUID = TestDailyChallengeIDs.coupleDay,
    localDate: String = "2026-06-27",
    effectiveLocalDate: String? = nil,
    startsAt: Date = TestDailyChallengeIDs.startsAt,
    endsAt: Date = TestDailyChallengeIDs.endsAt,
    instanceID: UUID = UUID(),
    questionVersionID: UUID = UUID(),
    status: String = "active",
    answerKinds: [DailyChallengeAnswerKind] = [.text],
    promptEN: String = "What small moment made you think of us today?",
    ownAnswerID: UUID? = nil,
    ownAnsweredAt: Date? = nil,
    partnerAnswerID: UUID? = nil,
    partnerAnsweredAt: Date? = nil,
    canViewPartnerAnswer: Bool = false,
    isCurrentDay: Bool = true
) -> DailyQuestionRow {
    DailyQuestionRow(
        coupleDayID: coupleDayID,
        coupleID: TestDailyChallengeIDs.couple,
        localDate: localDate,
        effectiveLocalDate: effectiveLocalDate,
        startsAt: startsAt,
        endsAt: endsAt,
        instanceID: instanceID,
        instanceStatus: status,
        questionID: UUID(),
        questionVersionID: questionVersionID,
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

func dailyAnswerDetail(
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

@MainActor
func dailySampleImageData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
    let image = renderer.image { context in
        UIColor.systemPink.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    return image.jpegData(compressionQuality: 0.9) ?? image.pngData() ?? Data()
}

func dailyFixedClientOperation() -> SyncClientOperation {
    SyncClientOperation(id: UUID(), clientID: UUID(), clientSequence: 1, localCreatedAt: Date())
}

func dailyPendingSnapshot(requestData: Data) -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: TestDailyChallengeIDs.currentUser,
        operation: dailyFixedClientOperation(),
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

func dailyChallengeSyncContext() -> SyncContext {
    SyncContext(
        session: SyncSession(userID: TestDailyChallengeIDs.currentUser, activeCoupleID: TestDailyChallengeIDs.couple),
        reason: .localChange,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository()
    )
}
