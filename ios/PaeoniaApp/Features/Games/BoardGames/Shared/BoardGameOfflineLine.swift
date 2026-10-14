import SwiftUI

/// What the pinned bottom says while a move waits to leave the phone. Offline,
/// it is a calm "Saved on this phone" line. When the last try reached the server
/// and failed there, it says so and offers "Try again". It takes no space when
/// nothing waits.
struct BoardGameOfflineLine: View {
    let isWaiting: Bool
    let failedWhileOnline: Bool
    let onRetry: () -> Void

    var body: some View {
        if isWaiting {
            if failedWhileOnline {
                failed
            } else {
                saved
            }
        }
    }

    /// "Saved on this phone. We'll send it when you're online."
    private var saved: some View {
        Label {
            Text(.gamesPendingSavedOnPhone)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "clock")
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaSyncPending)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("boardGames.pending")
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
        BoardGameOfflineLine(isWaiting: true, failedWhileOnline: false, onRetry: {})
        BoardGameOfflineLine(isWaiting: true, failedWhileOnline: true, onRetry: {})
        BoardGameOfflineLine(isWaiting: false, failedWhileOnline: false, onRetry: {})
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
