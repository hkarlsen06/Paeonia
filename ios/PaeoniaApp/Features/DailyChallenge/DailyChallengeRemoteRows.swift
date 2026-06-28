import Foundation

nonisolated struct DailyQuestionRow: Decodable, Equatable, Sendable {
    let coupleDayID: UUID
    let coupleID: UUID
    let localDate: String
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

    enum CodingKeys: String, CodingKey {
        case coupleDayID = "couple_day_id"
        case coupleID = "couple_id"
        case localDate = "local_date"
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

nonisolated struct CoupleStreakRow: Decodable, Equatable, Sendable {
    let currentCount: Int
    let longestCount: Int
    let lastQualifiedDate: String?
    let restoreAvailable: Bool
    let restorableCount: Int
    let restoreDeadline: Date?

    enum CodingKeys: String, CodingKey {
        case currentCount = "current_count"
        case longestCount = "longest_count"
        case lastQualifiedDate = "last_qualified_date"
        case restoreAvailable = "restore_available"
        case restorableCount = "restorable_count"
        case restoreDeadline = "restore_deadline"
    }

    var streak: CoupleStreak {
        CoupleStreak(
            currentCount: currentCount,
            longestCount: longestCount,
            lastQualifiedDate: lastQualifiedDate,
            restoreAvailable: restoreAvailable,
            restorableCount: restorableCount,
            restoreDeadline: restoreDeadline
        )
    }
}

nonisolated struct DailyAnswerDetailRow: Decodable, Equatable, Sendable {
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
