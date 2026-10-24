import Foundation

/// What the daily question card looks like for a state: the tall picture card or the
/// short row, the color of the wax seal, and whether the card glows. The views read this
/// so they hold no rules of their own.
nonisolated struct DailyPromptCardArt: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        /// The picture card with the sealed envelope, while there is something to do.
        /// It also stands in while the questions load, so the card does not jump.
        case hero
        /// A short row with the envelope, once today's question is answered. The envelope
        /// stays sealed until the partner's answer can be read.
        case compact
    }

    enum Seal: Equatable, Sendable {
        /// This person's color.
        case pink
        /// The partner's color, once the partner has answered today or left an earlier
        /// question to unlock: a letter from them waits.
        case lavender
    }

    let shape: Shape
    let seal: Seal
    /// The card glows while a question waits for this person.
    let glows: Bool
    /// The envelope holds the partner's answer, so it is open once it can be read.
    let isEnvelopeOpen: Bool

    /// This person has answered today's question and the partner has too, so the
    /// partner's answer can be read.
    static func partnerAnswersAreReadable(_ state: DailyChallengeCardState) -> Bool {
        state.kind == .complete && state.hasPartnerAnsweredToday
    }

    init(_ state: DailyChallengeCardState) {
        seal = state.hasPartnerAnsweredToday || state.hasEarlierQuestionsToAnswer ? .lavender : .pink
        isEnvelopeOpen = Self.partnerAnswersAreReadable(state)
        switch state.kind {
        case .loading:
            shape = .hero
            glows = false
        case .noChallenge, .active:
            shape = .hero
            glows = true
        case .complete:
            shape = .compact
            glows = false
        }
    }
}

/// Keeps the card looking like it did before today's question was answered, so the
/// seal can break on screen before the card shrinks. The answer flow covers the card
/// while the state turns complete, so the card must not collapse behind the flow.
nonisolated struct DailyPromptCardHold: Equatable, Sendable {
    /// The last state that showed a question to answer. Nil once released.
    private var lastActive: DailyChallengeCardState?

    /// Call on every state change.
    mutating func observe(_ state: DailyChallengeCardState) {
        switch state.kind {
        case .active:
            lastActive = state
        case .noChallenge:
            // A new day started, so the old picture is out of date.
            lastActive = nil
        case .loading, .complete:
            break
        }
    }

    /// The card is complete but still shows its last active picture.
    func isHolding(for state: DailyChallengeCardState) -> Bool {
        state.kind == .complete && lastActive != nil
    }

    /// The state the card draws. While holding it is the last active picture.
    func shownState(for state: DailyChallengeCardState) -> DailyChallengeCardState {
        guard isHolding(for: state), let last = lastActive else { return state }
        return last
    }

    /// Lets the card show its real state.
    mutating func release() {
        lastActive = nil
    }
}
