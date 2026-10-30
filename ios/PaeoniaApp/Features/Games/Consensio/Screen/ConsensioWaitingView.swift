import SwiftUI

/// The partner's turn. While they guess this person's marker, the line shows
/// the real spot to its owner, and live the partner's guess pin moving toward it.
/// While they pick a topic, their portrait shows presence. Either way the screen says
/// what happens next.
struct ConsensioWaitingView: View {
    let viewModel: ConsensioViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The live pin is this close to the real spot, so the track between them warms.
    private static let warmDistance = 7

    private var isWaitingForGuess: Bool {
        if case .waitingForGuess = viewModel.phase { return true }
        return false
    }

    private var partnerIsHere: Bool {
        viewModel.partnerStatus != .away
    }

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space16)
                if isWaitingForGuess, let round = viewModel.round {
                    line(for: round)
                } else {
                    avatar
                }
                text
                if viewModel.isHeldOnPhone {
                    ConsensioHeldLine(viewModel: viewModel) {
                        GameOfflineLine(identifier: "consensio.pending")
                            .multilineTextAlignment(.center)
                    }
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
            identifier: "consensio.invite"
        )
        .animation(stateChange, value: viewModel.partnerStatus)
        .animation(stateChange, value: viewModel.isHeldOnPhone)
        .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0), value: viewModel.partnerMarker)
        .onChange(of: viewModel.partnerStatus) { old, new in
            if old == .away, new != .away {
                PaeoniaHaptics.partnerDrawingReceived()
                GameSound.nudge.play(volume: 0.6)
            }
        }
        .accessibilityIdentifier(isWaitingForGuess ? "consensio.waiting.guess" : "consensio.waiting.topic")
    }

    private var stateChange: Animation {
        reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.stateChange
    }

    // MARK: Line

    private func line(for round: RemoteConsensioRound) -> some View {
        var pins: [ConsensioScale.Pin] = []
        if let spot = round.spot {
            pins.append(ConsensioScale.Pin(id: "mine", position: spot, style: viewModel.myStyle, opacity: 0.6))
        }
        var warmth: (from: Int, to: Int)?
        if let guess = viewModel.partnerMarker {
            pins.append(ConsensioScale.Pin(
                id: "partner",
                position: guess,
                style: viewModel.partnerStyle,
                isLifted: viewModel.partnerIsTouching
            ))
            if let spot = round.spot, abs(spot - guess) <= Self.warmDistance {
                warmth = (spot, guess)
            }
        }
        return VStack(spacing: PaeoniaSpacing.space8) {
            Text(verbatim: round.subject)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
            ConsensioScale(
                subject: round.subject,
                leftEnd: round.leftEnd,
                rightEnd: round.rightEnd,
                pins: pins,
                warmth: warmth
            )
            .accessibilityValue(Text(partnerGuessA11y))
        }
    }

    private var partnerGuessA11y: LocalizedStringResource {
        guard let guess = viewModel.partnerMarker, let round = viewModel.round else {
            return .consensioWaitYourSpotA11Y
        }
        return .consensioScalePartnerA11Y(
            viewModel.partnerName,
            ConsensioScaleValue.string(guess, in: round)
        )
    }

    // MARK: Avatar

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

    private var text: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
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
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(partnerIsHere ? .gamesPresenceHere : .gamesPresenceAway))
    }

    private var title: LocalizedStringResource {
        switch viewModel.partnerStatus {
        case .guessing where isWaitingForGuess: .consensioWaitGuessing(viewModel.partnerName)
        case .picking where !isWaitingForGuess: .consensioWaitChoosing(viewModel.partnerName)
        default: .consensioWaitTitle(viewModel.partnerName)
        }
    }

    private var hint: LocalizedStringResource {
        if partnerIsHere, isWaitingForGuess { return .consensioWaitHintLive(viewModel.partnerName) }
        return isWaitingForGuess ? .consensioWaitHintGuess(viewModel.partnerName) : .consensioWaitHintTurn
    }
}
