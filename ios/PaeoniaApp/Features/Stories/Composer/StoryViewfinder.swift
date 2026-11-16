import SwiftUI

/// The live camera in the story composer, with the round shutter button at the bottom
/// center and the switch-camera button beside it. Without camera access it says why
/// and offers Settings. A recording that could not be made ready offers Try again and Delete.
struct StoryViewfinder: View {
    let model: StoryComposerModel
    let shape: RoundedRectangle

    @Environment(\.openURL) private var openURL

    /// Behind the small controls on the camera and the photo, so they read on any picture.
    static var controlBackdrop: Color { .black.opacity(0.4) }

    var body: some View {
        ZStack {
            Color.black
            switch model.availability {
            case .ready:
                StoryCameraPreview(camera: model.camera)
                    .accessibilityHidden(true)
            case .denied:
                message(.storiesComposerCameraDenied, showsSettings: true)
            case .unavailable:
                message(.storiesComposerCameraUnavailable, showsSettings: false)
            case .unknown:
                ProgressView().tint(.white)
            }
            if model.isDimmed {
                Self.controlBackdrop
            }
            if model.isPreparing {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel(Text(.storiesComposerPreparing))
            }
            if model.failedRecording != nil {
                failedRecording
            }
        }
        .clipShape(shape)
        .overlay(alignment: .bottom) {
            if model.availability == .ready, model.failedRecording == nil {
                shutterRow
            }
        }
        .onChange(of: model.failedRecording != nil) { _, failed in
            if failed {
                AccessibilityNotification.Announcement(String(localized: .storiesComposerRecordingNotReady)).post()
            }
        }
    }

    private var failedRecording: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "video.badge.exclamationmark")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(.storiesComposerRecordingNotReady)
                .font(PaeoniaTypography.body)
                .multilineTextAlignment(.center)
            Button {
                model.retryFailedRecording()
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            Button(role: .destructive) {
                model.deleteFailedRecording()
            } label: {
                Text(.storiesComposerDeleteRecording)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
        }
        .foregroundStyle(.white)
        .padding(PaeoniaSpacing.space24)
    }

    private var shutterRow: some View {
        StoryShutterButton(
            shutter: model.shutter,
            isDisabled: model.isPreparing,
            onPressBegan: model.pressBegan,
            onPressEnded: model.pressEnded,
            onTakePhoto: { Task { await model.takePhoto() } },
            onRecord: { Task { await model.recordVideo() } },
            onStopRecording: model.stopRecording
        )
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button {
                model.camera.flip()
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
            .disabled(model.shutter != .idle || model.isPreparing)
            .opacity(model.isRecording ? 0 : 1)
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
