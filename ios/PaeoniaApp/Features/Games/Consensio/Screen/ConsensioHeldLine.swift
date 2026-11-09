import SwiftUI

/// A failed send and its retry action. Routine queued sends show no status.
struct ConsensioHeldLine: View {
    let viewModel: ConsensioViewModel

    var body: some View {
        if viewModel.sendState.isFailing {
            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.gamesWaitingToSyncFailedTitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                Button {
                    Task { await viewModel.retrySend() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .accessibilityIdentifier("consensio.retrySend")
            }
            .multilineTextAlignment(.center)
        }
    }
}
