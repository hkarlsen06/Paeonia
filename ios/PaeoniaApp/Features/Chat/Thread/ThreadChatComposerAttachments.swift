import Observation
import PhotosUI
import SwiftUI

/// The photos picked for the next chat message, ported from Tidex's composer. Up to
/// four per message. Each is compressed when it's picked, off the main actor, with
/// the same compressor as memory photos, so sending never waits on it.
@MainActor
@Observable
final class ThreadChatPhotoStaging {
    static let maximumPhotos = 4

    struct Staged: Identifiable, Equatable {
        let id: UUID
        /// The library pick it came from. Nil for a camera shot.
        let pickerItemID: String?
        var photo: ThreadChatPhoto
    }

    private(set) var staged: [Staged] = [] {
        didSet { persistDraft() }
    }
    private var caption = ""
    /// Staging owns this callback so a pick finishing after the view disappears is still saved.
    @ObservationIgnored var onDraftChange: ((ThreadChatPhotoDraft) -> Void)?
    /// While true, the field and send button wait, so a half-loaded pick can't send.
    private(set) var isProcessing = false
    var pickerItems: [PhotosPickerItem] = [] {
        didSet { syncPicker(oldValue: oldValue) }
    }
    var isDrawerOpen = false
    var isShowingLibrary = false
    var isShowingCamera = false

    var photos: [ThreadChatPhoto] {
        staged.map(\.photo)
    }

    /// The library may hold this many, after camera shots already staged.
    var librarySelectionLimit: Int {
        max(1, Self.maximumPhotos - staged.count(where: { $0.pickerItemID == nil }))
    }

    var canAddPhotos: Bool {
        staged.count < Self.maximumPhotos
    }

    func addCameraPhoto(_ data: Data) {
        guard canAddPhotos else { return }
        isProcessing = true
        Task {
            if let photo = await Self.compress(data) {
                staged.append(Staged(id: UUID(), pickerItemID: nil, photo: photo))
            }
            isProcessing = false
        }
    }

    func remove(_ id: UUID) {
        guard let removed = staged.first(where: { $0.id == id }) else { return }
        staged.removeAll { $0.id == id }
        // Clears the photo's check mark in the picker too.
        if let pickerItemID = removed.pickerItemID {
            pickerItems.removeAll { $0.itemIdentifier == pickerItemID }
        }
    }

    func setDescription(_ text: String, for id: UUID) {
        guard let index = staged.firstIndex(where: { $0.id == id }) else { return }
        staged[index].photo.accessibilityText = text
    }

    func updateCaption(_ caption: String) {
        self.caption = caption
        persistDraft()
    }

    func restore(_ draft: ThreadChatPhotoDraft) {
        caption = draft.caption
        // Compressed local copies are independent of a later photo-library selection.
        staged = draft.photos.map { Staged(id: UUID(), pickerItemID: nil, photo: $0) }
    }

    func removeSent(_ sent: [Staged]) {
        for item in sent where staged.contains(item) {
            remove(item.id)
        }
        if staged.isEmpty { isDrawerOpen = false }
    }

    private func persistDraft() {
        onDraftChange?(ThreadChatPhotoDraft(photos: photos, caption: caption))
    }

    /// Mirrors the picker's selection: new picks are loaded and staged, picks taken
    /// away are unstaged.
    private func syncPicker(oldValue: [PhotosPickerItem]) {
        let selectedIDs = Set(pickerItems.compactMap(\.itemIdentifier))
        staged.removeAll { item in
            guard let pickerItemID = item.pickerItemID else { return false }
            return !selectedIDs.contains(pickerItemID)
        }
        let stagedIDs = Set(staged.compactMap(\.pickerItemID))
        let added = pickerItems.filter { item in
            guard let id = item.itemIdentifier else { return false }
            return !stagedIDs.contains(id)
        }
        guard !added.isEmpty else { return }
        isProcessing = true
        Task {
            for item in added where canAddPhotos {
                guard let id = item.itemIdentifier,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let photo = await Self.compress(data),
                      // The pick may have been taken away while it loaded.
                      pickerItems.contains(where: { $0.itemIdentifier == id })
                else { continue }
                staged.append(Staged(id: UUID(), pickerItemID: id, photo: photo))
            }
            isProcessing = false
        }
    }

    @concurrent
    private nonisolated static func compress(_ data: Data) async -> ThreadChatPhoto? {
        ImageCompressor.compress(data).map {
            ThreadChatPhoto(data: $0.data, width: $0.width, height: $0.height)
        }
    }
}

/// The drawer under the field: a strip of recent photos to tap, and buttons for the
/// whole library and the camera. Like Tidex's attachment drawer.
struct ThreadChatAttachmentDrawer: View {
    @Bindable var staging: ThreadChatPhotoStaging

    private static let pickerHeight: CGFloat = 168

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            PhotosPicker(
                selection: $staging.pickerItems,
                maxSelectionCount: staging.librarySelectionLimit,
                selectionBehavior: .continuous,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text(.dailyChatComposerLibrary)
            }
            .photosPickerStyle(.compact)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden)
            .frame(height: Self.pickerHeight)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))

            HStack(spacing: PaeoniaSpacing.space8) {
                tile(systemImage: "photo.on.rectangle", title: .dailyChatComposerLibrary) {
                    staging.isShowingLibrary = true
                }
                tile(systemImage: "camera", title: .dailyChatComposerCamera) {
                    staging.isShowingCamera = true
                }
                .disabled(!staging.canAddPhotos)
            }
        }
        .padding(PaeoniaSpacing.space8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
    }

    private func tile(
        systemImage: String,
        title: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Color.paeoniaTextPrimary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The picked photos above the field, each with a button to take it away.
struct ThreadChatStagedPhotosRow: View {
    let staging: ThreadChatPhotoStaging

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            ForEach(staging.staged) { item in
                HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
                    thumbnail(item, side: 64)
                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                        Text(.mediaAccessibilityPhotoDescription).font(PaeoniaTypography.caption)
                        TextField(String(localized: .mediaAccessibilityPhotoHint), text: Binding(
                            get: { staging.staged.first(where: { $0.id == item.id })?.photo.accessibilityText ?? "" },
                            set: { staging.setDescription($0, for: item.id) }
                        ), axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        if DailyAnswerDraft.measuredLength(of: item.photo.accessibilityText ?? "") > 10_000 {
                            Text(.mediaAccessibilityTooLong).foregroundStyle(.paeoniaErrorText)
                        }
                    }
                }
            }
            if staging.isProcessing { ProgressView() }
        }
    }

    private func thumbnail(_ item: ThreadChatPhotoStaging.Staged, side: CGFloat) -> some View {
        ThreadChatPhotoCard(
            photo: item.photo,
            size: CGSize(width: side, height: side),
            shape: UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: PaeoniaRadius.radius16, bottomLeading: PaeoniaRadius.radius16,
                bottomTrailing: PaeoniaRadius.radius16, topTrailing: PaeoniaRadius.radius16
            ), style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                staging.remove(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.46), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                    // The circle stays small. The tap area is 44pt.
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(Text(.dailyChatComposerRemovePhoto))
        }
    }
}
