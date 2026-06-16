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

struct AuthStartView: View {
    let isWorking: Bool
    let onDevelopmentSignIn: () -> Void

    var body: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .authStartTitle,
                message: .authStartMessage,
                systemImage: "lock.heart"
            ) {
                VStack(spacing: PaeoniaSpacing.space8) {
                    Button(action: onDevelopmentSignIn) {
                        Label {
                            Text(.authSignInDevelopmentButton)
                        } icon: {
                            Image(systemName: "person.badge.key.fill")
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle())
                    .disabled(isWorking)

                    Text(.authSignInDevelopmentHint)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

struct AuthOnboardingView: View {
    let isWorking: Bool
    let onCompleteOnboarding: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .authOnboardingTitle,
                message: .authOnboardingMessage,
                systemImage: "person.crop.circle.badge.checkmark"
            ) {
                VStack(spacing: PaeoniaSpacing.space8) {
                    Button(action: onCompleteOnboarding) {
                        Label {
                            Text(.authOnboardingCompleteButton)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle())
                    .disabled(isWorking)

                    Button(action: onSignOut) {
                        Text(.authOnboardingSignOutButton)
                    }
                    .buttonStyle(PaeoniaQuietButtonStyle())
                    .disabled(isWorking)
                }
            }
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
            Text(.authSignedInTestAccountCaption)
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
