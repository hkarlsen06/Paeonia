import SwiftUI

/// "Tell [Name] you want to play". It shows only while the partner is not in the
/// game, reads "Sent" after a send with the time the next one can go, and comes
/// back 15 minutes after the last invite (`GameInviteState`). The caller's
/// state drives all of it. It shares its words with the Draw & Guess button.
struct BoardGameInviteButton: View {
    let state: GameInviteState
    let partnerName: String
    let onSend: () -> Void

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .available:
            sendButton
        case let .sent(until):
            VStack(spacing: PaeoniaSpacing.space8) {
                Button {} label: {
                    Label {
                        Text(.gamesInviteSent)
                    } icon: {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .disabled(true)
                .accessibilityIdentifier("boardGames.invite.sent")
                Text(.gamesInviteSentUntil(until.formatted(date: .omitted, time: .shortened)))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Text(.gamesInviteButton(partnerName))
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .accessibilityIdentifier("boardGames.invite")
    }
}

#if DEBUG
#Preview {
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameInviteButton(state: .available, partnerName: "Robin", onSend: {})
        BoardGameInviteButton(
            state: .sent(until: Date.now.addingTimeInterval(GameInviteState.interval)),
            partnerName: "Robin",
            onSend: {}
        )
        BoardGameInviteButton(state: .hidden, partnerName: "Robin", onSend: {})
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
