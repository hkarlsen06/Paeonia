import PhotosUI
import SwiftUI
import UIKit

/// Edits the paired user's canonical profile. Provider artwork never appears
/// here as a URL; the view renders either a custom private asset, the imported
/// private provider fallback, a newly cropped local image, or initials.
struct PairedProfileEditorView: View {
    private let originalDisplayName: String
    private let originalCustomProfilePhotoAssetID: UUID?
    private let providerProfilePhotoAssetID: UUID?
    private let authProvider: AuthProvider?
    private let onSave: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var displayName: String
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var cropDraft: PairedProfileCropDraft?
    @State private var removesExistingPhoto = false
    @State private var isSaving = false
    @State private var isResettingPicker = false

    init(
        displayName: String,
        customProfilePhotoAssetID: UUID?,
        providerProfilePhotoAssetID: UUID?,
        authProvider: AuthProvider? = nil,
        onSave: @escaping @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool
    ) {
        originalDisplayName = displayName
        originalCustomProfilePhotoAssetID = customProfilePhotoAssetID
        self.providerProfilePhotoAssetID = providerProfilePhotoAssetID
        self.authProvider = authProvider
        self.onSave = onSave
        _displayName = State(initialValue: displayName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                profileRow

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                    Text(.settingsProfilePhotoMessage)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let authProviderName {
                        Text(.settingsProfileSignedInWith(authProviderName))
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextTertiary)
                    }
                }

                saveButton
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.settingsProfileEditorTitle))
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissable()
        .onChange(of: selectedItem) { _, item in
            loadPhoto(from: item)
        }
        .sheet(item: $cropDraft) { draft in
            PaeoniaProfileImageCropSheet(
                image: draft.image,
                onCrop: applyCroppedPhoto,
                onCancel: cancelCrop
            )
            .ignoresSafeArea()
        }
    }
}

