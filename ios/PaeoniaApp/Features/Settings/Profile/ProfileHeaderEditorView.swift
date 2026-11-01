import PhotosUI
import SwiftUI

/// The name and photo editor on the profile screen. The avatar is the anchor, with
/// its decoration left uncovered. A row of labelled buttons below it changes or
/// removes the photo, and the name field sits under that row at the same width.
/// Save appears under the name field once there is something to save.
///
/// Nothing leaves the device until the user taps Save. `ProfileEditorViewModel`
/// owns the edits and the async work; this view only draws them.
struct ProfileHeaderEditorView: View {
    let editor: ProfileEditorViewModel
    let onSave: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool

    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 104
    /// Keeps the centered field visually tied to the avatar instead of stretching
    /// the full screen width.
    @ScaledMetric(relativeTo: .body) private var nameFieldWidth: CGFloat = 260

    @Environment(\.avatarStyling) private var avatarStyling
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            avatar
            VStack(spacing: PaeoniaSpacing.space12) {
                photoActions
                nameField
                if draft.showsFirstNameHint {
                    Text(.authOnboardingDisplayNameFirstNameHint)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaWarning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsSaveButton {
                    saveButton
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .frame(maxWidth: nameFieldWidth)
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: showsSaveButton)
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
                AvatarDecorationArtwork(decoration: decoration, size: resolvedAvatarSize)
            }
            .overlay {
                if editor.isLoadingPhoto {
                    Circle()
                        .fill(.black.opacity(0.35))
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityLabel(Text(.settingsProfilePhotoLoading))
                }
            }
            .padding(resolvedAvatarSize * decoration.outset)
    }

    private var decoration: AvatarDecoration {
        avatarStyling?.decorations.own ?? .none
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

    /// Side by side when they fit, stacked at large text sizes.
    @ViewBuilder
    private var photoActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: PaeoniaSpacing.space8) { photoActionButtons }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaeoniaSpacing.space8) { photoActionButtons }
                VStack(spacing: PaeoniaSpacing.space8) { photoActionButtons }
            }
        }
    }

    @ViewBuilder
    private var photoActionButtons: some View {
        // The picker's label closure is not on the main actor, so it gets a ready-made view.
        let pickLabel = ProfilePhotoActionLabel(
            title: draft.hasVisiblePhoto ? .settingsProfilePhotoChange : .settingsProfilePhotoAdd,
            systemImage: draft.hasVisiblePhoto ? "camera.fill" : "plus",
            tint: .paeoniaAccentPrimary
        )
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            pickLabel
        }
        .buttonStyle(.plain)
        .disabled(editor.isSaving)
        .accessibilityIdentifier("settings.profile.photo.change")

        if draft.hasRemovablePhoto {
            Button(action: editor.removePhoto) {
                ProfilePhotoActionLabel(
                    title: .settingsProfilePhotoRemove,
                    systemImage: "trash",
                    tint: .paeoniaErrorText
                )
            }
            .buttonStyle(.plain)
            .disabled(editor.isSaving || editor.isLoadingPhoto)
            .accessibilityIdentifier("settings.profile.photo.remove")
        }
    }

    /// Let the identity anchor grow with text without letting it take over the screen.
    private var resolvedAvatarSize: CGFloat {
        min(avatarSize, 132)
    }

    /// Initials need something to draw before the account has a name.
    private var avatarName: String {
        draft.name.trimmedNonEmpty ?? String(localized: .settingsProfileFallbackName)
    }
}

// MARK: - Name and save

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
        .disabled(editor.isSaving)
        .accessibilityIdentifier("settings.profile.displayName")
    }

    private var showsSaveButton: Bool {
        draft.hasChanges || editor.isSaving
    }

    private var saveButton: some View {
        Button {
            PaeoniaKeyboard.dismiss()
            Task { await editor.save(using: onSave) }
        } label: {
            Text(.settingsProfileSave)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: editor.isSaving))
        .disabled(!editor.canSave)
        .accessibilityIdentifier("settings.profile.save")
    }
}

/// A capsule with an icon and a short label, sized to its text so the two
/// actions read as a pair under the avatar.
private struct ProfilePhotoActionLabel: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(tint)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }
}

#Preview {
    ScrollView {
        ProfileHeaderEditorView(editor: ProfileEditorViewModel(), onSave: { _, _ in true })
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
    }
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
