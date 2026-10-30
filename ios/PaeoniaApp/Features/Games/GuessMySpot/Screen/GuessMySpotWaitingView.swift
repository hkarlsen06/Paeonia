import MapKit
import SwiftUI

/// The partner's turn. While they guess this person's photo, the photo and its
/// spot show to their owner, and live the map shows what the partner's map shows.
/// While they pick a photo, their portrait shows presence, and once they picked one it shows
/// blurred where the guess screen will show it. Either way the screen says what
/// happens next.
struct GuessMySpotWaitingView: View {
    let viewModel: GuessMySpotViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = GuessMySpotCamera.world

    private var isWaitingForGuess: Bool {
        if case .waitingForGuess = viewModel.phase { return true }
        return false
    }

    private var partnerIsHere: Bool {
        viewModel.partnerStatus != .away
    }

    var body: some View {
        Group {
            if isWaitingForGuess, let round = viewModel.round {
                waitingForGuess(round)
            } else {
                waitingForPhoto
            }
        }
        .gameInviteToolbar(
            invite: viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "guessMySpot.invite"
        )
        .animation(stateChange, value: viewModel.partnerStatus)
        .animation(stateChange, value: viewModel.isHeldOnPhone)
        .onChange(of: viewModel.partnerStatus) { old, new in
            if old == .away, new != .away {
                PaeoniaHaptics.partnerDrawingReceived()
                GameSound.nudge.play(volume: 0.6)
            }
        }
        .accessibilityIdentifier(isWaitingForGuess ? "guessMySpot.waiting.guess" : "guessMySpot.waiting.photo")
    }

    private var stateChange: Animation {
        reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.stateChange
    }

    // MARK: Waiting for the guess

    private func waitingForGuess(_ round: RemoteGuessMySpotRound) -> some View {
        let partnerView = viewModel.partnerMapView
        return GuessMySpotSplitLayout {
            EmptyView()
        } photo: {
            GuessMySpotPhotoPane(
                image: viewModel.roundPhoto,
                failed: viewModel.roundPhotoFailed,
                retry: viewModel.retryRoundPhoto
            )
        } map: {
            // Live, the map follows the partner's and can't be moved here.
            GuessMySpotMap(
                position: $camera,
                pins: pins(for: round),
                isInteractive: partnerView == nil,
                showsSatelliteButton: partnerView == nil,
                accessibilityValue: partnerView == nil ? .guessMySpotWaitYourSpotA11Y
                    : .guessMySpotWaitPartnerMapA11Y(viewModel.partnerName),
                satellite: partnerView.map { .constant($0.satellite) }
            )
        } footer: {
            VStack(spacing: PaeoniaSpacing.space12) {
                text
                heldLine
            }
        } bottom: {
            EmptyView()
        }
        .onChange(of: round.id, initial: true) { _, _ in
            camera = round.spot.map { GuessMySpotCamera.around($0, meters: 4_000) } ?? GuessMySpotCamera.world
        }
        .onChange(of: partnerView) { _, view in
            guard let view else { return }
            camera = .rect(view.rect)
        }
    }

    private func pins(for round: RemoteGuessMySpotRound) -> [GuessMySpotMap.Pin] {
        guard let spot = round.spot else { return [] }
        return [GuessMySpotMap.Pin(id: "mine", coordinate: spot, style: viewModel.myStyle, opacity: 0.6)]
    }

    // MARK: Waiting for a photo

    private var waitingForPhoto: some View {
        ZStack {
            if let preview = viewModel.partnerPhotoPreview {
                photoComing(preview)
                    .transition(.blurReplace)
            } else {
                pickingPhoto
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment,
            value: viewModel.partnerPhotoPreview == nil
        )
    }

    /// The partner picked a photo and checks it. It shows blurred above the map,
    /// laid out as the guess screen, which takes over in place once it is sent.
    private func photoComing(_ preview: GuessMySpotPhotoPreview) -> some View {
        GuessMySpotSplitLayout {
            GameLiveRow {
                GamePresenceLabel(player: viewModel.partner, text: title, isHere: partnerIsHere)
            } trailing: {
                EmptyView()
            }
        } photo: {
            GuessMySpotPhotoPane(image: nil, preview: preview.image)
        } map: {
            GuessMySpotMap(
                position: .constant(GuessMySpotCamera.world),
                isInteractive: false,
                showsSatelliteButton: false
            )
            .overlay(alignment: .bottom) {
                Text(.guessMySpotWaitPreviewHint)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextPrimary)
                    .padding(.horizontal, PaeoniaSpacing.space12)
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Capsule())
                    .padding(PaeoniaSpacing.space12)
                    .allowsHitTesting(false)
            }
        } footer: {
            heldLine
        } bottom: {
            EmptyView()
        }
    }

    private var pickingPhoto: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space16)
                avatar
                text
                heldLine
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var avatar: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: viewModel.partner.photoAssetID,
            name: viewModel.partner.name,
            tint: .paeoniaPartnerTwo,
            size: 96
        )
        .gamePresenceRing(partnerIsHere)
        .accessibilityHidden(true)
    }

    // MARK: Text

    @ViewBuilder
    private var heldLine: some View {
        if viewModel.isHeldOnPhone {
            GuessMySpotHeldLine(viewModel: viewModel) {
                GameOfflineLine(identifier: "guessMySpot.pending")
                    .multilineTextAlignment(.center)
            }
            .transition(.opacity)
        }
    }

    private var text: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            HStack(spacing: PaeoniaSpacing.space8) {
                if isWaitingForGuess {
                    GameAvatar(player: viewModel.partner, isMe: false, size: 24)
                        .gamePresenceRing(partnerIsHere)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .contentTransition(.opacity)
            }
            Text(hint)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .contentTransition(.opacity)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(partnerIsHere ? .gamesPresenceHere : .gamesPresenceAway))
    }

    private var title: LocalizedStringResource {
        switch viewModel.partnerStatus {
        case .guessing where isWaitingForGuess: .guessMySpotWaitGuessing(viewModel.partnerName)
        case .picking where !isWaitingForGuess: .guessMySpotWaitChoosing(viewModel.partnerName)
        default: .guessMySpotWaitTitle(viewModel.partnerName)
        }
    }

    private var hint: LocalizedStringResource {
        if partnerIsHere, isWaitingForGuess { return .guessMySpotWaitHintLive(viewModel.partnerName) }
        return isWaitingForGuess ? .guessMySpotWaitHintGuess(viewModel.partnerName) : .guessMySpotWaitHintTurn
    }
}
