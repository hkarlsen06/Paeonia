import Foundation

nonisolated struct DailyChallengeRemoteSnapshotRow: Codable, Equatable, Sendable {
    let questions: [DailyQuestionRow]
    let answerDetails: [DailyAnswerDetailRow]
    let streak: CoupleStreakRow?
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case questions
        case answerDetails = "answer_details"
        case streak
        case generatedAt = "generated_at"
    }
}

nonisolated struct DailyQuestionRow: Codable, Equatable, Sendable {
    let coupleDayID: UUID
    let coupleID: UUID
    let localDate: String
    /// The couple-local date the question effectively belongs to — the day of its most
    /// recent answer. Returned by the history read model so an exchange completed after
    /// midnight lands on the day it was finished, not the day its instance was seeded.
    /// Absent on the "today" read model; callers fall back to `localDate`.
    let effectiveLocalDate: String?
    let startsAt: Date
    let endsAt: Date
    let instanceID: UUID
    let seededForUserID: UUID
    let slotNumber: Int
    let instanceStatus: String
    let questionID: UUID
    let questionVersionID: UUID
    let questionKey: String
    let promptEN: String
    let shortPromptEN: String
    let promptNB: String
    let shortPromptNB: String
    let answerKinds: [DailyChallengeAnswerKind]
    let ownAnswerID: UUID?
    let ownAnsweredAt: Date?
    let partnerAnswerID: UUID?
    let partnerAnsweredAt: Date?
    let canViewPartnerAnswer: Bool
    /// Present only on the "today" read model once it includes carried-over
    /// unresolved exchanges. Older backend responses omit it; those rows are
    /// treated as current-day rows for compatibility.
    let isCurrentDay: Bool?

    enum CodingKeys: String, CodingKey {
        case coupleDayID = "couple_day_id"
        case coupleID = "couple_id"
        case localDate = "local_date"
        case effectiveLocalDate = "effective_local_date"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case instanceID = "instance_id"
        case seededForUserID = "seeded_for_user_id"
        case slotNumber = "slot_number"
        case instanceStatus = "instance_status"
        case questionID = "question_id"
        case questionVersionID = "question_version_id"
        case questionKey = "question_key"
        case promptEN = "prompt_en"
        case shortPromptEN = "short_prompt_en"
        case promptNB = "prompt_nb"
        case shortPromptNB = "short_prompt_nb"
        case answerKinds = "answer_kinds"
        case ownAnswerID = "own_answer_id"
        case ownAnsweredAt = "own_answered_at"
        case partnerAnswerID = "partner_answer_id"
        case partnerAnsweredAt = "partner_answered_at"
        case canViewPartnerAnswer = "can_view_partner_answer"
        case isCurrentDay = "is_current_day"
    }

    func prompt(for locale: Locale) -> String {
        prefersNorwegian(locale) ? promptNB : promptEN
    }

    func shortPrompt(for locale: Locale) -> String {
        prefersNorwegian(locale) ? shortPromptNB : shortPromptEN
    }

    private func prefersNorwegian(_ locale: Locale) -> Bool {
        let languageCode = locale.language.languageCode?.identifier
        return languageCode == "nb" || languageCode == "no"
    }
}

