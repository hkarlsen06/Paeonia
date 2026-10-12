import SwiftUI

/// The short states around the turns: loading, creating the game, setup not done,
/// and a move that still waits to reach the server.
struct DrawAndGuessStatusView: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        DrawAndGuessFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space16) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .drawAndGuessScoreToolbar(viewModel)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .needsSetup:
            PaeoniaEmptyStateView(
                title: .gamesDrawAndGuessName,
                message: .gamesDrawAndGuessNeedsSetup,
                systemImage: "gamecontroller.fill"
            )
        case .preparing where viewModel.startFailed:
            PaeoniaEmptyStateView(
                title: .gamesNoticeStartFailedTitle,
                message: .gamesNoticeStartFailedMessage,
                systemImage: "wifi.slash"
            ) {
                Button {
                    Task { await viewModel.retryStart() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        case .waitingToSync:
            PaeoniaEmptyStateView(
                title: .gamesPendingSavedOnPhone,
                message: .gamesDrawAndGuessWaitingToSyncMessage,
                systemImage: "clock"
            )
        default:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .controlSize(.large)
        }
    }
}
