import SwiftUI

/// The reveal's card: the photo back with where and when it was taken, the
/// verdict and the scores counting up. The map shows the distance above it.
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

    @State private var viewer: PaeoniaImageViewerSelection?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canToggle: Bool { onToggle != nil }
    private static let photoSide: CGFloat = 112

    var body: some View {
        Group {
            if isCollapsed, let onToggle {
                Button(action: onToggle) {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        Image(systemName: "chevron.compact.up")
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextSecondary)
                            .accessibilityHidden(true)
                        scores
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(.guessMySpotRevealCardExpand))
            } else {
                expandedContent
            }
        }
        .padding(PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.space4)
        .frame(maxWidth: .infinity)
        .background(
            .paeoniaSurfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if !isCollapsed, canToggle {
                collapseButton
            }
        }
        .paeoniaImageViewer(selection: $viewer)
        .accessibilityElement(children: .contain)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .accessibilityIdentifier("guessMySpot.reveal.card")
    }

    private var expandedContent: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            verdict
                .padding(.horizontal, PaeoniaSpacing.space24)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space12))
                : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space16))
            layout {
                photo
                scores
                    .frame(
                        maxWidth: .infinity,
                        alignment: dynamicTypeSize.isAccessibilitySize ? .center : .leading
                    )
            }
        }
    }

    private var verdict: some View {
        Text(Self.title(for: plan.verdict, isSender: isSender, partnerName: viewModel.partnerName))
            .font(PaeoniaTypography.largeTitle)
            .foregroundStyle(.paeoniaTextPrimary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityFocused(isTitleFocused)
            .accessibilityIdentifier("guessMySpot.reveal.title")
    }

    private var scores: some View {
        GuessMySpotScoreLine(
            me: viewModel.me,
            partner: viewModel.partner,
            score: viewModel.score,
            guesserIsMe: round?.guesserUserID == viewModel.currentUserID,
            points: plan.points,
            countedPoints: countedPoints
        )
    }

    private var photo: some View {
        Button {
            if let image { viewer = PaeoniaImageViewerSelection(image: image) }
        } label: {
            VStack(spacing: PaeoniaSpacing.space4) {
                GuessMySpotPhotoCaption(
                    image: image,
                    placeName: dynamicTypeSize.isAccessibilitySize ? nil : round?.placeName,
                    takenOn: dynamicTypeSize.isAccessibilitySize ? nil : round?.takenOn,
                    height: Self.photoSide
                )
                .frame(width: Self.photoSide)
                if dynamicTypeSize.isAccessibilitySize {
                    if let place = round?.placeName {
                        Text(verbatim: place)
                            .font(PaeoniaTypography.bodyEmphasis)
                    }
                    if let date = GuessMySpotText.takenOn(round?.takenOn) {
                        Text(verbatim: date)
                            .font(PaeoniaTypography.caption)
                    }
                }
            }
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
        .disabled(!canToggle || image == nil)
        .accessibilityLabel(Text(.guessMySpotPhotoA11Y))
        .accessibilityValue(Text(verbatim: [round?.placeName, GuessMySpotText.takenOn(round?.takenOn)]
            .compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("guessMySpot.reveal.card.photo")
        .transition(.opacity)
    }

    /// Keeps the map available after the compact card has appeared.
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
        .padding(PaeoniaSpacing.space4)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: GuessMySpotText.distance(final)))
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
