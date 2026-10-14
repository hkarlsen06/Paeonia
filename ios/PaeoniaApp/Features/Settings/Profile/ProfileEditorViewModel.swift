import Observation
import UIKit

/// The name and photo editor's state and async work.
///
/// The Us tab owns one instance, so a save keeps running and keeps showing its
/// progress if the user leaves the profile screen and comes back.
@MainActor
@Observable
final class ProfileEditorViewModel {
    enum Event: Equatable {
        case saved
        case saveFailed
        case photoLoadFailed
    }

    /// The image waiting in the crop sheet. A new identity per pick, so the sheet
    /// presents once per photo.
    struct CropRequest: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private(set) var savedName = ""
    private(set) var customPhotoAssetID: UUID?
    private(set) var providerPhotoAssetID: UUID?

    private(set) var typedName: String?
    private(set) var stagedPhotoData: Data?
    private(set) var stagedImage: UIImage?
    private(set) var removesExistingPhoto = false
    private(set) var isLoadingPhoto = false
    private(set) var isSaving = false
    var cropRequest: CropRequest?
    private(set) var event: Event?
    /// Counts successful saves, so the view can play one success haptic per save.
    private(set) var completedSaveCount = 0

    @ObservationIgnored private var photoLoadTask: Task<Void, Never>?
    @ObservationIgnored private var photoLoadGeneration = 0
    /// Turns the cropped photo into upload bytes. Tests replace it to hold the
    /// encode open and check what happens around it.
    @ObservationIgnored private let encodePhoto: (UIImage) async -> Data?

    init(encodePhoto: @escaping (UIImage) async -> Data? = ProfileEditorViewModel.encodeJPEG) {
        self.encodePhoto = encodePhoto
    }

    var draft: ProfileEditorDraft {
        ProfileEditorDraft(
            savedName: savedName,
            customPhotoAssetID: customPhotoAssetID,
            providerPhotoAssetID: providerPhotoAssetID,
            typedName: typedName,
            stagedPhotoData: stagedPhotoData,
            removesExistingPhoto: removesExistingPhoto
        )
    }

    /// Edits stay until the user saves or cancels, so leaving the screen with
    /// them would throw away work without asking.
    var hasUnsavedWork: Bool {
        draft.hasChanges || isSaving || isLoadingPhoto
    }

    var canSave: Bool {
        draft.canSave && !isSaving && !isLoadingPhoto
    }

    /// The saved profile can refresh while the screen is open, for example after
    /// another device renames the user.
    func updateSavedProfile(name: String?, customPhotoAssetID: UUID?, providerPhotoAssetID: UUID?) {
        savedName = name?.trimmedNonEmpty ?? ""
        self.customPhotoAssetID = customPhotoAssetID
        self.providerPhotoAssetID = providerPhotoAssetID
    }

    func setName(_ name: String) {
        guard !isSaving else {
            return
        }
        typedName = name
    }

    /// Loads a picked photo for cropping. A newer pick replaces an older one that
    /// is still loading, so a slow first photo can never open over the second.
    func pickPhoto(load: @escaping () async throws -> Data?) {
        guard !isSaving else {
            return
        }

        photoLoadTask?.cancel()
        photoLoadGeneration += 1
        let generation = photoLoadGeneration
        isLoadingPhoto = true

        photoLoadTask = Task {
            let image = await Self.decodedImage(from: load)
            guard generation == photoLoadGeneration, !Task.isCancelled else {
                return
            }

            isLoadingPhoto = false
            if let image {
                cropRequest = CropRequest(image: image)
            } else {
                event = .photoLoadFailed
            }
        }
    }

    /// Encoding counts as loading, so Save waits for it. A discard or a newer pick
    /// during the encode wins, and the encoded photo is dropped.
    func applyCroppedPhoto(_ image: UIImage) async {
        cropRequest = nil
        photoLoadGeneration += 1
        let generation = photoLoadGeneration
        isLoadingPhoto = true

        let data = await encodePhoto(image)

        guard generation == photoLoadGeneration else {
            return
        }
        isLoadingPhoto = false

        guard let data else {
            event = .photoLoadFailed
            return
        }

        stagedImage = image
        stagedPhotoData = data
        removesExistingPhoto = false
    }

    func cancelCrop() {
        cropRequest = nil
    }

    /// The first tap drops a photo that is only staged. The saved photo goes only
    /// when nothing is staged, so one tap never removes more than the user sees.
    func removePhoto() {
        guard !isSaving else {
            return
        }

        if stagedPhotoData != nil {
            stagedImage = nil
            stagedPhotoData = nil
        } else if customPhotoAssetID != nil {
            removesExistingPhoto = true
        }
    }

    /// Drops every unsaved edit, including a photo still loading.
    func discard() {
        guard !isSaving else {
            return
        }

        photoLoadTask?.cancel()
        photoLoadGeneration += 1
        isLoadingPhoto = false
        cropRequest = nil
        clearEdits()
    }

    func save(using onSave: @MainActor (String, AuthProfilePhotoUpdate) async -> Bool) async {
        let draft = draft
        guard canSave, let validatedName = draft.validatedName else {
            return
        }

        isSaving = true
        let succeeded = await onSave(validatedName, draft.photoUpdate)
        isSaving = false

        if succeeded {
            // Editing is locked while saving, so the edits still match what was
            // sent and can all go.
            clearEdits()
            completedSaveCount += 1
            event = .saved
        } else {
            // Keep the edits so the user can try again.
            event = .saveFailed
        }
    }

    func consumeEvent() {
        event = nil
    }

    private func clearEdits() {
        typedName = nil
        stagedImage = nil
        stagedPhotoData = nil
        removesExistingPhoto = false
    }

    nonisolated static func encodeJPEG(_ image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: 0.9)
        }.value
    }

    private static func decodedImage(from load: () async throws -> Data?) async -> UIImage? {
        guard let data = try? await load() else {
            return nil
        }
        // Decoding a full-size photo is slow, so keep it off the main thread.
        return await Task.detached(priority: .userInitiated) {
            cropReadyImage(from: data)
        }.value
    }

    /// A profile photo ends up small, so a 48-megapixel original only costs
    /// memory in the crop sheet. Scale anything larger than the limit down first.
    nonisolated private static func cropReadyImage(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let longestSide = max(image.size.width, image.size.height)
        let limit: CGFloat = 2_048
        guard longestSide > limit else {
            return image
        }

        let factor = limit / longestSide
        let targetSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        return image.preparingThumbnail(of: targetSize) ?? image
    }
}
