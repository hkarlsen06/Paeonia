import PhotosUI
import SwiftUI
import UIKit

/// The profile editor at the top of the Me tab. Editing a name or photo is a
/// two-control job, so it lives inline instead of behind its own screen: the avatar
/// is the anchor, two small round buttons on its bottom corners change or remove the
/// photo, and the name is edited in a centered field right below it.
///
/// Nothing leaves the device until the user taps Save, which only appears once
/// something has actually changed.
struct ProfileHeaderEditorView: View {
    /// The saved name from the session. `nil` while it is still loading.
    let savedDisplayName: String?
    let customProfilePhotoAssetID: UUID?
    let providerProfilePhotoAssetID: UUID?
    let authProvider: AuthProvider?
    let onSave: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 104
    @ScaledMetric(relativeTo: .caption) private var photoActionSize: CGFloat = 34
    /// Keeps the centered field visually tied to the avatar instead of stretching
    /// the full screen width.
    @ScaledMetric(relativeTo: .body) private var nameFieldWidth: CGFloat = 260

    @State private var typedName: String?
    @State private var stagedPhotoData: Data?
    @State private var stagedImage: UIImage?
    @State private var removesExistingPhoto = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var cropDraft: ProfilePhotoCropDraft?
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            avatar
            nameField
            supportingCopy

            if draft.hasChanges {
                pendingChangeActions
            }
        }
        .frame(maxWidth: .infinity)
        // The Save button fades in when the first edit lands instead of snapping
        // the rest of the tab downwards.
        .animation(PaeoniaMotion.stateChange, value: draft.hasChanges)
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

// MARK: - Avatar

extension ProfileHeaderEditorView {
    private var avatar: some View {
        profilePreview
            .overlay(alignment: .bottomLeading) {
                changePhotoButton
            }
            .overlay(alignment: .bottomTrailing) {
                removePhotoButton
            }
    }

    @ViewBuilder
    private var profilePreview: some View {
        if let stagedImage {
            Image(uiImage: stagedImage)
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
                mediaAssetID: draft.previewPhotoAssetID,
                name: avatarName,
                tint: .paeoniaPartnerOne,
                size: resolvedAvatarSize
            )
            .accessibilityHidden(true)
        }
    }

    private var changePhotoButton: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            photoActionBadge(
                systemName: draft.hasVisiblePhoto ? "camera.fill" : "plus",
                foreground: .paeoniaTextInverse,
                background: .paeoniaAccentPrimary
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .offset(x: -PaeoniaSpacing.space8, y: PaeoniaSpacing.space8)
        .accessibilityLabel(
            Text(draft.hasVisiblePhoto ? .settingsProfilePhotoChange : .settingsProfilePhotoAdd)
        )
    }

    @ViewBuilder
    private var removePhotoButton: some View {
        if draft.hasRemovablePhoto {
            Button(action: removePhoto) {
                photoActionBadge(
                    systemName: "trash.fill",
                    foreground: .paeoniaError,
                    background: .paeoniaSurfaceSecondary
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .offset(x: PaeoniaSpacing.space8, y: PaeoniaSpacing.space8)
            .accessibilityLabel(Text(.settingsProfilePhotoRemove))
        }
    }

    /// A small round action sitting on the avatar's edge. The ring in the screen
    /// background keeps it from merging into the photo behind it.
    private func photoActionBadge(
        systemName: String,
        foreground: Color,
        background: Color
    ) -> some View {
        Image(systemName: systemName)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(width: resolvedPhotoActionSize, height: resolvedPhotoActionSize)
            .background(background)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.paeoniaBackgroundPrimary, lineWidth: 2)
            }
            // The badge stays visually small, but the tap area keeps the platform
            // 44-point touch target.
            .frame(
                width: PaeoniaSpacing.compactButtonHeight,
                height: PaeoniaSpacing.compactButtonHeight
            )
            .contentShape(Circle())
            // The surrounding control carries the label.
            .accessibilityHidden(true)
    }

    /// Let the identity anchor grow with text without letting it take over the tab.
    private var resolvedAvatarSize: CGFloat {
        min(avatarSize, 132)
    }

    /// Cap the badge at the touch target so it never outgrows its own hit area.
    private var resolvedPhotoActionSize: CGFloat {
        min(photoActionSize, PaeoniaSpacing.compactButtonHeight)
    }

    /// Initials need something to draw before the account has a name.
    private var avatarName: String {
        draft.name.trimmedNonEmpty ?? String(localized: .settingsProfileFallbackName)
    }
}

// MARK: - Name and supporting copy

