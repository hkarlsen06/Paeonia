import PhotosUI
import SwiftUI
import UIKit

/// Profile setup right after the first sign-in: a name and an optional photo.
/// One primary action sits above the keyboard; sign out and account deletion
/// live in the toolbar menu so a new user is not met with a delete button.
struct AuthOnboardingView: View {
    let isWorking: Bool
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
            profilePhotoPicker
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

                if showsSingleWordHint {
                    Text(.authOnboardingDisplayNameSingleWordHint)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(PaeoniaMotion.stateChange, value: showsSingleWordHint)
            .screenEntrance(order: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var validatedName: String? {
        AuthDisplayNamePolicy.validatedSingleName(from: displayName)
    }

    /// The single-word rule is otherwise invisible: a multi-word name just leaves
    /// Continue disabled with no explanation.
    private var showsSingleWordHint: Bool {
        displayName.trimmedNonEmpty != nil && validatedName == nil
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
        .disabled(validatedName == nil || (isWorking && !isSaving))
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
        guard !isWorking, let name = validatedName else {
            return
        }

        isNameFocused = false
        hasSubmitted = true
        PaeoniaHaptics.profileSetupSent()
        onCompleteOnboarding(name, selectedProfilePhotoData)
    }

    private var profilePhotoPicker: some View {
        PhotosPicker(
            selection: $selectedProfilePhotoItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            profilePhotoPreview
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: selectedProfilePhotoImage == nil ? "plus.circle.fill" : "pencil.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .background(Circle().fill(.paeoniaBackgroundPrimary))
                        .accessibilityHidden(true)
                }
        }
        .disabled(isWorking)
        .accessibilityLabel(
            Text(
                selectedProfilePhotoImage == nil
                    ? .authOnboardingProfilePhotoAdd
                    : .authOnboardingProfilePhotoChange
            )
        )
    }

    private var profilePhotoPreview: some View {
        Group {
            if let selectedProfilePhotoImage {
                selectedProfilePhotoImage
                    .resizable()
                    .scaledToFill()
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
                .strokeBorder(.paeoniaAccentPrimary.opacity(0.25), lineWidth: 1)
        }
        .accessibilityHidden(true)
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
        // swiftlint:disable:next accessibility_label_for_image
        selectedProfilePhotoImage = Image(uiImage: image)
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
