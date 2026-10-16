import PhotosUI
import SwiftUI

/// Shares a photo, with an optional caption, as a story. The first time, it explains
/// that a story shows on Home for a day and then stays in Memories. A failed post keeps
/// the photo and caption here, and the error shows in the banner.
struct StoryComposerView: View {
    let viewModel: StoriesViewModel
    let partnerName: String

    @State private var photo: Data?
    @State private var preview: UIImage?
    @State private var caption = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isLoadingPhoto = false
    @State private var showsExplainer = false
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private static let previewHeight: CGFloat = 420

    var body: some View {
        NavigationStack {
            form
                .paeoniaScreenBackground()
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
                    Button {
                        Task { await post() }
                    } label: {
                        Text(.storiesComposerShare(partnerName))
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isPosting))
                    .disabled(photo == nil)
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                    .padding(.bottom, PaeoniaSpacing.space8)
                    .paeoniaReadableWidth()
                }
        }
        // The sheet covers the app's top banner, so show it here too.
        .paeoniaTopBanner(bannerCenter)
        .presentationBackground(.paeoniaBackgroundPrimary)
        // A picked photo or a running post can't be swiped away by accident. Cancel still closes.
        .interactiveDismissDisabled(viewModel.isPosting || photo != nil)
        .fullScreenCover(isPresented: $isCameraPresented) {
            DailyCameraPicker { data in setPhoto(data) }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in loadPicked(item) }
        .onAppear { showsExplainer = !viewModel.hasPostedBefore }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                photoArea
                captionField
                if showsExplainer {
                    Text(.storiesComposerExplainer(partnerName))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space24)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var photoArea: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        if let preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: Self.previewHeight)
                .clipShape(shape)
                .overlay(alignment: .topTrailing) {
                    Button {
                        photo = nil
                        self.preview = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .padding(PaeoniaSpacing.space8)
                    }
                    .accessibilityLabel(Text(.storiesComposerRemovePhoto))
                    .disabled(viewModel.isPosting)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(.storiesComposerPhotoAccessibility))
        } else {
            VStack(spacing: PaeoniaSpacing.space12) {
                if isLoadingPhoto {
                    ProgressView()
                } else {
                    Image(systemName: "camera.on.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label {
                            Text(.storiesComposerChoosePhoto)
                        } icon: {
                            Image(systemName: "photo.on.rectangle").accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(PaeoniaQuietButtonStyle())
                    if DailyCameraPicker.isAvailable {
                        Button {
                            isCameraPresented = true
                        } label: {
                            Label {
                                Text(.storiesComposerTakePhoto)
                            } icon: {
                                Image(systemName: "camera").accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(PaeoniaQuietButtonStyle())
                    }
                }
            }
            .padding(PaeoniaSpacing.space24)
            .frame(maxWidth: .infinity)
            .frame(height: Self.previewHeight)
            .background(shape.fill(.paeoniaSurfaceSecondary))
        }
    }

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
        photo = data
        Task {
            preview = await MemoryImageDecoding.downsample(data, maxPixelSize: 1_200)
            if preview == nil {
                photo = nil
                bannerCenter.show(.error(message: String(localized: .storiesErrorPhotoUnreadable)))
            }
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