extension ProfileHeaderEditorView {
    private var nameField: some View {
        TextField(
            text: nameBinding,
            prompt: Text(.authOnboardingDisplayNamePlaceholder)
        ) {
            Text(.settingsProfileNameLabel)
        }
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaTextPrimary)
        .multilineTextAlignment(.center)
        .textContentType(.name)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled(false)
        .submitLabel(.done)
        .focused($isNameFocused)
        .onSubmit(save)
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
        .frame(maxWidth: nameFieldWidth)
        .disabled(isSaving)
        .accessibilityIdentifier("settings.profile.displayName")
    }

    private var supportingCopy: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            if draft.showsSingleWordHint {
                Text(.authOnboardingDisplayNameSingleWordHint)
                    .foregroundStyle(.paeoniaWarning)
            }

            Text(.settingsProfilePhotoMessage)
                .foregroundStyle(.paeoniaTextSecondary)

            if let authProviderName {
                Text(.settingsProfileSignedInWith(authProviderName))
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
        .font(PaeoniaTypography.caption)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Both ways out of an unsaved edit, side by side: keep it or drop it. The
    /// quiet discard action keeps a full button-sized hit target and normal button
    /// spacing so it is easy to hit without competing with Save.
    private var pendingChangeActions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            saveButton
            discardButton
        }
        .transition(.opacity)
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
        .disabled(isSaving || !draft.canSave)
        // The spinner and "Saving" label fade in instead of snapping while the save
        // settles in the background.
        .animation(PaeoniaMotion.stateChange, value: isSaving)
    }

    /// Puts the name and photo back to what is saved on the account. Only the
    /// unsaved edits go away, so nothing the user has already saved is at risk.
    private var discardButton: some View {
        Button {
            isNameFocused = false
            clearEdits()
        } label: {
            Text(.settingsProfileDiscard)
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isSaving)
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
}

// MARK: - State

extension ProfileHeaderEditorView {
    private var draft: ProfileEditorDraft {
        ProfileEditorDraft(
            savedName: savedDisplayName?.trimmedNonEmpty ?? "",
            customPhotoAssetID: customProfilePhotoAssetID,
            providerPhotoAssetID: providerProfilePhotoAssetID,
            typedName: typedName,
            stagedPhotoData: stagedPhotoData,
            removesExistingPhoto: removesExistingPhoto
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { draft.name },
            set: { typedName = $0 }
        )
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw AuthServiceError.invalidProfilePhoto
                }
                cropDraft = ProfilePhotoCropDraft(image: image)
            } catch {
                bannerCenter.show(
                    .error(
                        title: String(localized: .settingsProfilePhotoLoadFailedTitle),
                        message: String(localized: .settingsProfilePhotoLoadFailedMessage)
                    )
                )
                selectedItem = nil
            }
        }
    }

    private func applyCroppedPhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            cropDraft = nil
            return
        }

        stagedImage = image
        stagedPhotoData = data
        removesExistingPhoto = false
        cropDraft = nil
        selectedItem = nil
    }

    private func cancelCrop() {
        cropDraft = nil
        selectedItem = nil
    }

    private func removePhoto() {
        stagedImage = nil
        stagedPhotoData = nil
        removesExistingPhoto = customProfilePhotoAssetID != nil
        selectedItem = nil
    }

    /// Drops the pending edits so the header follows the saved profile again. Only
    /// called after a successful save, never on failure — a failed save keeps the
    /// user's work in place so they can retry it.
    private func clearEdits() {
        typedName = nil
        stagedImage = nil
        stagedPhotoData = nil
        removesExistingPhoto = false
        selectedItem = nil
    }

    private func save() {
        let draft = draft
        guard !isSaving, draft.canSave, let validatedName = draft.validatedName else {
            return
        }

        isNameFocused = false
        isSaving = true
        Task { @MainActor in
            let succeeded = await onSave(validatedName, draft.photoUpdate)
            isSaving = false

            if succeeded {
                clearEdits()
                bannerCenter.show(
                    .info(
                        title: String(localized: .settingsProfileSavedTitle),
                        message: String(localized: .settingsProfileSavedMessage)
                    )
                )
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

/// Identifies the image currently being cropped so the crop sheet presents per
/// picked photo rather than per boolean flag.
private struct ProfilePhotoCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview {
    ScrollView {
        ProfileHeaderEditorView(
            savedDisplayName: "Hjalmar",
            customProfilePhotoAssetID: nil,
            providerProfilePhotoAssetID: nil,
            authProvider: .apple,
            onSave: { _, _ in true }
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
    }
    .background(.paeoniaBackgroundPrimary)
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
