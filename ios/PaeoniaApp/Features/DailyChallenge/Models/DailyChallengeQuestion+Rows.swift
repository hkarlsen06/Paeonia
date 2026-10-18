import Foundation

extension DailyChallengeQuestion {
    /// Builds the domain questions from the backend read-model rows and the matching
    /// answer detail rows. Shared by today's snapshot and the Questions history, so
    /// both surfaces map rows the same way: shuffled instances are dropped, answer
    /// details are attached by answer id, and only rows the current user can see
    /// survive. The caller decides how to slice or group the result.
    ///
    /// `nonisolated` so the nonisolated `DailyChallengeSnapshot.make` and the
    /// `DailyChallengeService` actor can both build questions off the main
    /// actor (an extension doesn't inherit the type's `nonisolated` by default).
    nonisolated static func list(
        currentUserID: UUID,
        rows: [DailyQuestionRow],
        answerDetails: [DailyAnswerDetailRow],
        locale: Locale = .current
    ) -> [DailyChallengeQuestion] {
        let detailsByAnswerID = Dictionary(
            answerDetails.map { ($0.answerID, $0.detail) },
            uniquingKeysWith: { first, _ in first }
        )

        return rows
            .filter { DailyQuestionInstanceStatus(rawValue: $0.instanceStatus) != .shuffled }
            .map {
                DailyChallengeQuestion(
                    row: $0,
                    currentUserID: currentUserID,
                    detailsByAnswerID: detailsByAnswerID,
                    locale: locale
                )
            }
            .filter(\.isVisibleToCurrentUser)
    }

    private nonisolated init(
        row: DailyQuestionRow,
        currentUserID: UUID,
        detailsByAnswerID: [UUID: DailyQuestionAnswerDetail],
        locale: Locale
    ) {
        self.init(
            id: row.instanceID,
            coupleDayID: row.coupleDayID,
            coupleID: row.coupleID,
            localDate: row.localDate,
            effectiveLocalDate: row.effectiveLocalDate ?? row.localDate,
            startsAt: row.startsAt,
            endsAt: row.endsAt,
            seededForUserID: row.seededForUserID,
            slotNumber: Int(row.slotNumber),
            status: DailyQuestionInstanceStatus(rawValue: row.instanceStatus),
            questionID: row.questionID,
            questionVersionID: row.questionVersionID,
            questionKey: row.questionKey,
            prompt: row.prompt(for: locale),
            shortPrompt: row.shortPrompt(for: locale),
            answerKinds: row.answerKinds,
            ownAnswer: row.ownAnswerSummary,
            partnerAnswer: row.partnerAnswerSummary,
            canViewPartnerAnswer: row.canViewPartnerAnswer,
            ownAnswerDetail: row.ownAnswerID.flatMap { detailsByAnswerID[$0] },
            partnerAnswerDetail: row.partnerAnswerID.flatMap { detailsByAnswerID[$0] },
            origin: row.seededForUserID == currentUserID ? .own : .partner,
            isCurrentDay: row.isCurrentDay,
            partnerAnswerSeenAt: row.partnerAnswerSeenAt,
            ownAnswerSeenByPartnerAt: row.ownAnswerSeenByPartnerAt,
            earlierRoundCount: row.earlierRoundCount ?? 0,
            latestEarlierRoundLocalDate: row.latestEarlierRoundLocalDate,
            hasSharedRound: row.chatAvailable ?? false,
            topicKey: row.topicKey
        )
    }
}

private extension DailyQuestionRow {
    nonisolated var ownAnswerSummary: DailyQuestionAnswerSummary? {
        ownAnswerID.map { DailyQuestionAnswerSummary(id: $0, answeredAt: ownAnsweredAt ?? startsAt) }
    }

    nonisolated var partnerAnswerSummary: DailyQuestionAnswerSummary? {
        partnerAnswerID.map { DailyQuestionAnswerSummary(id: $0, answeredAt: partnerAnsweredAt ?? startsAt) }
    }
}
