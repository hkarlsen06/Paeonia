import Foundation

/// Today's daily question and the open exchanges from earlier days. Both partners answer
/// the same question each couple day, and each sees the other's answer once both have
/// answered.
nonisolated struct DailyChallengeSnapshot: Equatable, Sendable {
    let currentUserID: UUID?
    /// The active day represented by this snapshot. When the backend returns only
    /// carried-over unresolved rows and no active-day rows, this is nil so the Home
    /// card correctly shows that today's question has not started.
    let coupleDayID: UUID?
    let questions: [DailyChallengeQuestion]
    let refreshedAt: Date
    var anchorTimeZoneID = "UTC"

    var timeZone: TimeZone { TimeZone(identifier: anchorTimeZoneID) ?? .gmt }

    static func empty(
        currentUserID: UUID?, refreshedAt: Date = Date(), anchorTimeZoneID: String = "UTC"
    ) -> DailyChallengeSnapshot {
        DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: nil,
            questions: [],
            refreshedAt: refreshedAt,
            anchorTimeZoneID: anchorTimeZoneID
        )
    }

    /// The question both partners answer today. Nil before today's question exists.
    var todayQuestion: DailyChallengeQuestion? {
        guard let coupleDayID else { return nil }
        return questions.first { $0.coupleDayID == coupleDayID && $0.isCurrentDay }
    }

    /// Questions the partner has answered that the user can still answer to see theirs:
    /// today's first, then earlier days, newest first.
    var questionsAwaitingAnswer: [DailyChallengeQuestion] {
        questions
            .filter(\.isAwaitingCurrentUserAnswer)
            .sorted(by: Self.dayOrder)
    }

    var hasQuestionsAwaitingAnswer: Bool {
        questions.contains(where: \.isAwaitingCurrentUserAnswer)
    }

    /// The questions from earlier days that wait for the user's answer. The cards list
    /// them under today's question, which the card itself stands for.
    var earlierQuestionsAwaitingAnswer: [DailyChallengeQuestion] {
        questionsAwaitingAnswer.filter { !$0.isCurrentDay }
    }

    var hasAnyQuestions: Bool {
        !questions.isEmpty
    }

    /// Current day first, then newer days, then a stable id tiebreak.
    private static func dayOrder(_ lhs: DailyChallengeQuestion, _ rhs: DailyChallengeQuestion) -> Bool {
        if lhs.isCurrentDay != rhs.isCurrentDay {
            return lhs.isCurrentDay
        }
        if lhs.startsAt != rhs.startsAt {
            return lhs.startsAt > rhs.startsAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// The couple-local date (`yyyy-MM-dd`) of the active day. Nil before today's
    /// question exists.
    var currentDayLocalDate: String? {
        todayQuestion?.localDate
    }

    /// The shared date for the active day, or the snapshot's date in the couple's zone.
    var todayLocalDate: String {
        currentDayLocalDate ?? MemoryTimeline.localDateString(for: refreshedAt, timeZone: timeZone)
    }

    /// When the active couple day ends. Nil when no day is active.
    var currentDayEndsAt: Date? {
        todayQuestion?.endsAt
    }

    /// This snapshot with the active day dropped once its end has passed, so a day
    /// from the cache, or one still on screen when the couple's day ends offline,
    /// never shows as today. Its question stays as an earlier day's, like the server's
    /// carry-over: one the partner answered can still be answered.
    func endingCurrentDay(ifEndedBy now: Date) -> DailyChallengeSnapshot {
        guard let endsAt = currentDayEndsAt, endsAt <= now else { return self }
        return DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: nil,
            questions: questions.map { question in
                guard question.coupleDayID == coupleDayID else { return question }
                var carried = question
                carried.isCurrentDay = false
                return carried
            },
            refreshedAt: now,
            anchorTimeZoneID: anchorTimeZoneID
        )
    }

    var homeCardState: DailyChallengeCardState {
        guard let todayQuestion else {
            return cardState(.noChallenge)
        }
        if todayQuestion.hasOwnAnswer {
            return cardState(.complete)
        }
        let prompt = todayQuestion.shortPrompt.isEmpty ? todayQuestion.prompt : todayQuestion.shortPrompt
        return cardState(.active(prompt: prompt))
    }

    /// Whole days from a couple-local date to `todayLocalDate`.
    private func daysBeforeToday(_ localDate: String) -> Int {
        guard
            let start = DailyChallengeHistory.parseLocalDate(localDate),
            let end = DailyChallengeHistory.parseLocalDate(todayLocalDate)
        else { return 0 }
        return max(0, Int((end.timeIntervalSince(start) / 86_400).rounded()))
    }

    private func cardState(_ kind: DailyChallengeCardState.Kind) -> DailyChallengeCardState {
        let waiting = earlierQuestionsAwaitingAnswer
        let shown = waiting.prefix(DailyChallengeCardState.maxLockedPartnerQuestions)
        return DailyChallengeCardState(
            kind: kind,
            hasPartnerAnsweredToday: todayQuestion?.hasPartnerAnswer == true,
            hasEarlierQuestionsToAnswer: !waiting.isEmpty,
            lockedPartnerQuestions: shown.map {
                DailyChallengeCardState.LockedPartnerQuestion(
                    id: $0.id,
                    shortPrompt: $0.shortPrompt.isEmpty ? $0.prompt : $0.shortPrompt,
                    daysAgo: daysBeforeToday($0.localDate)
                )
            },
            moreLockedPartnerQuestionCount: waiting.count - shown.count
        )
    }

    static func make(
        currentUserID: UUID,
        rows: [DailyQuestionRow],
        answerDetails: [DailyAnswerDetailRow],
        locale: Locale = .current,
        refreshedAt: Date = Date(),
        anchorTimeZoneID: String = "UTC"
    ) -> DailyChallengeSnapshot {
        let questions = DailyChallengeQuestion.list(
            rows: rows,
            answerDetails: answerDetails,
            locale: locale
        )

        let currentCoupleDayID = rows.first(where: \.isCurrentDay)?.coupleDayID

        return DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: currentCoupleDayID,
            questions: questions,
            refreshedAt: refreshedAt,
            anchorTimeZoneID: anchorTimeZoneID
        )
    }
}