nonisolated struct CoupleStreakRow: Codable, Equatable, Sendable {
    let currentCount: Int
    let longestCount: Int
    let lastQualifiedDate: String?
    let restoreAvailable: Bool
    let restorableCount: Int
    let restoreDeadline: Date?
    let currentUserContributedToday: Bool
    let partnerContributedToday: Bool

    init(
        currentCount: Int,
        longestCount: Int,
        lastQualifiedDate: String?,
        restoreAvailable: Bool,
        restorableCount: Int,
        restoreDeadline: Date?,
        currentUserContributedToday: Bool = false,
        partnerContributedToday: Bool = false
    ) {
        self.currentCount = currentCount
        self.longestCount = longestCount
        self.lastQualifiedDate = lastQualifiedDate
        self.restoreAvailable = restoreAvailable
        self.restorableCount = restorableCount
        self.restoreDeadline = restoreDeadline
        self.currentUserContributedToday = currentUserContributedToday
        self.partnerContributedToday = partnerContributedToday
    }

    enum CodingKeys: String, CodingKey {
        case currentCount = "current_count"
        case longestCount = "longest_count"
        case lastQualifiedDate = "last_qualified_date"
        case restoreAvailable = "restore_available"
        case restorableCount = "restorable_count"
        case restoreDeadline = "restore_deadline"
        case currentUserContributedToday = "current_user_contributed_today"
        case partnerContributedToday = "partner_contributed_today"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentCount = try container.decode(Int.self, forKey: .currentCount)
        longestCount = try container.decode(Int.self, forKey: .longestCount)
        lastQualifiedDate = try container.decodeIfPresent(String.self, forKey: .lastQualifiedDate)
        restoreAvailable = try container.decode(Bool.self, forKey: .restoreAvailable)
        restorableCount = try container.decode(Int.self, forKey: .restorableCount)
        restoreDeadline = try container.decodeIfPresent(Date.self, forKey: .restoreDeadline)
        currentUserContributedToday = try container.decodeIfPresent(
            Bool.self,
            forKey: .currentUserContributedToday
        ) ?? false
        partnerContributedToday = try container.decodeIfPresent(
            Bool.self,
            forKey: .partnerContributedToday
        ) ?? false
    }

    var streak: CoupleStreak {
        CoupleStreak(
            currentCount: currentCount,
            longestCount: longestCount,
            lastQualifiedDate: lastQualifiedDate,
            restoreAvailable: restoreAvailable,
            restorableCount: restorableCount,
            restoreDeadline: restoreDeadline,
            currentUserContributedToday: currentUserContributedToday,
            partnerContributedToday: partnerContributedToday
        )
    }
}

nonisolated struct DailyAnswerDetailRow: Codable, Equatable, Sendable {
    let coupleDayID: UUID
    let instanceID: UUID
    let seededForUserID: UUID
    let slotNumber: Int
    let answerUserID: UUID
    let answerID: UUID
    let answeredAt: Date
    let isOwnAnswer: Bool
    let canViewAnswer: Bool
    let textBody: String?
    let selectedUserID: UUID?
    let mediaAssetIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case coupleDayID = "couple_day_id"
        case instanceID = "instance_id"
        case seededForUserID = "seeded_for_user_id"
        case slotNumber = "slot_number"
        case answerUserID = "answer_user_id"
        case answerID = "answer_id"
        case answeredAt = "answered_at"
        case isOwnAnswer = "is_own_answer"
        case canViewAnswer = "can_view_answer"
        case textBody = "text_body"
        case selectedUserID = "selected_user_id"
        case mediaAssetIDs = "media_asset_ids"
    }

    var detail: DailyQuestionAnswerDetail {
        DailyQuestionAnswerDetail(
            answerUserID: answerUserID,
            answerID: answerID,
            answeredAt: answeredAt,
            isOwnAnswer: isOwnAnswer,
            canViewAnswer: canViewAnswer,
            textBody: textBody,
            selectedUserID: selectedUserID,
            mediaAssetIDs: mediaAssetIDs
        )
    }
}

extension DailyChallengeRemoteSnapshotRow {
    /// Converts the raw row into a `DailyChallengeLoadResult` using exactly the
    /// same field mapping as `SupabaseDailyChallengeService.makeResult`. Extracting
    /// this here lets both the live service and the local snapshot cache build
    /// domain objects through a single path — no risk of the two diverging.
    ///
    /// `nonisolated` so it can be called from any isolation context (actors, tasks,
    /// and the cache — which is not isolated).
    nonisolated func loadResult(
        currentUserID: UUID,
        locale: Locale = .current
    ) -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(
            snapshot: DailyChallengeSnapshot.make(
                currentUserID: currentUserID,
                rows: questions,
                answerDetails: answerDetails,
                locale: locale,
                refreshedAt: generatedAt
            ),
            streak: streak?.streak ?? .none
        )
    }
}
