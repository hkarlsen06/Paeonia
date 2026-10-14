import SwiftUI

/// How the two picks on a "who is more likely" question line up. It is a small, warm
/// line about the picks, never a score: nothing is counted and nothing is right or wrong.
nonisolated enum PartnerChoiceMatch: Equatable {
    case bothPickedViewer
    case bothPickedPartner
    case eachPickedThemselves
    case eachPickedTheOther

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

    /// The two cases where both people chose the same person get a small bloom.
    var isSamePick: Bool {
        self == .bothPickedViewer || self == .bothPickedPartner
    }

    fileprivate var systemImage: String {
        isSamePick ? "heart.fill" : "person.2.fill"
    }
}

extension DailyChallengeQuestion {
    /// How the two picks line up, once both are visible to the user. Nil when either
    /// answer is missing or hidden, or the couple's identity is not known yet.
    nonisolated func partnerChoiceMatch(participants: DailyChallengeParticipants) -> PartnerChoiceMatch? {
        guard
            let viewerID = participants.currentUserID,
            let partnerID = participants.partnerUserID,
            partnerAnswerDetail?.canViewAnswer == true
        else { return nil }
        return .make(
            viewerID: viewerID,
            partnerID: partnerID,
            viewerChoice: ownAnswerDetail?.selectedUserID,
            partnerChoice: partnerAnswerDetail?.selectedUserID
        )
    }
}

/// One line under the revealed picks that says how they lined up. When `celebrates`
/// is true and both picked the same person, a short petal bloom and a soft haptic
/// play once. Reduce Motion skips the animation and keeps the haptic.
struct PartnerChoiceMatchBanner: View {
    let match: PartnerChoiceMatch
    let partnerName: String
    let celebrates: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomStart: Date?
    @State private var isShown = false

    /// The burst needs room around the banner. It draws outside the row without
    /// taking layout space.
    private static let bloomSize: CGFloat = 280

    init(match: PartnerChoiceMatch, partnerName: String, celebrates: Bool) {
        self.match = match
        self.partnerName = partnerName
        self.celebrates = celebrates
    }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: match.systemImage)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            Text(title)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary, in: Capsule())
        .frame(maxWidth: .infinity)
        .background {
            if let bloomStart {
                GamePetalBloom(start: bloomStart, seed: "partnerChoiceMatch")
                    .frame(width: Self.bloomSize, height: Self.bloomSize)
            }
        }
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown || reduceMotion ? 1 : 0.92)
        .accessibilityElement(children: .combine)
        .task {
            withAnimation(reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.celebrationReveal) {
                isShown = true
            }
            guard celebrates, match.isSamePick else { return }
            bloomStart = Date()
            PaeoniaHaptics.partnerChoiceMatched()
        }
    }

    private var title: LocalizedStringResource {
        switch match {
        case .bothPickedViewer: .dailyChallengeMatchBothPickedViewer
        case .bothPickedPartner: .dailyChallengeMatchBothPickedPartner(partnerName)
        case .eachPickedThemselves: .dailyChallengeMatchEachPickedThemselves
        case .eachPickedTheOther: .dailyChallengeMatchEachPickedTheOther
        }
    }
}

#if DEBUG
#Preview("Both picked partner, celebrating") {
    PartnerChoiceMatchBanner(match: .bothPickedPartner, partnerName: "Oda", celebrates: true)
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Each picked the other") {
    PartnerChoiceMatchBanner(match: .eachPickedTheOther, partnerName: "Oda", celebrates: false)
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
