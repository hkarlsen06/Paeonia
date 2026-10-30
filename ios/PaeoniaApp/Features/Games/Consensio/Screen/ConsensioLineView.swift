import SwiftUI

/// The line with this person's own pin: placing it where they stand, or
/// guessing where the partner put theirs. The pin starts in the middle and is
/// dragged either way.
struct ConsensioLineView: View {
    enum Role {
        case place
        case guess
    }

    @Bindable var viewModel: ConsensioViewModel
    let role: Role

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The topic on the line: the one being placed, or the partner's round.
    private var topic: ConsensioTopicChoice {
        switch role {
        case .place:
            viewModel.placingTopic ?? .own(subject: "", leftEnd: "", rightEnd: "")
        case .guess:
            .own(
                subject: viewModel.round?.subject ?? "",
                leftEnd: viewModel.round?.leftEnd ?? "",
                rightEnd: viewModel.round?.rightEnd ?? ""
            )
        }
    }

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                if role == .guess {
                    liveRow
                }
                Spacer(minLength: PaeoniaSpacing.space8)
                heading
                scale
                .padding(.vertical, PaeoniaSpacing.space16)
                if role == .place {
                    Text(.consensioPlaceHint(viewModel.partnerName))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            lockButton
        }
        .gameInviteToolbar(
            invite: role == .guess ? viewModel.invite : .hidden,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "consensio.invite"
        )
        .accessibilityIdentifier(role == .place ? "consensio.place" : "consensio.guess")
    }

    private var scale: some View {
        ConsensioScale(
            subject: topic.subject,
            leftEnd: topic.leftEnd,
            rightEnd: topic.rightEnd,
            editable: ConsensioScale.Editable(
                position: viewModel.marker,
                style: viewModel.myStyle,
                move: { position, isTouching in
                    withAnimation(viewModel.marker == nil && !reduceMotion ? PaeoniaMotion.cardReveal : nil) {
                        viewModel.moveMarker(to: position, isTouching: isTouching)
                    }
                }
            )
        )
    }

    private var heading: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(verbatim: topic.subject)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(role == .place ? .consensioPlaceQuestion : .consensioGuessQuestion(viewModel.partnerName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var liveRow: some View {
        GameLiveRow {
            let isHere = viewModel.partnerStatus != .away
            let name = viewModel.partnerName
            GamePresenceLabel(
                player: viewModel.partner,
                text: isHere ? .consensioGuessWatching(name) : .consensioGuessLater(name),
                isHere: isHere
            )
            .animation(PaeoniaMotion.stateChange, value: isHere)
        } trailing: {
            EmptyView()
        }
    }

    private var lockButton: some View {
        Button {
            let locked = role == .place ? viewModel.lockPlacement() : viewModel.lockGuess()
            if locked {
                PaeoniaHaptics.drawingSent()
                GameSound.send.play()
            } else {
                PaeoniaHaptics.validationError()
            }
        } label: {
            Label {
                Text(role == .place ? .consensioPlaceLock : .consensioGuessLock)
            } icon: {
                Image(systemName: "lock.fill").accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(viewModel.marker == nil)
        .accessibilityIdentifier(role == .place ? "consensio.place.lock" : "consensio.guess.lock")
    }
}
