import Foundation

/// A step of the first day sequence that follows the pairing celebration. The order
/// here is the order they play in.
nonisolated enum PostPairingStep: String, Codable, CaseIterable, Sendable {
    /// Unwrap the drawing the partner made, then maybe draw one back.
    case gift
    /// Add the widget, for the person who started the couple and drew the first
    /// drawing before sign-in. Someone who draws back after the gift is asked there.
    case widget
    /// Confirm or set the day the couple got together.
    case date
    /// Pick when the daily questions arrive.
    case questionTime
    /// The partner answered questions that wait for this person.
    case answerInvite
}

/// How far one person got through the first day sequence of one pair, saved on
/// this phone so an app kill resumes where it stopped.
nonisolated struct PostPairingProgress: Codable, Equatable, Sendable {
    /// Steps the person moved past. A gift counts as soon as it is opened, so it
    /// never plays twice.
    var finishedSteps: Set<PostPairingStep> = []
    /// The sequence is over and never shows again for this pair.
    var isFinished = false
}

/// What the steps are decided from. A fact that failed to load counts as false, so
/// its step is skipped instead of blocking the sequence.
nonisolated struct PostPairingFacts: Equatable, Sendable {
    /// The couple's active widget drawing is the partner's and has loaded.
    var hasGift = false
    /// The couple's start date as `yyyy-MM-dd`.
    var startedOn: String?
    /// This person joined with the partner's code. The partner set things up while
    /// waiting, so a date that is already set came from them.
    var acceptedInvite = false
    /// This person's own drawing is on the couple's widget, and the widget is not on
    /// their Home Screen.
    var ownDrawingNeedsWidget = false
    var questionTimeIsOn: Bool?
    var partnerAnswersWaiting = false
}

nonisolated enum PostPairingPlan {
    /// The steps still to play, in order.
    static func steps(for facts: PostPairingFacts, finished: Set<PostPairingStep>) -> [PostPairingStep] {
        PostPairingStep.allCases.filter { !finished.contains($0) && applies($0, facts) }
    }

    private static func applies(_ step: PostPairingStep, _ facts: PostPairingFacts) -> Bool {
        switch step {
        case .gift:
            facts.hasGift
        case .widget:
            // With a gift, drawing back asks for the widget there, and Later skips it.
            !facts.hasGift && !facts.acceptedInvite && facts.ownDrawingNeedsWidget
        case .date:
            // The inviter set the date while waiting, so only the person who joined
            // confirms it. Anyone without a date is asked.
            facts.startedOn == nil || facts.acceptedInvite
        case .questionTime:
            facts.questionTimeIsOn == false
        case .answerInvite:
            facts.partnerAnswersWaiting
        }
    }
}
