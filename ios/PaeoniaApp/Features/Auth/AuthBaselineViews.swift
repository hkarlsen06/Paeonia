import PhotosUI
import SwiftUI
import UIKit

/// A quiet, copy-free launch state that picks up where the system launch screen
/// leaves off. It is often visible only for a split second, so it should not try
/// to explain work that the user will not have time to read.
struct AuthLaunchingView: View {
    var body: some View {
        Color.paeoniaBackgroundPrimary
            .ignoresSafeArea()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.appStateLaunching))
    }
}

struct AuthOnboardingView: View {
    let session: AuthSession?
    let isWorking: Bool
    let onCompleteOnboarding: (String, Data?) -> Void
    let onSignOut: () -> Void

    @State private var displayName: String
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
    @State private var selectedProfilePhotoData: Data?
    @State private var selectedProfilePhotoImage: Image?

    init(
        session: AuthSession?,
        isWorking: Bool,
        onCompleteOnboarding: @escaping (String, Data?) -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.session = session
        self.isWorking = isWorking
        self.onCompleteOnboarding = onCompleteOnboarding
        self.onSignOut = onSignOut
        _displayName = State(initialValue: session?.displayName ?? "")
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space32) {
            Spacer(minLength: PaeoniaSpacing.space16)

            onboardingContent

            Spacer(minLength: PaeoniaSpacing.space24)

            onboardingActions
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var onboardingMessage: LocalizedStringResource {
        if session?.displayName?.trimmedNonEmpty != nil {
            return .authOnboardingPrefilledMessage
        }

        return .authOnboardingMessage
    }

    private var onboardingContent: some View {
        VStack(spacing: PaeoniaSpacing.space20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.authOnboardingTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(onboardingMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                profilePhotoPicker
                displayNameField

                if hasMultipleDisplayNameWords {
                    Text(.authOnboardingDisplayNameSingleWordHint)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: selectedProfilePhotoItem) { _, item in
            loadProfilePhoto(from: item)
        }
    }

    private var onboardingActions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            completeButton
            signOutButton
        }
    }

    private var canCompleteOnboarding: Bool {
        !isWorking && AuthDisplayNamePolicy.validatedSingleName(from: displayName) != nil
    }

    private var hasMultipleDisplayNameWords: Bool {
        displayName
            .split(whereSeparator: \.isWhitespace)
            .count > 1
    }

    private var displayNameField: some View {
        TextField(
            text: $displayName,
            prompt: Text(.authOnboardingDisplayNamePlaceholder)
        ) {
            Text(.authOnboardingDisplayNameLabel)
        }
        .textContentType(.name)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled(false)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
    }

    private var completeButton: some View {
        Button {
            guard AuthDisplayNamePolicy.validatedSingleName(from: displayName) != nil else {
                return
            }

            onCompleteOnboarding(displayName, selectedProfilePhotoData)
        } label: {
            Label {
                Text(.authOnboardingCompleteButton)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!canCompleteOnboarding)
    }

    private var signOutButton: some View {
        Button(action: onSignOut) {
            Text(.authOnboardingSignOutButton)
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isWorking)
    }

    private var profilePhotoPicker: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            profilePhotoPreview

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(.authOnboardingProfilePhotoTitle)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.authOnboardingProfilePhotoMessage)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: PaeoniaSpacing.space8)

            PhotosPicker(
                selection: $selectedProfilePhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: selectedProfilePhotoImage == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityLabel(
                        Text(
                            selectedProfilePhotoImage == nil
                                ? .authOnboardingProfilePhotoAdd
                                : .authOnboardingProfilePhotoChange
                        )
                    )
            }
            .disabled(isWorking)
        }
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
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
                    .padding(PaeoniaSpacing.space8)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
        .frame(width: 68, height: 68)
        .background(.paeoniaSurfacePrimary)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.paeoniaAccentPrimary.opacity(0.25), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func loadProfilePhoto(from item: PhotosPickerItem?) {
        guard let item else {
            selectedProfilePhotoData = nil
            selectedProfilePhotoImage = nil
            return
        }

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                return
            }

            selectedProfilePhotoData = data
            // swiftlint:disable:next accessibility_label_for_image
            selectedProfilePhotoImage = Image(uiImage: image)
        }
    }
}

struct AuthenticatedBaselineView: View {
    let isWorking: Bool
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        card
            .confirmationDialog(
                Text(.authDeleteAccountConfirmTitle),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
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

    private var card: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .authSignedInTitle,
                message: .authSignedInMessage,
                systemImage: "heart.circle.fill"
            ) {
                actionStack
            }
        }
    }

    private var actionStack: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.authSignedInReadyCaption)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)

            Button(action: onSignOut) {
                Label {
                    Text(.authSignOutButton)
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(isWorking)

            Button {
                isConfirmingDelete = true
            } label: {
                Label {
                    Text(.authDeleteAccountButton)
                } icon: {
                    Image(systemName: "trash.fill")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaDestructiveButtonStyle())
            .disabled(isWorking)
        }
    }
}

struct AuthDeletingAccountView: View {
    var body: some View {
        PaeoniaCard {
            VStack(spacing: PaeoniaSpacing.space16) {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)

                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(.authDeletingTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.authDeletingMessage)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PaeoniaSpacing.space8)
        }
    }
}

struct AuthUnavailableRouteView: View {
    var body: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .authRouteUnavailableTitle,
                message: .authRouteUnavailableMessage,
                systemImage: "clock"
            )
        }
    }
}
