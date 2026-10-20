import SwiftUI

/// The reveal's card: the photo back with where and when it was taken, the
/// verdict, how far off the guess was, and the shared total counting up.
struct GuessMySpotResultCard: View {
    let round: RemoteGuessMySpotRound?
    let plan: GuessMySpotRevealPlan
    let image: UIImage?
    let isSender: Bool
    let viewModel: GuessMySpotViewModel
    let countedPoints: Int
    var isTitleFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            GuessMySpotPhotoCaption(
                image: image,
                placeName: round?.placeName,
                takenOn: round?.takenOn,
                height: 180
            )
            VStack(spacing: PaeoniaSpacing.space4) {
                Text(Self.title(for: plan.verdict, isSender: isSender, partnerName: viewModel.partnerName))
                    .font(PaeoniaTypography.largeTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(line)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityFocused(isTitleFocused)
            .accessibilityIdentifier("guessMySpot.reveal.title")
            GuessMySpotScoreLine(
                me: viewModel.me,
                partner: viewModel.partner,
                score: viewModel.score,
                guesserIsMe: round?.guesserUserID == viewModel.currentUserID,
                points: plan.points,
                countedPoints: countedPoints
            )
        }
        .padding(PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.space4)
        .frame(maxWidth: .infinity)
        .background(
            .paeoniaSurfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    /// The sender already knows where the photo was taken, so a far guess
    /// reads from the partner's side on the sender's phone.
    static func title(for verdict: GuessMySpotVerdict, isSender: Bool, partnerName: String) -> LocalizedStringResource {
        switch verdict {
        case .spotOn: .guessMySpotRevealSpotOnTitle
        case .soClose: .guessMySpotRevealSoCloseTitle
        case .close: .guessMySpotRevealCloseTitle
        case .far: isSender ? .guessMySpotRevealFarTitleSender(partnerName) : .guessMySpotRevealFarTitle
        }
    }

    private var line: LocalizedStringResource {
        guard plan.verdict == .spotOn else {
            let distance = GuessMySpotText.distance(plan.distanceMeters)
            return isSender
                ? .guessMySpotRevealOffSender(viewModel.partnerName, distance)
                : .guessMySpotRevealOff(distance)
        }
        return isSender ? .guessMySpotRevealSpotOnSender(viewModel.partnerName) : .guessMySpotRevealSpotOnGuesser
    }
}

/// The distance counting up at the top of the reveal. It keeps the width of the
/// final number, so the capsule doesn't jitter as digits are added.
struct GuessMySpotDistanceCapsule: View {
    let counted: Int
    let final: Int
    let scale: CGFloat

    var body: some View {
        ZStack {
            Text(verbatim: GuessMySpotText.distance(final))
                .hidden()
            Text(verbatim: GuessMySpotText.distance(counted))
                // Plain digits: each step is too short for the rolling transition.
                .contentTransition(.identity)
        }
        .font(PaeoniaTypography.title.monospacedDigit())
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space8)
        .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.7)), in: Capsule())
        .scaleEffect(scale)
        .accessibilityHidden(true)
        .accessibilityIdentifier("guessMySpot.reveal.distance")
    }
}

/// The reveal's card while the guess waits on this phone for the real spot.
struct GuessMySpotHeldCard: View {
    let viewModel: GuessMySpotViewModel

    var body: some View {
        GuessMySpotHeldLine(viewModel: viewModel) {
            Label {
                Text(.guessMySpotRevealWaitingServer)
            } icon: {
                Image(systemName: "clock").accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaSyncPending)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("guessMySpot.reveal.held")
        }
        .padding(PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity)
        .background(
            .paeoniaSurfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
        )
    }
}
