import SwiftUI

/// "Tell [Name] you want to play". It shows only while the partner is not in the
/// game, reads "Sent" after a send with the time the next one can go, and comes
/// back 15 minutes after the last invite. The game's tick brings it back.
/// `identifier` is the accessibility identifier of the send button, and the
/// "Sent" button adds `.sent` to it.
struct GameInviteButton: View {
    let invite: GameInviteState
    let partnerName: String
    let send: () async -> Void
    var identifier = "game.invite"

    var body: some View {
        switch invite {
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
                .accessibilityIdentifier("\(identifier).sent")
                Text(.gamesInviteSentUntil(until.formatted(date: .omitted, time: .shortened)))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            Text(.gamesInviteButton(partnerName))
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}
