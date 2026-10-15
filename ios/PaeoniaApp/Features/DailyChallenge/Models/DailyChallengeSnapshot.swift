import Foundation

nonisolated struct DailyChallengeSnapshot: Equatable, Sendable {
    let currentUserID: UUID?
    /// The active day represented by this snapshot. When the backend returns only
    /// carried-over unresolved rows and no active-day rows, this is nil so the Home
    /// card correctly shows that today's challenge has not started.
    let coupleDayID: UUID?
    let questions: [DailyChallengeQuestion]
    let refreshedAt: Date

    static func empty(currentUserID: UUID?, refreshedAt: Date = Date()) -> DailyChallengeSnapshot {
        DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: nil,
            questions: [],
            refreshedAt: refreshedAt
        )
    }

    var ownQuestions: [DailyChallengeQuestion] {
        currentDayQuestions
            .filter { $0.origin == .own }
            .sorted { $0.slotNumber < $1.slotNumber }
    }

    var partnerStartedQuestions: [DailyChallengeQuestion] {
        questions
            .filter { $0.origin == .partner && ($0.hasPartnerAnswer || $0.hasOwnAnswer) }
            .sorted(by: readOverviewDayOrder)
    }

    private var currentDayQuestions: [DailyChallengeQuestion] {
        guard let coupleDayID else { return [] }
        return questions.filter { $0.coupleDayID == coupleDayID && $0.isCurrentDay }
    }

    private var currentDayVisibleQuestions: [DailyChallengeQuestion] {
        currentDayQuestions.filter(\.isVisibleToCurrentUser)
    }

    private func readOverviewDayOrder(
        _ lhs: DailyChallengeQuestion,
        _ rhs: DailyChallengeQuestion
    ) -> Bool {
        if lhs.isCurrentDay != rhs.isCurrentDay {
            return lhs.isCurrentDay
        }
        if lhs.startsAt != rhs.startsAt {
            return lhs.startsAt > rhs.startsAt
        }
        if lhs.origin != rhs.origin {
            return lhs.origin == .own
        }

        let originOrder: Bool? = switch (lhs.origin, rhs.origin) {
        case (.partner, .partner): Self.partnerQuestionOrder(lhs, rhs)
        case (.own, .own): Self.ownQuestionOrder(lhs, rhs)
        default: nil
        }
        if let originOrder {
            return originOrder
        }

        if lhs.slotNumber != rhs.slotNumber {
            return lhs.slotNumber < rhs.slotNumber
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Orders two partner questions that share a start time. Nil means they tie.
    private static func partnerQuestionOrder(_ lhs: DailyChallengeQuestion, _ rhs: DailyChallengeQuestion) -> Bool? {
        let lhsAnswerable = lhs.isAvailableToAnswer
        let rhsAnswerable = rhs.isAvailableToAnswer
        if lhsAnswerable != rhsAnswerable {
            return lhsAnswerable
        }
        if lhsAnswerable {
            let lhsDate = lhs.partnerAnswer?.answeredAt ?? lhs.ownAnswer?.answeredAt ?? .distantPast
            let rhsDate = rhs.partnerAnswer?.answeredAt ?? rhs.ownAnswer?.answeredAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
        } else {
            let lhsDate = lhs.ownAnswer?.answeredAt ?? .distantPast
            let rhsDate = rhs.ownAnswer?.answeredAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
        }
        return nil
    }

    /// Orders two own questions that share a start time. Nil means they tie.
    private static func ownQuestionOrder(_ lhs: DailyChallengeQuestion, _ rhs: DailyChallengeQuestion) -> Bool? {
        let lhsHasPartnerAnswer = lhs.hasPartnerAnswer
        let rhsHasPartnerAnswer = rhs.hasPartnerAnswer
        if lhsHasPartnerAnswer != rhsHasPartnerAnswer {
            return lhsHasPartnerAnswer
        }
        if lhsHasPartnerAnswer {
            let lhsDate = lhs.partnerAnswer?.answeredAt ?? .distantPast
            let rhsDate = rhs.partnerAnswer?.answeredAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
        }
        return nil
    }

    var visibleQuestions: [DailyChallengeQuestion] {
        questions
            .filter(\.isVisibleToCurrentUser)
            .sorted(by: readOverviewDayOrder)
    }

    var answerablePartnerQuestions: [DailyChallengeQuestion] {
        partnerStartedQuestions.filter(\.isAvailableToAnswer)
    }

    var hasAnswerablePartnerQuestions: Bool {
        !answerablePartnerQuestions.isEmpty
    }

    var hasPartnerAnswersForToday: Bool {
        currentDayVisibleQuestions.contains(where: \.hasPartnerAnswer)
    }

    var partnerQuestionsForReadOverview: [DailyChallengeQuestion] {
        partnerStartedQuestions
    }

    /// The main Questions tab's own-questions section. Older own questions belong in
    /// history so this section never shows more than today's questions.
    var ownQuestionsForReadOverview: [DailyChallengeQuestion] {
        ownQuestions.sorted(by: readOverviewDayOrder)
    }

    /// The Questions tab's single read list: the partner's started questions and the
    /// user's own current-day questions in one set, sorted by `questionsTabOrder`.
    /// What the user has seen is view-model state, so the caller passes `isNew`. The
    /// view applies the "answered or still sending" filter (sending is view-model
    /// state too) before showing the cards.
    func readOverviewQuestions(
        isNew: (DailyChallengeQuestion) -> Bool = { _ in false }
    ) -> [DailyChallengeQuestion] {
        (partnerStartedQuestions + ownQuestions).sorted {
            Self.questionsTabOrder($0, $1, isNew: isNew)
        }
    }

    /// Questions tab order: anything with something new to see sits above the recency
    /// timeline. First a partner's question the user can still answer, then a card with
    /// something new from the partner (an answer or a chat message the user hasn't
    /// seen). Within each tier the shared `readOverviewOrder` applies. Once the user
    /// answers or opens a card it drops into the timeline, so the next new card is on top.
    static func questionsTabOrder(
        _ lhs: DailyChallengeQuestion,
        _ rhs: DailyChallengeQuestion,
        isNew: (DailyChallengeQuestion) -> Bool = { _ in false }
    ) -> Bool {
        func tier(_ question: DailyChallengeQuestion) -> Int {
            if question.isAwaitingCurrentUserAnswer { return 0 }
            if isNew(question) { return 1 }
            return 2
        }
        let lhsTier = tier(lhs)
        let rhsTier = tier(rhs)
        if lhsTier != rhsTier {
            return lhsTier < rhsTier
        }
        return readOverviewOrder(lhs, rhs)
    }

    /// Orders read-overview questions by most recent answer first, then slot, then a
    /// stable id tiebreak. Shared by the Questions tab's list (as the within-tier order)
    /// and the history's within-day order so both read the same way.
    static func readOverviewOrder(
        _ lhs: DailyChallengeQuestion,
        _ rhs: DailyChallengeQuestion
    ) -> Bool {
        if lhs.latestAnswerDate != rhs.latestAnswerDate {
            return lhs.latestAnswerDate > rhs.latestAnswerDate
        }
        if lhs.slotNumber != rhs.slotNumber {
            return lhs.slotNumber < rhs.slotNumber
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Questions surfaced inside the focused answering flow, in the order the
    /// flow steps through them: the user's own questions first, then any of the
    /// partner's questions the user can still answer. Already-answered own
    /// questions stay in the list so the user can swipe back and review them.
    var answerFlowQuestions: [DailyChallengeQuestion] {
        ownQuestions + answerablePartnerQuestions
    }

    var progress: DailyChallengeProgress {
        DailyChallengeProgress(
            ownQuestionCount: ownQuestions.count,
            ownAnsweredCount: ownQuestions.filter(\.hasOwnAnswer).count,
            partnerQuestionCount: partnerStartedQuestions.count
        )
    }

    var hasAnyQuestions: Bool {
        !visibleQuestions.isEmpty
    }

    var hasAnyCurrentDayQuestions: Bool {
        !currentDayVisibleQuestions.isEmpty
    }

    /// The couple-local date (`yyyy-MM-dd`) of the active day. Carried-over rows from
    /// earlier days can sit anywhere in `questions`, so this reads the active day's
    /// own questions only. Nil before today's questions exist.
    var currentDayLocalDate: String? {
        currentDayQuestions.first?.localDate
    }

    /// When the active couple day ends. Nil when no day is active.
    var currentDayEndsAt: Date? {
        currentDayQuestions.map(\.endsAt).min()
    }

    /// This snapshot with the active day dropped once its end has passed, so a day
    /// from the cache, or one still on screen when the couple's day ends offline,
    /// never shows as today. Questions from the partner stay, since those can be
    /// answered on a later day.
    func endingCurrentDay(ifEndedBy now: Date) -> DailyChallengeSnapshot {
        guard let endsAt = currentDayEndsAt, endsAt <= now else { return self }
        return DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: nil,
            questions: questions,
            refreshedAt: refreshedAt
        )
    }

    var homeCardState: DailyChallengeCardState {
        if !hasAnyCurrentDayQuestions {
            return cardState(.noChallenge)
        }

        if progress.isComplete {
            return cardState(.complete)
        }

        let prompt = ownQuestions.first(where: { !$0.hasOwnAnswer })?.shortPrompt
            ?? partnerStartedQuestions.first(where: { !$0.hasOwnAnswer })?.shortPrompt
            ?? visibleQuestions.first?.shortPrompt
            ?? visibleQuestions.first?.prompt
            ?? ""

        return cardState(.active(prompt: prompt))
    }

    /// Whole days from a couple-local date to the active day. Before today's day has
    /// started, the phone's date when this snapshot was read stands in for it.
    private func daysBeforeToday(_ localDate: String) -> Int {
        let today = currentDayLocalDate ?? MemoryTimeline.localDateString(for: refreshedAt)
        guard
            let start = DailyChallengeHistory.parseLocalDate(localDate),
            let end = DailyChallengeHistory.parseLocalDate(today)
        else { return 0 }
        return max(0, Int((end.timeIntervalSince(start) / 86_400).rounded()))
    }

    private func cardState(_ kind: DailyChallengeCardState.Kind) -> DailyChallengeCardState {
        let waiting = answerablePartnerQuestions
        let shown = waiting.prefix(DailyChallengeCardState.maxLockedPartnerQuestions)
        return DailyChallengeCardState(
            kind: kind,
            answeredCount: progress.ownAnsweredCount,
            totalCount: progress.requiredQuestionCount,
            hasPartnerAnswersForToday: hasPartnerAnswersForToday,
            hasAnswerablePartnerQuestions: !waiting.isEmpty,
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
        refreshedAt: Date = Date()
    ) -> DailyChallengeSnapshot {
        let questions = DailyChallengeQuestion.list(
            currentUserID: currentUserID,
            rows: rows,
            answerDetails: answerDetails,
            locale: locale
        )

        let currentCoupleDayID = rows.first(where: \.isCurrentDay)?.coupleDayID

        return DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: currentCoupleDayID,
            questions: questions,
            refreshedAt: refreshedAt
        )
    }
}
