import PhotosUI
import SwiftUI

/// The name and photo editor on the profile screen. The avatar is the anchor, two
/// small round buttons on its bottom corners change or remove the photo, and the
/// name is edited in a centered field right below it.
///
/// Nothing leaves the device until the user taps Save. `ProfileEditorViewModel`
/// owns the edits and the async work; this view only draws them.
struct ProfileHeaderEditorView: View {
    let editor: ProfileEditorViewModel

    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 104
    @ScaledMetric(relativeTo: .caption) private var photoActionSize: CGFloat = 34
    /// Keeps the centered field visually tied to the avatar instead of stretching
    /// the full screen width.
    @ScaledMetric(relativeTo: .body) private var nameFieldWidth: CGFloat = 260

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            avatar
            nameField
            supportingCopy
        }
        .frame(maxWidth: .infinity)
        .onChange(of: selectedItem) { _, item in
            guard let item else {
                return
            }
            // Clear the selection right away, so picking the same photo again
            // after a cancelled crop still counts as a new pick.
            selectedItem = nil
            PaeoniaKeyboard.dismiss()
            editor.pickPhoto {
                try await item.loadTransferable(type: Data.self)
            }
        }
        .sheet(
            item: Binding(
                get: { editor.cropRequest },
                set: { if $0 == nil { editor.cancelCrop() } }
            )
        ) { request in
            PaeoniaProfileImageCropSheet(
                image: request.image,
                onCrop: { image in
                    Task { await editor.applyCroppedPhoto(image) }
                },
                onCancel: editor.cancelCrop
            )
            .ignoresSafeArea()
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Avatar

extension ProfileHeaderEditorView {
    private var avatar: some View {
        profilePreview
            .overlay {
                if editor.isLoadingPhoto {
                    Circle()
                        .fill(.black.opacity(0.35))
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityLabel(Text(.settingsProfilePhotoLoading))
                }
            }
            .overlay(alignment: .bottomLeading) {
                changePhotoButton
            }
            .overlay(alignment: .bottomTrailing) {
                removePhotoButton
            }
    }

    @ViewBuilder
    private var profilePreview: some View {
        if let stagedImage = editor.stagedImage {
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
        .disabled(editor.isSaving)
        .offset(x: -PaeoniaSpacing.space8, y: PaeoniaSpacing.space8)
        .accessibilityLabel(
            Text(draft.hasVisiblePhoto ? .settingsProfilePhotoChange : .settingsProfilePhotoAdd)
        )
    }

    @ViewBuilder
    private var removePhotoButton: some View {
        if draft.hasRemovablePhoto {
            Button(action: editor.removePhoto) {
                photoActionBadge(
                    systemName: "trash.fill",
                    foreground: .paeoniaError,
                    background: .paeoniaSurfaceSecondary
                )
            }
            .buttonStyle(.plain)
            .disabled(editor.isSaving || editor.isLoadingPhoto)
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

    /// Let the identity anchor grow with text without letting it take over the screen.
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
    private var draft: ProfileEditorDraft {
        editor.draft
    }

    private var nameField: some View {
        TextField(
            text: Binding(get: { draft.name }, set: editor.setName),
            prompt: Text(.authOnboardingDisplayNamePlaceholder)
        ) {
            Text(.settingsProfileNameLabel)
        }
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaTextPrimary)
        .multilineTextAlignment(.center)
        // Only a first name is allowed, so do not offer to fill in a full name.
        .textContentType(.givenName)
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .onSubmit { PaeoniaKeyboard.dismiss() }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
        .frame(maxWidth: nameFieldWidth)
        .disabled(editor.isSaving)
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
        }
        .font(PaeoniaTypography.caption)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    ScrollView {
        ProfileHeaderEditorView(editor: ProfileEditorViewModel())
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
    }
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
