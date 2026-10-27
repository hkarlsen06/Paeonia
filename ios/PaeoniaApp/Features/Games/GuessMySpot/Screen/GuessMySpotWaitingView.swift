import MapKit
import SwiftUI

/// The partner's turn. While they guess this person's photo, the photo and its
/// spot show to their owner, and live the map shows what the partner's map shows.
/// While they pick a photo, their avatar breathes. Either way the screen says what
/// happens next.
struct GuessMySpotWaitingView: View {
    let viewModel: GuessMySpotViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false
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
        .overlay {
            Circle()
                .strokeBorder(.paeoniaAccentPrimary, lineWidth: 3)
                .padding(-6)
                .opacity(partnerIsHere ? (reduceMotion ? 0.35 : (breathes ? 0.5 : 0.2)) : 0)
        }
        .gamePresenceDot(partnerIsHere, size: 20)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathes = true
            }
        }
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
                // While the partner guesses there is no avatar on screen, so the dot
                // sits by the title.
                if partnerIsHere, isWaitingForGuess {
                    GamePresenceDot(size: 12)
                        .transition(.scale.combined(with: .opacity))
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
