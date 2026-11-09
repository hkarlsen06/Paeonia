import PhotosUI
import SwiftUI
import UIKit

/// The photos part of the memory form: photos already on the memory, photos picked
/// for this save, placeholders while picked photos load, and the library and camera
/// buttons. Each partner can add up to five photos to a memory.
struct MemoryEditorPhotosField: View {
    @Binding var photos: [MemoryDraftPhoto]
    @Binding var existingDescriptions: [UUID: String]
    @Binding var removedExistingMediaIDs: Set<UUID>
    /// Picked photos still loading from the library. The form can't save until they're in.
    @Binding var loadingPhotoCount: Int
    let existingMedia: [MemoryMediaSnapshot]
    let currentUserID: UUID?
    let allowsPhotos: Bool
    let isSaving: Bool

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    static let maxPhotosPerPartner = 5
    private let thumbnailSize: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if !visibleExistingMedia.isEmpty || !photos.isEmpty || loadingPhotoCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PaeoniaSpacing.space8) {
                        ForEach(visibleExistingMedia, id: \.memoryMediaID) { media in
                            existingPhotoEditor(media)
                        }
                        ForEach(photos) { photo in
                            stagedPhotoEditor(photo)
                        }
                        ForEach(0..<loadingPhotoCount, id: \.self) { _ in
                            loadingThumbnail
                        }
                    }
                }
            }

            if allowsPhotos, remainingPhotoSlots > 0 {
                pickerControls
            }
        }
        .onChange(of: pickerItems) { _, items in
            loadPickedPhotos(items)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            DailyCameraPicker(onCapture: appendCapturedPhoto)
                .ignoresSafeArea()
        }
        .paeoniaImageViewer(selection: $imageViewerSelection)
    }

    private func existingPhotoEditor(_ media: MemoryMediaSnapshot) -> some View {
        VStack {
            existingThumbnail(media)
            if media.ownerUserID == currentUserID {
                PhotoDescriptionField(text: Binding(
                    get: {
                        existingDescriptions[media.mediaAssetID] ?? media.accessibilityText ?? ""
                    },
                    set: { existingDescriptions[media.mediaAssetID] = $0 }
                ))
                .frame(width: 200)
                .disabled(isSaving)
            }
        }
    }

    private func stagedPhotoEditor(_ photo: MemoryDraftPhoto) -> some View {
        VStack {
            stagedThumbnail(photo)
            PhotoDescriptionField(text: Binding(
                get: { photos.first { $0.id == photo.id }?.accessibilityText ?? "" },
                set: { value in
                    if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                        photos[index].accessibilityText = value
                    }
                }
            ))
            .frame(width: 200)
            .disabled(isSaving)
        }
    }

    private func existingThumbnail(_ media: MemoryMediaSnapshot) -> some View {
        ZStack(alignment: .topTrailing) {
            MemoryMediaImageView(
                mediaAssetID: media.mediaAssetID,
                accessibilityText: media.accessibilityText,
                height: thumbnailSize,
                cornerRadius: PaeoniaRadius.radius12
            )
            .frame(width: thumbnailSize)

            if media.ownerUserID == currentUserID {
                removeButton {
                    animateStrip { _ = removedExistingMediaIDs.insert(media.memoryMediaID) }
                }
            }
        }
    }

    private func stagedThumbnail(_ photo: MemoryDraftPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            MemoryStagedPhotoThumbnail(photo: photo, size: thumbnailSize, cornerRadius: PaeoniaRadius.radius12)
                .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
                .onTapGesture {
                    presentStagedImage(photo.data)
                }
                .accessibilityLabel(Text(verbatim: PhotoDescription.label(photo.accessibilityText)))
                .accessibilityAddTraits(.isButton)

            removeButton {
                animateStrip { photos.removeAll { $0.id == photo.id } }
            }
        }
    }

    private var loadingThumbnail: some View {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            .fill(.paeoniaSurfaceSecondary)
            .frame(width: thumbnailSize, height: thumbnailSize)
            .overlay { ProgressView() }
            .accessibilityHidden(true)
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.space4)
        .accessibilityLabel(Text(.memoriesPhotoRemove))
        .disabled(isSaving)
    }

    private var pickerControls: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: max(1, remainingPhotoSlots),
                matching: .images
            ) {
                Label {
                    Text(.memoriesEditorAddPhoto)
                } icon: {
                    Image(systemName: "photo.on.rectangle").accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)

            if DailyCameraPicker.isAvailable {
                Button {
                    isCameraPresented = true
                } label: {
                    Label {
                        Text(.memoriesEditorTakePhoto)
                    } icon: {
                        Image(systemName: "camera").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(isSaving)
    }

    private var visibleExistingMedia: [MemoryMediaSnapshot] {
        existingMedia.filter { !removedExistingMediaIDs.contains($0.memoryMediaID) }
    }

    private var remainingPhotoSlots: Int {
        let ownVisible = visibleExistingMedia.filter { $0.ownerUserID == currentUserID }.count
        return max(0, Self.maxPhotosPerPartner - ownVisible - photos.count - loadingPhotoCount)
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let picked = Array(items.prefix(remainingPhotoSlots))
        pickerItems = []
        animateStrip { loadingPhotoCount += picked.count }
        Task {
            var loaded: [Data] = []
            for item in picked {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append(data)
                }
            }
            // One append, so a saved draft writes its photo files once.
            animateStrip {
                loadingPhotoCount -= picked.count
                photos.append(contentsOf: loaded.map { MemoryDraftPhoto(data: $0) })
            }
            if loaded.count < picked.count {
                bannerCenter.show(.error(message: String(localized: .memoriesEditorPhotoLoadFailed)))
            }
        }
    }

    private func appendCapturedPhoto(_ data: Data) {
        guard allowsPhotos, remainingPhotoSlots > 0 else { return }
        animateStrip { photos.append(MemoryDraftPhoto(data: data)) }
    }

    /// Tiles fade in and out and the strip and the fields below glide to their new
    /// place. The animation wraps the write, so it reaches the form outside this view.
    private func animateStrip(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange, change)
    }

    private func presentStagedImage(_ data: Data) {
        guard let uiImage = UIImage(data: data) else { return }
        imageViewerSelection = PaeoniaImageViewerSelection(image: uiImage)
    }
}
