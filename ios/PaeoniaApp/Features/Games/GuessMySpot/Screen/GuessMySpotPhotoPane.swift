import SwiftUI

/// A round's photo in its half of the screen: pinch and double tap to look
/// closer. While it downloads, a spinner. When it can't be fetched, a line and
/// Try again.
struct GuessMySpotPhotoPane: View {
    let image: UIImage?
    var failed = false
    var retry: (() -> Void)?

    @State private var showsSpinner = false

    var body: some View {
        ZStack {
            if let image {
                PaeoniaZoomableImageView(image: image, isActive: true, onZoomStateChanged: { _ in })
                    .accessibilityElement()
                    .accessibilityLabel(Text(.guessMySpotPhotoA11Y))
                    .accessibilityAddTraits(.isImage)
                    .transition(.opacity)
            } else if failed {
                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(.guessMySpotGuessPhotoFailed)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .multilineTextAlignment(.center)
                    if let retry {
                        Button(action: retry) {
                            Text(.commonTryAgain)
                        }
                        .buttonStyle(PaeoniaQuietButtonStyle())
                        .accessibilityIdentifier("guessMySpot.photo.retry")
                    }
                }
                .padding(PaeoniaSpacing.space16)
            } else {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .opacity(showsSpinner ? 1 : 0)
                    .task {
                        try? await Task.sleep(for: .seconds(0.3))
                        showsSpinner = true
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(PaeoniaMotion.stateChange, value: image == nil)
        .accessibilityIdentifier("guessMySpot.photo")
    }
}
