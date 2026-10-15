import PhotosUI
import SwiftUI
import UIKit

/// Profile setup right after the first sign-in: a photo and a name, both required.
/// A Google photo imported at sign-in shows in the avatar and counts as the photo.
/// Continue sits at the bottom, with sign out and account deletion as quiet links
/// under it. The keyboard covers them while the name is typed, and the keyboard's
/// Continue key submits.
struct AuthOnboardingView: View {
    let isWorking: Bool
    /// The photo already on the account, such as the imported Google photo.
    let savedPhotoAssetID: UUID?
    let onCompleteOnboarding: (String, Data?) -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var displayName: String
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
    @State private var selectedProfilePhotoData: Data?
    @State private var selectedProfilePhotoImage: Image?
    @State private var profilePhotoCropDraft: ProfilePhotoCropDraft?
    @State private var isConfirmingDelete = false
    /// The user tapped Continue. The spinner shows only while that save runs,
    /// not while a sign-out from the menu is running.
    @State private var hasSubmitted = false
    /// The user tapped Continue without a photo. The note under the photo stays
    /// until a photo is picked.
    @State private var triedWithoutPhoto = false
    @FocusState private var isNameFocused: Bool
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(
        session: AuthSession?,
        isWorking: Bool,
        onCompleteOnboarding: @escaping (String, Data?) -> Void,
        onSignOut: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) {
        self.isWorking = isWorking
        self.savedPhotoAssetID = session?.profilePhotoAssetID
        self.onCompleteOnboarding = onCompleteOnboarding
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        _displayName = State(initialValue: session?.displayName ?? "")
    }

    var body: some View {
        ScrollView {
            onboardingContent
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space24)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .paeoniaBottomBar(spacing: 0) {
            VStack(spacing: PaeoniaSpacing.space4) {
                completeButton
                accountActions
            }
            .padding(.top, PaeoniaSpacing.space12)
            .screenEntrance(order: 4)
        }
        .task(id: selectedProfilePhotoItem) {
            await loadProfilePhoto(from: selectedProfilePhotoItem)
        }
        .sheet(item: $profilePhotoCropDraft) { draft in
            PaeoniaProfileImageCropSheet(
                image: draft.image,
                onCrop: applyCroppedProfilePhoto,
                onCancel: { profilePhotoCropDraft = nil }
            )
            .ignoresSafeArea()
        }
        .alert(
            Text(.authDeleteAccountConfirmTitle),
            isPresented: $isConfirmingDelete
        ) {
            Button(role: .destructive, action: onDeleteAccount) {
                Text(.authDeleteAccountConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.authDeleteAccountConfirmCancel)
            }
        } message: {
            Text(.authDeleteAccountConfirmMessage)
        }
    }

    private var onboardingContent: some View {
        VStack(spacing: PaeoniaSpacing.space20) {
            profilePhotoSection
                .screenEntrance(order: 1)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.authOnboardingTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(.authOnboardingMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .screenEntrance(order: 2)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                displayNameField

                if showsFirstNameHint {
                    Text(.authOnboardingDisplayNameFirstNameHint)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(PaeoniaMotion.stateChange, value: showsFirstNameHint)
            .screenEntrance(order: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var validatedName: String? {
        AuthDisplayNamePolicy.validatedName(from: displayName)
    }

    /// The two-word limit is otherwise invisible: a first name with a surname just
    /// leaves Continue disabled with no explanation.
    private var showsFirstNameHint: Bool {
        displayName.trimmedNonEmpty != nil && validatedName == nil
    }

    private var hasPhoto: Bool {
        selectedProfilePhotoData != nil || savedPhotoAssetID != nil
    }

    private var showsPhotoRequiredHint: Bool {
        triedWithoutPhoto && !hasPhoto
    }

    private var isSaving: Bool {
        hasSubmitted && isWorking
    }

    private var displayNameField: some View {
        TextField(
            text: $displayName,
            prompt: Text(.authOnboardingDisplayNamePlaceholder)
        ) {
            Text(.authOnboardingDisplayNameLabel)
        }
        .focused($isNameFocused)
        .textContentType(.givenName)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.continue)
        .onSubmit(complete)
        .disabled(isWorking)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
        .accessibilityIdentifier("auth.onboarding.displayName")
    }

    private var completeButton: some View {
        Button(action: complete) {
            Text(.authOnboardingCompleteButton)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isSaving))
        // Stays tappable while something is missing, so a tap can point at it.
        .disabled(isWorking && !isSaving)
        .accessibilityIdentifier("auth.onboarding.complete")
    }

    /// Quiet links under Continue, like the paywall's footer. They sit here rather
    /// than in a navigation bar, so the logo above stays at the same height from
    /// this screen to the next.
    private var accountActions: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button(action: onSignOut) {
                accountActionLabel(.authOnboardingSignOutButton)
            }

            Text(verbatim: "·")
                .accessibilityHidden(true)

            Button {
                isConfirmingDelete = true
            } label: {
                accountActionLabel(.authDeleteAccountButton)
            }
        }
        .buttonStyle(.plain)
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextTertiary)
        .disabled(isWorking)
    }

