import MapKit
import SwiftUI

/// The partner's turn. While they guess this person's photo, the photo and its
/// spot show to their owner, and live the partner's pin lands where they tap.
/// While they pick a photo, their avatar breathes. Either way the screen says what
/// happens next.
struct GuessMySpotWaitingView: View {
    let viewModel: GuessMySpotViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false
    @State private var camera = GuessMySpotCamera.world

    /// The live pin is this close to the real spot, so the spot's pin glows gold.
    private static let warmMeters = 25_000

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
        GuessMySpotSplitLayout {
            EmptyView()
        } photo: {
            GuessMySpotPhotoPane(
                image: viewModel.roundPhoto,
                failed: viewModel.roundPhotoFailed,
                retry: viewModel.retryRoundPhoto
            )
        } map: {
            GuessMySpotMap(
                position: $camera,
                pins: pins(for: round),
                accessibilityValue: viewModel.partnerPin == nil ? .guessMySpotWaitYourSpotA11Y
                    : .guessMySpotWaitPartnerPinA11Y(viewModel.partnerName)
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
        .onChange(of: viewModel.partnerPin) { _, pin in
            // Frame both pins as the partner's lands, so the sender sees how close it is.
            guard let pin, let spot = round.spot else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                camera = GuessMySpotCamera.framing(pin, spot)
            }
        }
    }

    private func pins(for round: RemoteGuessMySpotRound) -> [GuessMySpotMap.Pin] {
        var pins: [GuessMySpotMap.Pin] = []
        if let spot = round.spot {
            // It glows gold while the partner's live guess is near it.
            pins.append(GuessMySpotMap.Pin(
                id: "mine",
                coordinate: spot,
                style: viewModel.myStyle,
                opacity: isWarm(round) ? 1 : 0.6,
                glow: isWarm(round) ? 0.8 : 0
            ))
        }
        if let guess = viewModel.partnerPin {
            pins.append(GuessMySpotMap.Pin(id: "partner", coordinate: guess, style: viewModel.partnerStyle))
        }
        return pins
    }

    private func isWarm(_ round: RemoteGuessMySpotRound) -> Bool {
        guard let spot = round.spot, let guess = viewModel.partnerPin else { return false }
        return GuessMySpotRules.distanceMeters(guess, spot) <= Self.warmMeters
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
            Text(title)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .contentTransition(.opacity)
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
