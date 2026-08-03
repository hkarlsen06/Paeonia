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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 104
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
                photoSection
                nameSection
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.settingsProfileEditorTitle))
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissable()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space12)
                .padding(.bottom, PaeoniaSpacing.space8)
                .background(.paeoniaBackgroundPrimary)
        }
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
    /// The photo is the visual anchor for this focused editor. The avatar itself
    /// opens the photo picker (with a camera badge as the affordance), so the
    /// actions below can stay quiet text instead of two competing boxed buttons.
    private var photoSection: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            avatarPicker
            photoActions

            VStack(spacing: PaeoniaSpacing.space4) {
                Text(.settingsProfilePhotoMessage)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let authProviderName {
                    Text(.settingsProfileSignedInWith(authProviderName))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarPicker: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            profilePreview
                .overlay(alignment: .bottomTrailing) {
                    cameraBadge
                }
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(
            Text(hasVisiblePhoto ? .settingsProfilePhotoChange : .settingsProfilePhotoAdd)
        )
    }

    private var cameraBadge: some View {
        Image(systemName: "camera.fill")
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextInverse)
            .frame(width: 30, height: 30)
            .background(.paeoniaAccentPrimary)
            .clipShape(Circle())
            .overlay {
                // Ring in the screen background so the badge reads as sitting on
                // top of the avatar instead of merging into its edge.
                Circle()
                    .stroke(.paeoniaBackgroundPrimary, lineWidth: 2)
            }
            .accessibilityHidden(true)
    }

    private var photoActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space8))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))

        return layout {
            changePhotoButton

            if hasRemovablePhoto {
                removePhotoButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var changePhotoButton: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            photoActionLabel(
                hasVisiblePhoto ? .settingsProfilePhotoChange : .settingsProfilePhotoAdd,
                systemName: hasVisiblePhoto ? "photo.badge.arrow.down" : "photo.badge.plus"
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(
            Text(hasVisiblePhoto ? .settingsProfilePhotoChange : .settingsProfilePhotoAdd)
        )
    }

    private var removePhotoButton: some View {
        Button(action: removePhoto) {
            photoActionLabel(
                .settingsProfilePhotoRemove,
                systemName: "trash",
                tint: .paeoniaError
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(Text(.settingsProfilePhotoRemove))
    }

    /// Quiet text actions under the avatar. They keep full button-sized hit
    /// targets, but without boxed backgrounds the avatar stays the visual anchor.
    private func photoActionLabel(
        _ title: LocalizedStringResource,
        systemName: String,
        tint: Color = .paeoniaAccentPrimary
    ) -> some View {
        Label {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemName)
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.button)
        .foregroundStyle(tint)
        .padding(.horizontal, PaeoniaSpacing.space16)
        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        .contentShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private var profilePreview: some View {
        if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFill()
                .frame(width: resolvedAvatarSize, height: resolvedAvatarSize)
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
                size: resolvedAvatarSize
            )
        }
    }

    /// Let the identity anchor grow with text without allowing it to crowd the
    /// form at the largest accessibility sizes.
    private var resolvedAvatarSize: CGFloat {
        min(avatarSize, 136)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            // Matches the section-header treatment in Settings so the form label
            // supports the field instead of competing with it.
            Text(.settingsProfileNameLabel)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextSecondary)

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

            if showsSingleWordHint {
                Text(.authOnboardingDisplayNameSingleWordHint)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The single-word rule is otherwise invisible: a multi-word name just leaves
    /// Save disabled with no explanation.
    private var showsSingleWordHint: Bool {
        displayName.trimmedNonEmpty != nil && validatedDisplayName == nil
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: PaeoniaSpacing.space8) {
                if isSaving {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityHidden(true)
                }

                Text(isSaving ? .settingsProfileSaving : .settingsProfileSave)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!canSave)
        // The spinner and "Saving" label fade in instead of snapping while the
        // save settles in the background.
        .animation(PaeoniaMotion.stateChange, value: isSaving)
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
