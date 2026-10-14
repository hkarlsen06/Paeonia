import SwiftUI

/// The short states around the turns: loading, creating the game, setup not done,
/// and a move that still waits to reach the server.
struct StoryChainStatusView: View {
    let viewModel: StoryChainViewModel

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space16) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .needsSetup:
            PaeoniaEmptyStateView(
                title: .storyChainName,
                message: .storyChainNeedsSetup,
                systemImage: "books.vertical"
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
                .accessibilityIdentifier("storyChain.retryStart")
            }
        case .waitingToSync where viewModel.isHeldOnPhone:
            PaeoniaEmptyStateView(
                title: viewModel.isSendFailing ? .storyChainWaitingToSyncFailedTitle : .gamesPendingSavedOnPhone,
                message: viewModel.isSendFailing
                    ? .storyChainWaitingToSyncFailedMessage
                    : .storyChainWaitingToSyncMessage,
                systemImage: viewModel.isSendFailing ? "exclamationmark.triangle" : "clock"
            ) {
                Button {
                    Task { await viewModel.retrySend() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .accessibilityIdentifier("storyChain.retry")
            }
        default:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .controlSize(.large)
        }
    }
}
