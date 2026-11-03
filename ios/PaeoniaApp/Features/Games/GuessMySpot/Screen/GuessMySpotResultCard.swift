import SwiftUI

/// The reveal's card: the photo back with where and when it was taken, the
/// verdict and the scores counting up. The map shows the distance above it.
/// Collapsed it shows only the total, so the map has nearly the whole screen.
/// Only the collapse button takes touches itself, so a pan or a pinch that starts
/// on the card moves the map. Taps on the photo or the collapsed card come as `tap`.
struct GuessMySpotResultCard: View {
    let round: RemoteGuessMySpotRound?
    let plan: GuessMySpotRevealPlan
    let image: UIImage?
    let isSender: Bool
    let viewModel: GuessMySpotViewModel
    let countedPoints: Int
    var isTitleFocused: AccessibilityFocusState<Bool>.Binding
    var isCollapsed = false
    var tap: GuessMySpotRevealTap?
    /// Collapses or expands the card. Nil: the card can't, as while the reveal plays.
    var onToggle: (() -> Void)?

    @State private var viewer: PaeoniaImageViewerSelection?
    @State private var contentWidth: CGFloat = 0
    @State private var cardFrame: CGRect = .zero
    @State private var photoFrame: CGRect = .zero
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canToggle: Bool { onToggle != nil }
    private static let photoSide: CGFloat = 128
    private static let columnSpacing = PaeoniaSpacing.space16

    /// The photo centers in the left half. The title starts where the photo does,
    /// and the collapse button keeps the same distance from the other edge.
    private var photoInset: CGFloat {
        guard !dynamicTypeSize.isAccessibilitySize else { return 0 }
        return max(0, ((contentWidth - Self.columnSpacing) / 2 - Self.photoSide) / 2)
    }

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
                }
                .buttonStyle(.plain)
                .allowsHitTesting(false)
                .accessibilityHint(Text(.guessMySpotRevealCardExpand))
            } else {
                expandedContent
            }
        }
        .padding(PaeoniaSpacing.space12)
        // The title's line height adds about 8 pt above its letters, so the
        // expanded card matches it below the photo.
        .padding(.bottom, isCollapsed ? PaeoniaSpacing.space4 : PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: PaeoniaRadius.card, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
                .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrame = $0 }
        .onChange(of: tap) { _, tap in
            if let tap { tapped(at: tap.location) }
        }
        .paeoniaImageViewer(selection: $viewer)
        .accessibilityElement(children: .contain)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .accessibilityIdentifier("guessMySpot.reveal.card")
    }

    private var expandedContent: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
                verdict
                    .allowsHitTesting(false)
                collapseButton
            }
            .padding(.horizontal, photoInset)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space12))
                : AnyLayout(HStackLayout(spacing: Self.columnSpacing))
            layout {
                photo
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { photoFrame = $0 }
                    .frame(maxWidth: .infinity)
                scores
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity)
            }
            GuessMySpotPhotoDescriptionReader(
                text: round?.photoAccessibilityText,
                editingTarget: round.flatMap { viewModel.photoDescriptionTarget(for: $0) }
            )
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
    }

    /// A tap on the collapsed card expands it, and one on the photo opens it.
    private func tapped(at location: CGPoint) {
        guard let onToggle else { return }
        if isCollapsed {
            if cardFrame.contains(location) { onToggle() }
        } else if let image, photoFrame.contains(location) {
            presentPhoto(image)
        }
    }

    private var verdict: some View {
        Text(Self.title(for: plan.verdict, isSender: isSender, partnerName: viewModel.partnerName))
            .font(PaeoniaTypography.largeTitle)
            .foregroundStyle(.paeoniaTextPrimary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
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
            countedPoints: countedPoints,
            isCompact: isCollapsed
        )
    }

    private var photo: some View {
        Button {
            if let image { presentPhoto(image) }
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
        .accessibilityLabel(Text(verbatim: PhotoDescription.label(round?.photoAccessibilityText)))
        .accessibilityValue(Text(verbatim: [round?.placeName, GuessMySpotText.takenOn(round?.takenOn)]
            .compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("guessMySpot.reveal.card.photo")
        .transition(.opacity)
    }

    private func presentPhoto(_ image: UIImage) {
        let item = PaeoniaImageViewerItem(image: image, accessibilityText: round?.photoAccessibilityText)
        viewer = PaeoniaImageViewerSelection(items: [item], initialItemID: item.id)
    }

    /// Keeps the map available after the compact card has appeared. It sits on a
    /// hidden letter in the title's font, so it centers on the title's first line.
    /// The space stays while the reveal plays, so the title doesn't rewrap.
    private var collapseButton: some View {
        Text(verbatim: "A")
            .font(PaeoniaTypography.largeTitle)
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .frame(width: Self.collapseSide)
            .overlay {
                if canToggle {
                    collapseButtonBody
                }
            }
    }

    private static let collapseSide: CGFloat = 32

    private var collapseButtonBody: some View {
        Button {
            PaeoniaHaptics.selection()
            onToggle?()
        } label: {
            Image(systemName: "chevron.down")
                .font(PaeoniaTypography.caption.weight(.bold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: Self.collapseSide, height: Self.collapseSide)
                .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// A tap anywhere on the reveal, in global coordinates. Each tap is new, even on the same spot.
struct GuessMySpotRevealTap: Equatable {
    let location: CGPoint
    let id = UUID()
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
