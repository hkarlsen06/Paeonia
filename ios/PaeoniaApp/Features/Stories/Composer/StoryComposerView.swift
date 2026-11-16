import PhotosUI
import SwiftUI

/// Shares a photo or a short video, with an optional caption, as a story. It opens
/// straight into the camera: a live viewfinder with the round shutter button, and
/// "Choose a photo or video" under it. A tap takes a photo and a hold records a video.
/// A taken or picked photo or video replaces the viewfinder, with a caption field below.
/// The first time, it explains that a story shows on Home for a day and then stays in
/// Memories. A failed post keeps the media and caption here, and the error shows in the banner.
struct StoryComposerView: View {
    let viewModel: StoriesViewModel
    let partnerName: String

    @State private var model = StoryComposerModel()
    @State private var caption = ""
    @State private var accessibilityText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsExplainer = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        NavigationStack {
            form
                .paeoniaScreenBackground()
                .keyboardDismissable()
                .navigationTitle(Text(.storiesComposerTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text(.commonCancel)
                        }
                        .accessibilityIdentifier("story.composer.cancel")
                        .disabled(viewModel.isPosting)
                    }
                }
                .paeoniaBottomBar {
                    if model.media != nil {
                        shareButton
                    }
                }
        }
        // The sheet covers the app's banner, so show it here too.
        .paeoniaBanner(bannerCenter)
        .presentationBackground(.paeoniaBackgroundPrimary)
        // A photo, a video, a recording or a running post can't be swiped away by accident.
        // Cancel still closes.
        .interactiveDismissDisabled(viewModel.isPosting || model.holdsMedia)
        .task {
            model.onMessage = { bannerCenter.show($0) }
            await model.open()
            model.updateCamera(isAppActive: scenePhase == .active)
        }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in model.updateCamera(isAppActive: phase == .active) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            model.loadPicked(item)
        }
        .onAppear { showsExplainer = !viewModel.hasPostedBefore }
    }

    /// The viewfinder or photo takes the room the rest leaves, so it shrinks to make
    /// space when the keyboard opens for the caption.
    private var form: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            mediaArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.media == nil {
                choosePhotoButton
            } else {
                captionField
                PhotoDescriptionField(text: $accessibilityText)
                    .disabled(viewModel.isPosting)
                if showsExplainer {
                    Text(.storiesComposerExplainer(partnerName))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
        .padding(.bottom, PaeoniaSpacing.space16)
        .paeoniaReadableWidth()
    }

    // MARK: - Viewfinder, photo and video

    private var mediaShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
    }

    @ViewBuilder
    private var mediaArea: some View {
        switch model.media {
        case let .photo(_, preview):
            Color.clear
                .overlay {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .accessibilityLabel(Text(.storiesComposerPhotoAccessibility))
                }
                .clipShape(mediaShape)
                .overlay(alignment: .topTrailing) { removeButton(label: .storiesComposerRemovePhoto) }
        case let .video(video):
            StoryPlayerLayerView(player: model.previewPlayer.player, videoGravity: .resizeAspectFill)
                .background(.black)
                .clipShape(mediaShape)
                .overlay(alignment: .bottomLeading) {
                    VideoBadge(durationMs: video.durationMs)
                        .padding(PaeoniaSpacing.space12)
                        .accessibilityHidden(true)
                }
                .accessibilityElement()
                .accessibilityLabel(Text(.storiesComposerVideoAccessibility))
                .accessibilityValue(Text(verbatim: VideoBadge.accessibilityLabel(durationMs: video.durationMs)))
                .overlay(alignment: .topTrailing) { removeButton(label: .storiesComposerRemoveVideo) }
        case nil:
            StoryViewfinder(model: model, shape: mediaShape)
        }
    }

    private func removeButton(label: LocalizedStringResource) -> some View {
        Button {
            model.removeMedia()
            accessibilityText = ""
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .background(StoryViewfinder.controlBackdrop, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(PaeoniaSpacing.space12)
        .accessibilityLabel(Text(label))
        .disabled(viewModel.isPosting)
    }

    private var choosePhotoButton: some View {
        // The default encoding, so Photos renders a slow-motion video's slow parts. Its
        // original file plays at normal speed.
        PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
            Label {
                Text(.storiesComposerChoosePhoto)
            } icon: {
                Image(systemName: "photo.on.rectangle").accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .disabled(model.shutter != .idle || model.isPreparing || model.failedRecording != nil)
    }

    // MARK: - Caption and share

    private var captionField: some View {
        TextField(text: $caption, prompt: Text(.storiesComposerCaptionPlaceholder), axis: .vertical) {
            Text(.storiesComposerCaptionPlaceholder)
        }
        .lineLimit(1...3)
        .font(PaeoniaTypography.body)
        .padding(PaeoniaSpacing.space16)
        .background(
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
        )
        .onChange(of: caption) { _, text in
            if text.count > Story.maxCaptionLength {
                caption = String(text.prefix(Story.maxCaptionLength))
            }
        }
        .disabled(viewModel.isPosting)
    }

    private var shareButton: some View {
        Button {
            Task { await post() }
        } label: {
            Text(.storiesComposerShare(partnerName))
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isPosting))
        .disabled(accessibilityText.unicodeScalars.count > 10_000)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space8)
        .paeoniaReadableWidth()
    }

    // MARK: - Actions

    private func post() async {
        guard let media = model.postMedia else { return }
        if await viewModel.post(media, caption: caption, accessibilityText: accessibilityText) {
            PaeoniaHaptics.storyShared()
            dismiss()
        }
    }
}