    private func accountActionLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
    }

    private func complete() {
        guard !isWorking else {
            return
        }
        guard hasPhoto, let name = validatedName else {
            showMissingRequirements()
            return
        }

        isNameFocused = false
        hasSubmitted = true
        PaeoniaHaptics.profileSetupSent()
        onCompleteOnboarding(name, selectedProfilePhotoData)
    }

    /// Points at what still blocks setup: a note and a stronger ring on the photo,
    /// and the keyboard for a missing or too long name.
    private func showMissingRequirements() {
        PaeoniaHaptics.validationError()
        if !hasPhoto {
            triedWithoutPhoto = true
            AccessibilityNotification.Announcement(
                String(localized: .authOnboardingProfilePhotoRequired)
            ).post()
        }
        if validatedName == nil {
            isNameFocused = true
        }
    }
}

// MARK: - Photo

extension AuthOnboardingView {
    private var profilePhotoSection: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            profilePhotoPicker

            if showsPhotoRequiredHint {
                Text(.authOnboardingProfilePhotoRequired)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: showsPhotoRequiredHint)
    }

    private var profilePhotoPicker: some View {
        // The picker's label closure is not on the main actor, so it gets a ready-made view.
        let preview = AuthOnboardingPhotoPreview(
            image: selectedProfilePhotoImage,
            savedPhotoAssetID: savedPhotoAssetID,
            name: displayName,
            hasPhoto: hasPhoto,
            showsPhotoRequiredHint: showsPhotoRequiredHint
        )
        return PhotosPicker(
            selection: $selectedProfilePhotoItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            preview
        }
        .disabled(isWorking)
        .accessibilityLabel(
            Text(
                hasPhoto
                    ? .authOnboardingProfilePhotoChange
                    : .authOnboardingProfilePhotoAdd
            )
        )
        .accessibilityIdentifier("auth.onboarding.profilePhoto")
    }

    /// Loads the picked photo and opens the crop sheet. The picker selection is
    /// cleared afterwards so picking the same photo again works, and a newer
    /// pick cancels an older load through `.task(id:)`.
    private func loadProfilePhoto(from item: PhotosPickerItem?) async {
        guard let item else {
            return
        }

        let data = try? await item.loadTransferable(type: Data.self)
        guard !Task.isCancelled else {
            return
        }

        selectedProfilePhotoItem = nil
        guard let data, let image = UIImage(data: data) else {
            bannerCenter.show(
                .error(
                    title: String(localized: .authOnboardingPhotoLoadFailedTitle),
                    message: String(localized: .authOnboardingPhotoLoadFailedMessage)
                )
            )
            return
        }

        profilePhotoCropDraft = ProfilePhotoCropDraft(image: image)
    }

    private func applyCroppedProfilePhoto(_ image: UIImage) {
        profilePhotoCropDraft = nil
        guard let imageData = image.jpegData(compressionQuality: 0.95) else {
            return
        }

        selectedProfilePhotoData = imageData
        selectedProfilePhotoImage = Image(uiImage: image)
    }
}

/// The round photo in the profile picker, with its add or change badge.
private struct AuthOnboardingPhotoPreview: View {
    let image: Image?
    let savedPhotoAssetID: UUID?
    let name: String
    let hasPhoto: Bool
    let showsPhotoRequiredHint: Bool

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else if let savedPhotoAssetID {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: savedPhotoAssetID,
                    name: name,
                    tint: .paeoniaPartnerOne,
                    size: 88
                )
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(PaeoniaSpacing.space12)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
        .frame(width: 88, height: 88)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(
                    .paeoniaAccentPrimary.opacity(showsPhotoRequiredHint ? 1 : 0.25),
                    lineWidth: showsPhotoRequiredHint ? 2 : 1
                )
        }
        .animation(PaeoniaMotion.stateChange, value: showsPhotoRequiredHint)
        .accessibilityHidden(true)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: hasPhoto ? "pencil.circle.fill" : "plus.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .background(Circle().fill(.paeoniaBackgroundPrimary))
                .accessibilityHidden(true)
        }
    }
}

private struct ProfilePhotoCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

#if DEBUG
#Preview {
    NavigationStack {
        AuthOnboardingView(
            session: nil,
            isWorking: false,
            onCompleteOnboarding: { _, _ in },
            onSignOut: {},
            onDeleteAccount: {}
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .background(.paeoniaBackgroundPrimary)
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
