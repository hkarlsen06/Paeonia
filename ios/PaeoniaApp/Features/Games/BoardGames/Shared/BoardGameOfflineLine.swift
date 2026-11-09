import SwiftUI

/// A failed move and its retry action. Routine queued moves show no status.
struct BoardGameOfflineLine: View {
    let isFailing: Bool
    let onRetry: () -> Void

    var body: some View {
        if isFailing {
            failed
        }
    }

    private var failed: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Label {
                Text(.boardGamesOfflineFailed)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaSyncPending)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("boardGames.pending.failed")

            Button(action: onRetry) {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .accessibilityIdentifier("boardGames.pending.retry")
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameOfflineLine(isFailing: false, onRetry: {})
        BoardGameOfflineLine(isFailing: true, onRetry: {})
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
