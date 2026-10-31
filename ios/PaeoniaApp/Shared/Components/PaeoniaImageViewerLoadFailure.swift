import SwiftUI

struct PaeoniaImageViewerLoadFailure: View {
    let failure: PaeoniaFailure
    let description: String?
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space16) {
                Text(verbatim: PhotoDescription.label(description))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("imageViewer.failure.description")

                PaeoniaLoadFailureView(
                    failure: failure,
                    offlineMessage: .imageViewerLoadOffline,
                    failedMessage: .imageViewerLoadFailed
                ) {
                    Button(.commonTryAgain, action: retry)
                        .buttonStyle(PaeoniaPrimaryButtonStyle())
                        .accessibilityIdentifier("imageViewer.retry")
                }
            }
            .padding(PaeoniaSpacing.space16)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
