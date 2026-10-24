import Foundation

#if DEBUG
actor PreviewDailyChallengeService: DailyChallengeServicing {
    static let userID = UUID()
    private let todayID = UUID()

    /// Today's question, which the partner hasn't answered yet, and yesterday's, which
    /// waits for the user's answer to show the partner's.
    func loadToday(currentUserID: UUID) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(
            snapshot: DailyChallengeSnapshot(
                currentUserID: currentUserID,
                coupleDayID: todayID,
                questions: [
                    previewDailyQuestion(
                        coupleDayID: todayID,
                        prompt: "What is one small moment from today that made you think of your partner?",
                        short: "A small moment today"
                    ),
                    previewDailyQuestion(
                        coupleDayID: UUID(),
                        localDate: "2026-06-26",
                        isCurrentDay: false,
                        prompt: "What is a favourite memory of the two of you from this month?",
                        short: "A favourite memory",
                        partnerAnswered: true
                    ),
                ],
                refreshedAt: .now
            ),
            streak: .none
        )
    }

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) throws -> DailyChallengeLoadResult {
        try loadToday(currentUserID: currentUserID)
    }

    func loadHistory(currentUserID: UUID) throws -> [DailyChallengeQuestion] {
        [
            previewHistoryQuestion(
                localDate: "2026-06-27",
                prompt: "What small moment made you think of your partner today?",
                ownText: "Your text came up on my lock screen mid-meeting.",
                partnerText: "I saw a couple on the tram holding hands like we do.",
                currentUserID: currentUserID
            ),
            previewHistoryQuestion(
                localDate: "2026-06-26",
                prompt: "What's one thing the two of you are looking forward to?",
                ownText: "The long weekend with nothing planned.",
                partnerText: "Cooking that pasta again, but slower this time.",
                currentUserID: currentUserID
            ),
            previewHistoryQuestion(
                localDate: "2026-06-25",
                prompt: "What made you laugh recently?",
                ownText: "Your voice note where you forgot what you were saying.",
                partnerText: "The dog video you sent at 1am.",
                currentUserID: currentUserID
            ),
        ]
    }

    func loadStreak() throws -> CoupleStreak {
        CoupleStreak(
            currentCount: 6,
            longestCount: 12,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil
        )
    }

    func submitAnswer(
        instanceID _: UUID,
        answerID _: UUID,
        payload _: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) throws -> UUID {
        UUID()
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
        currentUserID: UUID,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        try loadToday(currentUserID: currentUserID)
    }
}

nonisolated func previewDailyQuestion(
    coupleDayID: UUID,
    localDate: String = "2026-06-27",
    isCurrentDay: Bool = true,
    prompt: String,
    short: String,
    answerKinds: [DailyChallengeAnswerKind] = [.text],
    partnerAnswered: Bool = false
) -> DailyChallengeQuestion {
    let startsAt = isCurrentDay ? Date.now : Date.now.addingTimeInterval(-86_400)
    return DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: coupleDayID,
        coupleID: UUID(),
        localDate: localDate,
        effectiveLocalDate: localDate,
        startsAt: startsAt,
        endsAt: startsAt.addingTimeInterval(86_400),
        status: .active,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "preview_question",
        prompt: prompt,
        shortPrompt: short,
        answerKinds: answerKinds,
        ownAnswer: nil,
        partnerAnswer: partnerAnswered ? DailyQuestionAnswerSummary(id: UUID(), answeredAt: .now) : nil,
        canViewPartnerAnswer: false,
        ownAnswerDetail: nil,
        partnerAnswerDetail: nil,
        isCurrentDay: isCurrentDay
    )
}

/// A fully-answered question for the history preview: both people answered with text
/// and both replies are revealed, so the read card shows a complete exchange.
nonisolated func previewHistoryQuestion(
    localDate: String,
    prompt: String,
    ownText: String,
    partnerText: String,
    currentUserID: UUID = PreviewDailyChallengeService.userID,
    partnerUserID: UUID = UUID()
) -> DailyChallengeQuestion {
    let answeredAt = Date()
    let ownDetail = previewHistoryAnswerDetail(
        answerUserID: currentUserID,
        answeredAt: answeredAt,
        isOwnAnswer: true,
        text: ownText
    )
    let partnerDetail = previewHistoryAnswerDetail(
        answerUserID: partnerUserID,
        answeredAt: answeredAt,
        isOwnAnswer: false,
        text: partnerText
    )

    return DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: UUID(),
        coupleID: UUID(),
        localDate: localDate,
        effectiveLocalDate: localDate,
        startsAt: answeredAt,
        endsAt: answeredAt.addingTimeInterval(86_400),
        status: .active,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "preview_history_question",
        prompt: prompt,
        shortPrompt: prompt,
        answerKinds: [.text],
        ownAnswer: DailyQuestionAnswerSummary(id: ownDetail.answerID, answeredAt: answeredAt),
        partnerAnswer: DailyQuestionAnswerSummary(id: partnerDetail.answerID, answeredAt: answeredAt),
        canViewPartnerAnswer: true,
        ownAnswerDetail: ownDetail,
        partnerAnswerDetail: partnerDetail,
        isCurrentDay: false
    )
}

private nonisolated func previewHistoryAnswerDetail(
    answerUserID: UUID,
    answeredAt: Date,
    isOwnAnswer: Bool,
    text: String
) -> DailyQuestionAnswerDetail {
    DailyQuestionAnswerDetail(
        answerUserID: answerUserID,
        answerID: UUID(),
        answeredAt: answeredAt,
        isOwnAnswer: isOwnAnswer,
        canViewAnswer: true,
        textBody: text,
        selectedUserID: nil,
        mediaAssetIDs: []
    )
}
#endif
