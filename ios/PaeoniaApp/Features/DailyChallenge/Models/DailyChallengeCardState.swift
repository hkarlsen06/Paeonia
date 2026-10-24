import Foundation

nonisolated struct DailyChallengeCardState: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case loading
        case noChallenge
        /// Today's question waits for the user's answer.
        case active(prompt: String)
        /// The user has answered today's question.
        case complete
    }

    let kind: Kind
    /// The partner has answered today's question. Before the user answers, their answer
    /// waits to be unlocked. After, it is ready to read.
    let hasPartnerAnsweredToday: Bool
    /// The partner has answered questions from earlier days that the user can still
    /// answer to see theirs.
    let hasEarlierQuestionsToAnswer: Bool

    /// A question from an earlier day the partner answered and the user can answer to
    /// unlock. The cards show it as a locked row with its short prompt. It carries no
    /// answer content.
    nonisolated struct LockedPartnerQuestion: Equatable, Identifiable, Sendable {
        let id: UUID
        let shortPrompt: String
        /// How many days before today the question was handed out.
        var daysAgo = 0
    }

    /// The most locked rows a card shows. Any others collapse into "and N more".
    static let maxLockedPartnerQuestions = 2

    /// The first waiting questions, in `earlierQuestionsAwaitingAnswer` order.
    let lockedPartnerQuestions: [LockedPartnerQuestion]
    /// How many waiting questions come after the rows above.
    let moreLockedPartnerQuestionCount: Int

    init(
        kind: Kind,
        hasPartnerAnsweredToday: Bool = false,
        hasEarlierQuestionsToAnswer: Bool = false,
        lockedPartnerQuestions: [LockedPartnerQuestion] = [],
        moreLockedPartnerQuestionCount: Int = 0
    ) {
        self.kind = kind
        self.hasPartnerAnsweredToday = hasPartnerAnsweredToday
        self.hasEarlierQuestionsToAnswer = hasEarlierQuestionsToAnswer
        self.lockedPartnerQuestions = lockedPartnerQuestions
        self.moreLockedPartnerQuestionCount = moreLockedPartnerQuestionCount
    }

    var isActionEnabled: Bool {
        kind != .loading
    }

    /// What happens next once the user has answered today's question, in the order the
    /// cases are checked: questions from earlier days wait for the user's answer, the
    /// partner has not answered yet, or both have answered.
    enum CompleteFollowUp: Equatable, Sendable {
        case earlierQuestionsToAnswer
        case waitingForPartner
        case bothAnswered
    }

    var completeFollowUp: CompleteFollowUp {
        if hasEarlierQuestionsToAnswer { return .earlierQuestionsToAnswer }
        if !hasPartnerAnsweredToday { return .waitingForPartner }
        return .bothAnswered
    }
}
