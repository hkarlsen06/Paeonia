import SwiftUI

/// How the two picks on a "who is more likely" or a pick-one-of-two question line
/// up. It is a warm note about the picks, never a score: nothing is counted and
/// nothing is right or wrong.
nonisolated enum PartnerChoiceMatch: Hashable {
    case bothPickedViewer
    case bothPickedPartner
    case eachPickedThemselves
    case eachPickedTheOther
    /// Both picked the same option, with its label.
    case bothPickedOption(String)
    /// Each picked a different option: the user's, then the partner's.
    case pickedDifferentOptions(yours: String, theirs: String)

    /// The match for the two picks, or nil when either pick is missing or names
    /// someone outside the couple.
    static func make(
        viewerID: UUID,
        partnerID: UUID,
        viewerChoice: UUID?,
        partnerChoice: UUID?
    ) -> PartnerChoiceMatch? {
        guard let viewerChoice, let partnerChoice else { return nil }
        switch (viewerChoice, partnerChoice) {
        case (viewerID, viewerID): return .bothPickedViewer
        case (partnerID, partnerID): return .bothPickedPartner
        case (viewerID, partnerID): return .eachPickedThemselves
        case (partnerID, viewerID): return .eachPickedTheOther
        default: return nil
        }
    }

    /// The cases where both people chose the same person or option get a small bloom.
    var isSamePick: Bool {
        switch self {
        case .bothPickedViewer, .bothPickedPartner, .bothPickedOption: true
        default: false
        }
    }

    /// What each person picked, as the card shows it: the option, or the picked
    /// person's name. `viewerName` names the user.
    func picks(viewerName: String, partnerName: String) -> (yours: String, theirs: String) {
        switch self {
        case .bothPickedViewer: (viewerName, viewerName)
        case .bothPickedPartner: (partnerName, partnerName)
        case .eachPickedThemselves: (viewerName, partnerName)
        case .eachPickedTheOther: (partnerName, viewerName)
        case let .bothPickedOption(option): (option, option)
        case let .pickedDifferentOptions(yours, theirs): (yours, theirs)
        }
    }
}

extension DailyChallengeQuestion {
    /// How the two picks line up, once both are visible to the user. Nil when either
    /// answer is missing or hidden, or the couple's identity is not known yet.
    nonisolated func partnerChoiceMatch(participants: DailyChallengeParticipants) -> PartnerChoiceMatch? {
        guard partnerAnswerDetail?.canViewAnswer == true else { return nil }
        if let yours = ownAnswerDetail?.selectedOptionLabel, let theirs = partnerAnswerDetail?.selectedOptionLabel {
            return yours == theirs ? .bothPickedOption(yours) : .pickedDifferentOptions(yours: yours, theirs: theirs)
        }
        guard let viewerID = participants.currentUserID, let partnerID = participants.partnerUserID else {
            return nil
        }
        return .make(
            viewerID: viewerID,
            partnerID: partnerID,
            viewerChoice: ownAnswerDetail?.selectedUserID,
            partnerChoice: partnerAnswerDetail?.selectedUserID
        )
    }
}

/// How the revealed picks lined up, as a `PickMatchCard`. When both picked the same, a
/// petal bloom and a soft haptic play the first time the card for `celebrationID`
/// shows, and never again in this app session. A row the chat rebuilds mid-reveal
/// carries on with the same burst. Reduce Motion skips the bloom and keeps the haptic.
/// VoiceOver reads the match as one sentence.
struct PartnerChoiceMatchBanner: View {
    let match: PartnerChoiceMatch
    let participants: DailyChallengeParticipants
    /// The revealed day's instance, or nil when this showing doesn't celebrate.
    let celebrationID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomStart: Date?
    @State private var isShown = false

    /// The burst needs room around the card. It draws outside the row without taking
    /// layout space.
    private static let bloomSize: CGFloat = 380

    init(match: PartnerChoiceMatch, participants: DailyChallengeParticipants, celebrationID: UUID?) {
        self.match = match
        self.participants = participants
        self.celebrationID = celebrationID
        // Only the reveal fades the banner in. The chat rebuilds the row when the
        // reveal ends, and a second fade there reads as a flicker.
        _isShown = State(initialValue: celebrationID == nil)
    }

    private var partnerName: String { participants.partnerName }

    var body: some View {
        content
            // In front, so the card doesn't hide the petals. The bloom takes no taps.
            .overlay {
                if let bloomStart {
                    GamePetalBloom(start: bloomStart, seed: "partnerChoiceMatch")
                        .frame(width: Self.bloomSize, height: Self.bloomSize)
                }
            }
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.92)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .task {
                withAnimation(reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.celebrationReveal) {
                    isShown = true
                }
                guard match.isSamePick, let celebrationID else { return }
                if let started = MatchCelebrationStarts.dates[celebrationID] {
                    // A rebuilt row carries on with the same burst, or shows nothing
                    // once it is over.
                    bloomStart = started
                } else {
                    let now = Date()
                    MatchCelebrationStarts.dates[celebrationID] = now
                    bloomStart = now
                    PaeoniaHaptics.partnerChoiceMatched()
                }
            }
    }

    private var content: some View {
        let picks = match.picks(
            viewerName: participants.currentDisplayName ?? String(localized: .dailyChallengeChoiceYou),
            partnerName: partnerName
        )
        return PickMatchCard(
            yours: picks.yours,
            theirs: picks.theirs,
            isSamePick: match.isSamePick,
            participants: participants
        )
    }

    private var title: LocalizedStringResource {
        switch match {
        case .bothPickedViewer: .dailyChallengeMatchBothPickedViewer
        case .bothPickedPartner: .dailyChallengeMatchBothPickedPartner(partnerName)
        case .eachPickedThemselves: .dailyChallengeMatchEachPickedThemselves
        case .eachPickedTheOther: .dailyChallengeMatchEachPickedTheOther
        case let .bothPickedOption(option): .dailyChallengeMatchBothPickedOption(option)
        case let .pickedDifferentOptions(yours, theirs):
            .dailyChallengeMatchPickedDifferentOptions(yours, partnerName, theirs)
        }
    }
}

// ponytail: grows by one entry per same-pick reveal for the app's lifetime; tiny.
/// When each round's match began to bloom. The chat can rebuild a row mid-reveal, so
/// the new row picks up the same burst instead of starting another, and the haptic
/// plays once.
@MainActor
private enum MatchCelebrationStarts {
    static var dates: [UUID: Date] = [:]
}

#if DEBUG
private func matchPreview(_ match: PartnerChoiceMatch, celebrates: Bool) -> some View {
    PartnerChoiceMatchBanner(
        match: match,
        participants: .init(partnerDisplayName: "Oda"),
        celebrationID: celebrates ? UUID() : nil
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Both picked partner, celebrating") {
    matchPreview(.bothPickedPartner, celebrates: true)
}

#Preview("Both picked an option") {
    matchPreview(.bothPickedOption("Teleport once a week"), celebrates: true)
}

#Preview("Picked different options") {
    matchPreview(.pickedDifferentOptions(yours: "The dinosaurs", theirs: "The year 3000"), celebrates: false)
}

#Preview("Each picked the other") {
    matchPreview(.eachPickedTheOther, celebrates: false)
}
#endif
