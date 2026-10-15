import SwiftUI

/// What a square shows while a drawing is not on the phone: a spinner while it
/// downloads, or the failed download and its Try again button.
struct GameDrawingPlaceholder: View {
    let loadFailed: Bool
    let retry: () -> Void

    var body: some View {
        if loadFailed {
            PaeoniaEmptyStateView(
                title: .gamesNoticeDrawingUnavailableTitle,
                message: .gamesNoticeDrawingUnavailableMessage,
                systemImage: "exclamationmark.circle"
            ) {
                Button {
                    retry()
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
            .padding(PaeoniaSpacing.space16)
        } else {
            GameDrawingSpinner()
        }
    }
}

/// A small spinner that waits a moment before it shows, so a drawing that
/// arrives quickly never flashes it.
private struct GameDrawingSpinner: View {
    @State private var isShown = false

    var body: some View {
        ProgressView()
            .tint(.paeoniaAccentPrimary)
            .opacity(isShown ? 1 : 0)
            .accessibilityLabel(Text(.gamesDrawingLoading))
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(PaeoniaMotion.stateChange) { isShown = true }
            }
    }
}
