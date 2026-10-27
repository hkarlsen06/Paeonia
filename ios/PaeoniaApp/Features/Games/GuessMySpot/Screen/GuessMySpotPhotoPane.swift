import SwiftUI

/// A round's photo filling its pane. A tap or a pinch opens it full screen to look closer.
/// While it downloads, the partner's blurred preview when there is one, and the
/// photo sharpens out of it. Otherwise a spinner. When it can't be fetched, a line
/// and Try again.
struct GuessMySpotPhotoPane: View {
    /// The photo's part of the room it shares with the map on the split screens. It
    /// is small because a tap opens the photo, and the map needs room to pan and zoom.
    static let splitShare: CGFloat = 0.3

    let image: UIImage?
    var preview: UIImage?
    var failed = false
    var retry: (() -> Void)?

    @State private var showsSpinner = false
    @State private var viewer: PaeoniaImageViewerSelection?

    var body: some View {
        ZStack {
            if let image {
                filled(image)
                    .transition(preview == nil ? .opacity : AnyTransition(.blurReplace))
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
            } else if let preview {
                blurred(preview)
                    .transition(.blurReplace)
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
        // The photo sharpening out of the preview takes its time.
        .animation(preview == nil ? PaeoniaMotion.stateChange : PaeoniaMotion.meaningfulMoment, value: image == nil)
        .animation(PaeoniaMotion.meaningfulMoment, value: preview)
        .paeoniaImageViewer(selection: $viewer)
        .accessibilityIdentifier("guessMySpot.photo")
    }

    private func blurred(_ preview: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: preview)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .blur(radius: 16, opaque: true)
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(Text(.guessMySpotPhotoPreviewA11Y))
            .accessibilityAddTraits(.isImage)
    }

    private func filled(_ image: UIImage) -> some View {
        // The photo fills a clear box, so its overflow is cut at the pane's edge.
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // The clip cuts only the drawing. The filled image would still take
                    // touches past the pane, over the map. The box takes the taps.
                    .allowsHitTesting(false)
                    .accessibilityIgnoresInvertColors()
                    .accessibilityHidden(true)
            }
            .clipped()
            .contentShape(.rect)
            .onTapGesture {
                viewer = PaeoniaImageViewerSelection(image: image)
            }
            // The pane is too small to zoom in, so a pinch outward opens the viewer
            // to zoom there. Pinching inward does nothing.
            .gesture(
                MagnifyGesture().onChanged { value in
                    guard value.magnification > 1.05, viewer == nil else { return }
                    viewer = PaeoniaImageViewerSelection(image: image)
                }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(.guessMySpotPhotoA11Y))
            .accessibilityAddTraits([.isImage, .isButton])
    }
}
