import SwiftUI

/// "Tell [Name] you want to play". It shows only while the partner is not in the
/// game, reads "Sent" after a send with the time the next one can go, and comes
/// back 15 minutes after the last invite. The view model's tick brings it back.
struct MindMeldInviteButton: View {
    let viewModel: MindMeldViewModel

    var body: some View {
        switch viewModel.invite {
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
                .accessibilityIdentifier("mindMeld.invite.sent")
                Text(.gamesInviteSentUntil(until.formatted(date: .omitted, time: .shortened)))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.sendInvite() }
        } label: {
            Text(.gamesInviteButton(viewModel.partnerName))
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .accessibilityIdentifier("mindMeld.invite")
    }
}
