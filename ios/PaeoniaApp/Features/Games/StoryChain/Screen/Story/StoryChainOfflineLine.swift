import SwiftUI

/// "Saved on this phone. We'll send it when you're online." It shows under the
/// page while a move waits to be sent, and offers "Try again" when the server
/// refused the send although the phone is online.
struct StoryChainOfflineLine: View {
    let viewModel: StoryChainViewModel

    var body: some View {
        if viewModel.isHeldOnPhone {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                if viewModel.isSendFailing {
                    Label {
                        Text(.storyChainWaitingToSyncFailedTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaSyncPending)
                    Button {
                        Task { await viewModel.retrySend() }
                    } label: {
                        Text(.commonTryAgain)
                    }
                    .buttonStyle(PaeoniaQuietButtonStyle())
                    .accessibilityIdentifier("storyChain.retry")
                } else {
                    Label {
                        Text(.gamesPendingSavedOnPhone)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "clock")
                            .accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaSyncPending)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            .accessibilityIdentifier("storyChain.pending")
        }
    }
}