extension PairedProfileEditorView {
    /// One compact composition instead of stacked cards: the avatar sits to the
    /// left of the name field with its two photo actions as small icon buttons
    /// directly beneath it, so the whole identity reads as a single block.
    private var profileRow: some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space16) {
            VStack(spacing: PaeoniaSpacing.space8) {
                profilePreview

                HStack(spacing: PaeoniaSpacing.space8) {
                    changePhotoButton

                    if hasRemovablePhoto {
                        removePhotoButton
                    }
                }
            }

            nameField
        }
    }

    private var changePhotoButton: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            iconCircle(systemName: hasVisiblePhoto ? "photo.badge.arrow.down" : "photo.badge.plus")
        }
        .disabled(isSaving)
        .accessibilityLabel(
            Text(hasVisiblePhoto ? .settingsProfilePhotoChange : .settingsProfilePhotoAdd)
        )
    }

    private var removePhotoButton: some View {
        Button(action: removePhoto) {
            iconCircle(systemName: "trash", tint: .paeoniaError)
        }
        .disabled(isSaving)
        .accessibilityLabel(Text(.settingsProfilePhotoRemove))
    }

    private func iconCircle(systemName: String, tint: Color = .paeoniaAccentPrimary) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(
                width: PaeoniaSpacing.compactButtonHeight,
                height: PaeoniaSpacing.compactButtonHeight
            )
            .background(.paeoniaSurfaceSecondary, in: Circle())
            .contentShape(Circle())
    }

    @ViewBuilder
    private var profilePreview: some View {
        if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFill()
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .clipShape(Circle())
                .overlay {
                    // Same subtle accent ring as the onboarding photo preview.
                    Circle()
                        .stroke(.paeoniaAccentPrimary.opacity(0.25), lineWidth: 1)
                }
                .accessibilityLabel(Text(.settingsProfilePhotoPreviewAccessibilityLabel))
        } else {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: previewProfilePhotoAssetID,
                name: validatedDisplayName ?? displayName,
                tint: .paeoniaAccentPrimary,
                size: Self.avatarSize
            )
        }
    }

    /// Sized so the avatar plus its two 44-point icon buttons form a column that
    /// balances the name field beside it.
    private static let avatarSize: CGFloat = 88

    private var nameField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            TextField(
                text: $displayName,
                prompt: Text(.authOnboardingDisplayNamePlaceholder)
            ) {
                Text(.settingsProfileNameLabel)
            }
            .textContentType(.name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(false)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space12)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
            .disabled(isSaving)

            Text(.authOnboardingDisplayNameSingleWordHint)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button(action: save) {
            Label {
                Text(isSaving ? .settingsProfileSaving : .settingsProfileSave)
            } icon: {
                if isSaving {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!canSave)
    }

    /// Brand names stay unlocalized; only the sentence around them is translated.
    /// Development/unknown sessions show no line rather than leaking internals.
    private var authProviderName: String? {
        switch authProvider {
        case .apple: "Apple"
        case .google: "Google"
        case .development, .unknown, nil: nil
        }
    }

    private var validatedDisplayName: String? {
        AuthDisplayNamePolicy.validatedSingleName(from: displayName)
    }

    private var photoUpdate: AuthProfilePhotoUpdate {
        if let selectedImageData {
            return .replace(selectedImageData)
        }
        if removesExistingPhoto {
            return .remove
        }
        return .unchanged
    }

    private var hasVisiblePhoto: Bool {
        selectedImage != nil || previewProfilePhotoAssetID != nil
    }

    /// Only a staged/custom override can be removed. A provider fallback can be
    /// changed by adding a custom photo, but never presents a remove action.
    private var hasRemovablePhoto: Bool {
        selectedImage != nil
            || (!removesExistingPhoto && originalCustomProfilePhotoAssetID != nil)
    }

    private var previewProfilePhotoAssetID: UUID? {
        if removesExistingPhoto {
            return providerProfilePhotoAssetID
        }
        return originalCustomProfilePhotoAssetID ?? providerProfilePhotoAssetID
    }

    private var hasChanges: Bool {
        validatedDisplayName != AuthDisplayNamePolicy.validatedSingleName(from: originalDisplayName)
            || photoUpdate != .unchanged
    }

    private var canSave: Bool {
        !isSaving && validatedDisplayName != nil && hasChanges
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else {
            if isResettingPicker {
                isResettingPicker = false
            }
            return
        }

        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw AuthServiceError.invalidProfilePhoto
                }
                cropDraft = PairedProfileCropDraft(image: image)
            } catch {
                bannerCenter.show(
                    .error(
                        title: String(localized: .settingsProfilePhotoLoadFailedTitle),
                        message: String(localized: .settingsProfilePhotoLoadFailedMessage)
                    )
                )
                resetPicker()
            }
        }
    }

    private func applyCroppedPhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            cropDraft = nil
            return
        }

        selectedImage = image
        selectedImageData = data
        removesExistingPhoto = false
        cropDraft = nil
        resetPicker()
    }

    private func cancelCrop() {
        cropDraft = nil
        resetPicker()
    }

    private func removePhoto() {
        selectedImage = nil
        selectedImageData = nil
        removesExistingPhoto = originalCustomProfilePhotoAssetID != nil
        resetPicker()
    }

    private func resetPicker() {
        guard selectedItem != nil else {
            isResettingPicker = false
            return
        }
        isResettingPicker = true
        selectedItem = nil
    }

    private func save() {
        guard let validatedDisplayName, canSave else {
            return
        }

        isSaving = true
        Task { @MainActor in
            let succeeded = await onSave(validatedDisplayName, photoUpdate)
            isSaving = false

            if succeeded {
                bannerCenter.show(
                    .info(
                        title: String(localized: .settingsProfileSavedTitle),
                        message: String(localized: .settingsProfileSavedMessage)
                    )
                )
                dismiss()
            } else {
                bannerCenter.show(
                    .error(
                        title: String(localized: .settingsProfileSaveFailedTitle),
                        message: String(localized: .settingsProfileSaveFailedMessage)
                    )
                )
            }
        }
    }
}

private struct PairedProfileCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}
