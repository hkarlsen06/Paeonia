import SwiftUI

/// A failed send and its retry action. Routine queued sends show no status.
struct StoryChainOfflineLine: View {
    let viewModel: StoryChainViewModel

    var body: some View {
        if viewModel.isHeldOnPhone, viewModel.isSendFailing {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            .accessibilityIdentifier("storyChain.pending")
        }
    }
}
