import Foundation

nonisolated struct DailyChallengeProgress: Equatable, Sendable {
    static let requiredOwnQuestionCount = 2

    let ownQuestionCount: Int
    let ownAnsweredCount: Int
    let partnerQuestionCount: Int

    var requiredQuestionCount: Int {
        Self.requiredOwnQuestionCount
    }

    var isComplete: Bool {
        ownQuestionCount >= Self.requiredOwnQuestionCount
            && ownAnsweredCount >= Self.requiredOwnQuestionCount
    }
}

nonisolated struct DailyChallengeCardState: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case loading
        case noChallenge
        case active(prompt: String)
        case complete
    }

    let kind: Kind
    let answeredCount: Int
    let totalCount: Int
    let hasPartnerAnswersForToday: Bool
    /// Whether the partner has answered questions the user can still answer to
    /// unlock. Distinguishes "there's a partner reply to reveal" (a real call to
    /// action) from "everything is already answered" (pure review).
    let hasAnswerablePartnerQuestions: Bool

    /// A question the partner answered that the user can answer to unlock. The cards
    /// show it as a locked row with its short prompt. It carries no answer content.
    nonisolated struct LockedPartnerQuestion: Equatable, Identifiable, Sendable {
        let id: UUID
        let shortPrompt: String
        /// How many days before today the partner's question was handed out. 0 for
        /// today's questions, more for ones carried over from an earlier day.
        var daysAgo = 0
    }

    /// The most locked rows a card shows. Any others collapse into "and N more".
    static let maxLockedPartnerQuestions = 2

    /// The first waiting partner questions, in `answerablePartnerQuestions` order.
    let lockedPartnerQuestions: [LockedPartnerQuestion]
    /// How many waiting partner questions come after the rows above.
    let moreLockedPartnerQuestionCount: Int

    init(
        kind: Kind,
        answeredCount: Int,
        totalCount: Int,
        hasPartnerAnswersForToday: Bool = false,
        hasAnswerablePartnerQuestions: Bool = false,
        lockedPartnerQuestions: [LockedPartnerQuestion] = [],
        moreLockedPartnerQuestionCount: Int = 0
    ) {
        self.kind = kind
        self.answeredCount = answeredCount
        self.totalCount = totalCount
        self.hasPartnerAnswersForToday = hasPartnerAnswersForToday
        self.hasAnswerablePartnerQuestions = hasAnswerablePartnerQuestions
        self.lockedPartnerQuestions = lockedPartnerQuestions
        self.moreLockedPartnerQuestionCount = moreLockedPartnerQuestionCount
    }

    /// Locked rows open their answer flow only once the user's own questions are done,
    /// like the Questions tab list. Until then they only say the partner has answered.
    var lockedPartnerQuestionsAreOpenable: Bool {
        kind == .complete
    }

    var isActionEnabled: Bool {
        kind != .loading
    }

    /// What happens next once the user has answered everything, in the order the cases
    /// are checked: the partner's questions are open to answer, the partner has not
    /// answered yet today, or both sides have answered.
    enum CompleteFollowUp: Equatable, Sendable {
        case partnerQuestionsToAnswer
        case waitingForPartner
        case bothAnswered
    }

    var completeFollowUp: CompleteFollowUp {
        if hasAnswerablePartnerQuestions { return .partnerQuestionsToAnswer }
        if !hasPartnerAnswersForToday { return .waitingForPartner }
        return .bothAnswered
    }
}
