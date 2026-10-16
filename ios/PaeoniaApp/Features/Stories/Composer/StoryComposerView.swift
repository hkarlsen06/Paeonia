import PhotosUI
import SwiftUI

/// Shares a photo, with an optional caption, as a story. It opens straight into the
/// camera: a live viewfinder with the round shutter button, and "Choose a photo" under
/// it. A taken or picked photo replaces the viewfinder, with a caption field below. The
/// first time, it explains that a story shows on Home for a day and then stays in
/// Memories. A failed post keeps the photo and caption here, and the error shows in the banner.
struct StoryComposerView: View {
    let viewModel: StoriesViewModel
    let partnerName: String

    @State private var camera = StoryCamera()
    @State private var cameraAvailability: StoryCamera.Availability = .unknown
    @State private var isCapturing = false
    @State private var photo: Data?
    @State private var preview: UIImage?
    @State private var caption = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
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
                        .disabled(viewModel.isPosting)
                    }
                }
                .paeoniaBottomBar {
                    if photo != nil {
                        shareButton
                    }
                }
        }
        // The sheet covers the app's top banner, so show it here too.
        .paeoniaTopBanner(bannerCenter)
        .presentationBackground(.paeoniaBackgroundPrimary)
        // A picked photo or a running post can't be swiped away by accident. Cancel still closes.
        .interactiveDismissDisabled(viewModel.isPosting || photo != nil)
        .task {
            cameraAvailability = await camera.prepare()
            updateCamera()
        }
        .onDisappear { camera.stop() }
        .onChange(of: photo == nil) { _, _ in updateCamera() }
        .onChange(of: scenePhase) { _, _ in updateCamera() }
        .onChange(of: pickerItem) { _, item in loadPicked(item) }
        .onAppear { showsExplainer = !viewModel.hasPostedBefore }
    }

    /// The viewfinder or photo takes the room the rest leaves, so it shrinks to make
    /// space when the keyboard opens for the caption.
    private var form: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            mediaArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if photo == nil {
                choosePhotoButton
            } else {
                captionField
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

    // MARK: - Viewfinder and photo

    private var mediaShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
    }

    @ViewBuilder
    private var mediaArea: some View {
        if let preview {
            Color.clear
                .overlay {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .accessibilityLabel(Text(.storiesComposerPhotoAccessibility))
                }
                .clipShape(mediaShape)
                .overlay(alignment: .topTrailing) { retakeButton }
        } else {
            StoryViewfinder(
                camera: camera,
                availability: cameraAvailability,
                isBusy: isCapturing || isLoadingPhoto,
                shape: mediaShape
            ) {
                Task { await capture() }
            }
        }
    }

    private var retakeButton: some View {
        Button {
            photo = nil
            preview = nil
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .background(StoryViewfinder.controlBackdrop, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(PaeoniaSpacing.space12)
        .accessibilityLabel(Text(.storiesComposerRemovePhoto))
        .disabled(viewModel.isPosting)
    }

    private var choosePhotoButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label {
                Text(.storiesComposerChoosePhoto)
            } icon: {
                Image(systemName: "photo.on.rectangle").accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .disabled(isCapturing || isLoadingPhoto)
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
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space8)
        .paeoniaReadableWidth()
    }

    // MARK: - Actions

    /// The camera runs only while the viewfinder shows and the app is in front.
    private func updateCamera() {
        if photo == nil, cameraAvailability == .ready, scenePhase == .active {
            camera.start()
        } else {
            camera.stop()
        }
    }

    private func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        if let data = await camera.capture() {
            PaeoniaHaptics.selection()
            setPhoto(data)
        } else {
            bannerCenter.show(.error(message: String(localized: .storiesErrorPhotoUnreadable)))
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        pickerItem = nil
        isLoadingPhoto = true
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            isLoadingPhoto = false
            if let data {
                setPhoto(data)
            } else {
                bannerCenter.show(.error(message: String(localized: .storiesErrorPhotoUnreadable)))
            }
        }
    }

    private func setPhoto(_ data: Data) {
        Task {
            let image = await MemoryImageDecoding.downsample(data, maxPixelSize: StoryPhotoView.maxPixelSize)
            guard let image else {
                bannerCenter.show(.error(message: String(localized: .storiesErrorPhotoUnreadable)))
                return
            }
            preview = image
            photo = data
        }
    }

    private func post() async {
        guard let photo else { return }
        if await viewModel.post(photo: photo, caption: caption) {
            PaeoniaHaptics.storyShared()
            dismiss()
        }
    }
}
