import SwiftUI

/// A quiet, copy-free launch state that picks up where the system launch screen
/// leaves off. It is often visible only for a split second, so it should not try
/// to explain work that the user will not have time to read.
struct AuthLaunchingView: View {
    var body: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary

            Image(.paeoniaLaunchPetalMark)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.appStateLaunching))
    }
}

/// Shown while the account is being deleted. Like the other notices, a spinner and
/// the text sit a little above the middle of the screen.
struct AuthDeletingAccountView: View {
    var body: some View {
        PaeoniaScreenScroll {
            VStack(spacing: PaeoniaSpacing.space20) {
                ProgressView()
                    .controlSize(.large)
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
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

struct RelationshipEndedNoticeView: View {
    let isWorking: Bool
    let onAcknowledge: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        PaeoniaScreenScroll {
            notice
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onAcknowledge) {
                Text(.authRelationshipEndedAcknowledgeButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isWorking))
            .padding(.top, PaeoniaSpacing.space12)
        }
    }

    private var notice: some View {
        VStack(spacing: PaeoniaSpacing.space20) {
            Image(systemName: "heart.slash.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.authRelationshipEndedTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(.authRelationshipEndedMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    // Keep the supporting copy a touch narrower than the title so
                    // the two wrapped lines stay balanced instead of a long line
                    // followed by a short orphan.
                    .padding(.horizontal, PaeoniaSpacing.space24)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
