import SwiftUI

/// The short states around the turns: loading, creating the game, setup not done,
/// and a move that still waits to reach the server.
struct DrawAndGuessStatusView: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
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
        case .loading where viewModel.refreshFailure != nil:
            PaeoniaLoadFailureView(
                failure: viewModel.refreshFailure ?? .other,
                offlineMessage: .gamesUnavailableMessage
            ) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .accessibilityIdentifier("drawAndGuess.retryLoad")
            }
        case .needsSetup:
            PaeoniaEmptyStateView(
                title: .gamesDrawAndGuessName,
                message: .gamesNeedsSetup,
                systemImage: "gamecontroller.fill"
            )
        case .preparing where viewModel.startFailure != nil:
            PaeoniaLoadFailureView(
                failure: viewModel.startFailure ?? .other,
                offlineTitle: .gamesNoticeStartFailedTitle,
                offlineMessage: .gamesNoticeStartFailedMessage,
                failedMessage: .commonActionFailedMessage
            ) {
                Button {
                    Task { await viewModel.retryStart() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        case .waitingToSync where viewModel.sendState.isFailing:
            PaeoniaEmptyStateView(
                title: .gamesWaitingToSyncFailedTitle,
                message: .gamesWaitingToSyncFailedMessage,
                systemImage: "exclamationmark.triangle"
            ) {
                Button {
                    Task { await viewModel.retrySending() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        default:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .controlSize(.large)
        }
    }
}
