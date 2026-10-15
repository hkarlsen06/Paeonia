import SwiftUI

/// The partner's avatar at 96 pt. A soft ring breathes around it while the
/// partner is in the game. The ring stays in the layout and fades in and out, and
/// the breathing covers only its opacity, so it moves with the avatar when the
/// layout changes.
struct ExquisiteCorpsePartnerAvatar: View {
    let player: GamePlayer
    let isPartnerHere: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        GameAvatar(player: player, isMe: false, size: 96)
            .background { ring }
            .padding(PaeoniaSpacing.space8)
    }

    private var ring: some View {
        Circle()
            .stroke(.paeoniaAccentPrimary, lineWidth: 4)
            .padding(-PaeoniaSpacing.space8)
            .blur(radius: 1.5)
            .animation(reduceMotion ? nil : breathing) {
                $0.opacity(reduceMotion ? 0.35 : isBreathing ? 0.5 : 0.2)
            }
            .opacity(isPartnerHere ? 1 : 0)
            .onAppear { isBreathing = true }
            .accessibilityHidden(true)
    }

    private var breathing: Animation {
        PaeoniaMotion.standardCurve(duration: 2.4).repeatForever(autoreverses: true)
    }
}

extension View {
    /// "Tell [Name] you want to play" in the toolbar, while the partner is not in the game.
    func exquisiteCorpseInviteToolbar(_ viewModel: ExquisiteCorpseViewModel) -> some View {
        gameInviteToolbar(
            invite: viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "corpse.invite"
        )
    }
}

/// What happened to the part this person sent, under the waiting title: it went
/// through, it waits on this phone, or it could not be sent although the phone is
/// online. A part that is on its way says nothing.
struct ExquisiteCorpseSendStatus: View {
    let viewModel: ExquisiteCorpseViewModel

    var body: some View {
        if viewModel.isSendFailing {
            ExquisiteCorpseSendFailure(viewModel: viewModel)
        } else if viewModel.isHeldOnPhone {
            GameOfflineLine()
        } else if viewModel.didSendPreviousPart, !viewModel.isWaitingToSend {
            Label {
                Text(.exquisiteCorpseWaitSent(viewModel.partnerName))
            } icon: {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextSecondary)
            .transition(.opacity)
            .accessibilityIdentifier("corpse.sent")
        }
    }
}

/// "We couldn't send your move yet" and Try again, for a part that waits on this
/// phone and keeps failing although the phone is online.
struct ExquisiteCorpseSendFailure: View {
    let viewModel: ExquisiteCorpseViewModel

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Label {
                Text(.gamesWaitingToSyncFailedTitle)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.body.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            Text(.gamesWaitingToSyncFailedMessage)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            Button {
                Task { await viewModel.retrySending() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .accessibilityIdentifier("corpse.retry")
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .contain)
    }
}
