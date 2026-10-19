import SwiftUI

/// What a move still on this phone says. Offline: that it is saved and goes out
/// later. After a failed send on a working connection: that it didn't go yet, with
/// Try again, because "when you're online" would be wrong then.
struct GuessMySpotHeldLine<Offline: View>: View {
    let viewModel: GuessMySpotViewModel
    @ViewBuilder var offline: Offline

    var body: some View {
        if viewModel.isSendFailing {
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
                .accessibilityIdentifier("guessMySpot.retrySend")
            }
            .multilineTextAlignment(.center)
        } else {
            offline
        }
    }
}
