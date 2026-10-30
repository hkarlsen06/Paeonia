import SwiftUI

/// This person's word is locked in and the partner's is not. It says the word is
/// safe, shows two cards (mine face up with a lock, theirs face down), and makes
/// the wait feel shared. When the partner locks in, the screen gives way to the reveal.
struct MindMeldWaitingView: View {
    let viewModel: MindMeldViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A little smaller than on the reveal, where the cards grow.
    private static let cardWidth: CGFloat = 128

    private var partnerIsHere: Bool {
        viewModel.isPartnerHere
    }

    private var isTyping: Bool {
        viewModel.partnerStatus == .typing
    }

    private var myWord: String {
        viewModel.round?.myWord ?? ""
    }

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space16)
                cards
                text
                if viewModel.showsOfflineLine {
                    GameOfflineLine(identifier: "mindMeld.pending")
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        }
        .gameInviteToolbar(
            invite: viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "mindMeld.invite"
        )
        // The partner's phone changes the title, the hint and presence while this
        // screen is open. Everything moves to its new place together.
        .animation(stateChange, value: viewModel.partnerStatus)
        .animation(stateChange, value: viewModel.showsOfflineLine)
        .onChange(of: viewModel.isPartnerHere) { old, new in
            if !old, new {
                PaeoniaHaptics.partnerDrawingReceived()
                GameSound.nudge.play(volume: 0.7)
            }
        }
        .accessibilityIdentifier("mindMeld.waiting")
    }

    private var stateChange: Animation {
        reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.stateChange
    }

    // MARK: Cards

    private var cards: some View {
        HStack(spacing: PaeoniaSpacing.space24) {
            MindMeldWordCard(
                word: myWord,
                isFaceUp: true,
                faceDownLabel: .mindMeldWaitYourWordA11Y(myWord),
                isLocked: true,
                maxWidth: Self.cardWidth
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.mindMeldWaitYourWordA11Y(myWord)))
            MindMeldWordCard(
                word: nil,
                isFaceUp: false,
                faceDownLabel: .mindMeldWaitPartnerCardA11Y(viewModel.partnerName),
                maxWidth: Self.cardWidth
            )
            .overlay {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: viewModel.partner.photoAssetID,
                    name: viewModel.partner.name,
                    tint: .paeoniaPartnerTwo,
                    size: 40
                )
                .gamePresenceRing(partnerIsHere)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Text

    private var text: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space8) {
                Text(title)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .contentTransition(.opacity)
                if isTyping {
                    GameTypingDots()
                        .transition(.opacity)
                }
            }
            Text(hint)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .contentTransition(.opacity)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(partnerIsHere ? .gamesPresenceHere : .gamesPresenceAway))
    }

    private var title: LocalizedStringResource {
        if isTyping { return .mindMeldPartnerTyping(viewModel.partnerName) }
        return partnerIsHere ? .mindMeldPartnerHere(viewModel.partnerName) : .mindMeldWaitTitle(viewModel.partnerName)
    }

    private var hint: LocalizedStringResource {
        partnerIsHere ? .mindMeldWaitHintLive : .mindMeldWaitHintLater(viewModel.partnerName)
    }
}
