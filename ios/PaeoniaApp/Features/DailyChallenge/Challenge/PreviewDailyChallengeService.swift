import Foundation

#if DEBUG
actor PreviewDailyChallengeService: DailyChallengeServicing {
    static let userID = UUID()
    private let partnerUserID = UUID()

    func loadToday(currentUserID: UUID) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(
            snapshot: DailyChallengeSnapshot(
                currentUserID: currentUserID,
                coupleDayID: UUID(),
                questions: [
                    previewDailyQuestion(
                        slot: 1,
                        seededFor: currentUserID,
                        origin: .own,
                        prompt: "What small moment made you think of us today?",
                        short: "A small moment today"
                    ),
                    previewDailyQuestion(
                        slot: 2,
                        seededFor: currentUserID,
                        origin: .own,
                        prompt: "What's one thing you're looking forward to together?",
                        short: "Something to look forward to",
                        answerKinds: [.voice, .text]
                    ),
                    previewDailyQuestion(
                        slot: 1,
                        seededFor: partnerUserID,
                        origin: .partner,
                        prompt: "What's a favourite memory of us from this month?",
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
                slot: 1,
                seededFor: currentUserID,
                prompt: "What small moment made you think of us today?",
                ownText: "Your text came up on my lock screen mid-meeting.",
                partnerText: "I saw a couple on the tram holding hands like we do."
            ),
            previewHistoryQuestion(
                localDate: "2026-06-26",
                slot: 1,
                seededFor: currentUserID,
                prompt: "What's one thing you're looking forward to together?",
                ownText: "The long weekend with nothing planned.",
                partnerText: "Cooking that pasta again, but slower this time."
            ),
            previewHistoryQuestion(
                localDate: "2026-06-26",
                slot: 2,
                seededFor: partnerUserID,
                prompt: "What made you laugh recently?",
                ownText: "Your voice note where you forgot what you were saying.",
                partnerText: "The dog video you sent at 1am."
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
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        try loadToday(currentUserID: currentUserID)
    }
}

nonisolated func previewDailyQuestion(
    slot: Int,
    seededFor userID: UUID,
    origin: DailyQuestionOrigin,
    prompt: String,
    short: String,
    answerKinds: [DailyChallengeAnswerKind] = [.text],
    partnerAnswered: Bool = false
) -> DailyChallengeQuestion {
    DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: UUID(),
        coupleID: UUID(),
        localDate: "2026-06-27",
        effectiveLocalDate: "2026-06-27",
        startsAt: .now,
        endsAt: .now.addingTimeInterval(86_400),
        seededForUserID: userID,
        slotNumber: slot,
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
        origin: origin,
        isCurrentDay: true
    )
}

/// A fully-answered question for the history preview: both people answered with text
/// and both replies are revealed, so the read card shows a complete exchange.
nonisolated func previewHistoryQuestion(
    localDate: String,
    slot: Int = 1,
    seededFor userID: UUID,
    prompt: String,
    ownText: String,
    partnerText: String,
    currentUserID: UUID = PreviewDailyChallengeService.userID
) -> DailyChallengeQuestion {
    let answeredAt = Date()
    let partnerUserID = userID == currentUserID ? UUID() : userID
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
        seededForUserID: userID,
        slotNumber: slot,
        status: .answered,
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
        origin: userID == currentUserID ? .own : .partner,
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
