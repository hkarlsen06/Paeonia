import SwiftUI

struct AuthLaunchingView: View {
    var body: some View {
        PaeoniaCard {
            VStack(spacing: PaeoniaSpacing.space16) {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)

                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(.authLaunchingTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.authLaunchingMessage)
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

struct AuthOnboardingView: View {
    let session: AuthSession?
    let isWorking: Bool
    let onCompleteOnboarding: (String) -> Void
    let onSignOut: () -> Void

    @State private var displayName: String

    init(
        session: AuthSession?,
        isWorking: Bool,
        onCompleteOnboarding: @escaping (String) -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.session = session
        self.isWorking = isWorking
        self.onCompleteOnboarding = onCompleteOnboarding
        self.onSignOut = onSignOut
        _displayName = State(initialValue: session?.displayName ?? "")
    }

    var body: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .authOnboardingTitle,
                message: .authOnboardingMessage,
                systemImage: "person.crop.circle.badge.checkmark"
            ) {
                onboardingActions
            }
        }
    }

    private var onboardingActions: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            displayNameField
            completeButton
            signOutButton
        }
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
            onCompleteOnboarding(displayName)
        } label: {
            Label {
                Text(.authOnboardingCompleteButton)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(isWorking || displayName.trimmedNonEmpty == nil)
    }

    private var signOutButton: some View {
        Button(action: onSignOut) {
            Text(.authOnboardingSignOutButton)
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isWorking)
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
