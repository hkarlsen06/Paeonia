import SwiftUI

/// The reveal's card: the photo back with where and when it was taken, the
/// verdict, how far off the guess was, and the shared total counting up.
/// Collapsed it shows only the total, so the map has nearly the whole screen.
struct GuessMySpotResultCard: View {
    let round: RemoteGuessMySpotRound?
    let plan: GuessMySpotRevealPlan
    let image: UIImage?
    let isSender: Bool
    let viewModel: GuessMySpotViewModel
    let countedPoints: Int
    var isTitleFocused: AccessibilityFocusState<Bool>.Binding
    var isCollapsed = false
    /// Collapses or expands the card. Nil: the card can't, as while the reveal plays.
    var onToggle: (() -> Void)?

    private var canToggle: Bool { onToggle != nil }

    var body: some View {
        // Collapsed, the card is a button. It has the trait then.
        // swiftlint:disable:next accessibility_trait_for_button
        VStack(spacing: PaeoniaSpacing.space12) {
            if isCollapsed {
                Image(systemName: "chevron.compact.up")
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                GuessMySpotPhotoCaption(
                    image: image,
                    placeName: round?.placeName,
                    takenOn: round?.takenOn,
                    height: 180
                )
                .transition(.opacity)
                verdict
                    .transition(.opacity)
            }
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
        .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .onTapGesture { onToggle?() }
        // Expanded, it has nothing to tap but its button, so a pan or pinch on it moves
        // the map under it. Collapsed, a tap anywhere on it expands it.
        .allowsHitTesting(isCollapsed && canToggle)
        .overlay(alignment: .topTrailing) {
            if !isCollapsed, canToggle {
                collapseButton
            }
        }
        .accessibilityElement(children: isCollapsed ? .combine : .contain)
        .accessibilityAddTraits(isCollapsed && canToggle ? .isButton : [])
        .accessibilityHint(isCollapsed && canToggle ? Text(.guessMySpotRevealCardExpand) : Text(verbatim: ""))
        .accessibilityAction {
            if isCollapsed { onToggle?() }
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .accessibilityIdentifier("guessMySpot.reveal.card")
    }

    private var verdict: some View {
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
    }

    /// On the photo's top corner.
    private var collapseButton: some View {
        Button {
            PaeoniaHaptics.selection()
            onToggle?()
        } label: {
            Image(systemName: "chevron.down")
                .font(PaeoniaTypography.caption.weight(.bold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(PaeoniaSpacing.space12)
        .accessibilityLabel(Text(.guessMySpotRevealCardCollapse))
        .accessibilityIdentifier("guessMySpot.reveal.card.collapse")
        .transition(.opacity)
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
