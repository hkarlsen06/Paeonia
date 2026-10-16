import SwiftUI

/// The live camera in the story composer, with the round shutter button at the bottom
/// center and the switch-camera button beside it. Without camera access it says why
/// and offers Settings.
struct StoryViewfinder: View {
    let camera: StoryCamera
    let availability: StoryCamera.Availability
    /// A photo is being taken or loaded.
    let isBusy: Bool
    let shape: RoundedRectangle
    let onCapture: () -> Void

    @Environment(\.openURL) private var openURL

    /// Behind the small controls on the camera and the photo, so they read on any picture.
    static var controlBackdrop: Color { .black.opacity(0.4) }

    var body: some View {
        ZStack {
            Color.black
            switch availability {
            case .ready:
                StoryCameraPreview(session: camera.session)
                    .accessibilityHidden(true)
            case .denied:
                message(.storiesComposerCameraDenied, showsSettings: true)
            case .unavailable:
                message(.storiesComposerCameraUnavailable, showsSettings: false)
            case .unknown:
                ProgressView().tint(.white)
            }
            if isBusy {
                Self.controlBackdrop
            }
        }
        .clipShape(shape)
        .overlay(alignment: .bottom) {
            if availability == .ready {
                shutterRow
            }
        }
    }

    private var shutterRow: some View {
        StoryShutterButton(isBusy: isBusy, action: onCapture)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button {
                    camera.flip()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                        .background(Self.controlBackdrop, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.storiesComposerFlipCamera))
                .padding(.trailing, PaeoniaSpacing.space24)
            }
            .padding(.bottom, PaeoniaSpacing.space24)
    }

    private func message(_ text: LocalizedStringResource, showsSettings: Bool) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "camera")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(text)
                .font(PaeoniaTypography.body)
                .multilineTextAlignment(.center)
            if showsSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text(.commonOpenSettings)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
            }
        }
        .foregroundStyle(.paeoniaTextSecondary)
        .padding(PaeoniaSpacing.space24)
    }
}
