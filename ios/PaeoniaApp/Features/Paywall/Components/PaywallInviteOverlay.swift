import SwiftUI

/// Owns the modal chrome around invite entry. The offer screen retains the join
/// state and async work; this component only keeps the dimmer, dismissal target,
/// and code form consistent.
struct PaywallInviteOverlay: View {
    @Binding var code: String
    var focus: FocusState<Bool>.Binding
    let isSubmitting: Bool
    let hasPendingInvite: Bool
    let onSubmit: () -> Void
    let onDismiss: () -> Void
    let onContinueWithoutInvite: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.3))
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityLabel(Text(.paywallInviteDismiss))
                .accessibilityAddTraits(.isButton)

            PaywallInviteCodeView(
                code: $code,
                focus: focus,
                isSubmitting: isSubmitting,
                onSubmit: onSubmit,
                onContinueWithoutInvite: hasPendingInvite ? onContinueWithoutInvite : nil
            )
            .padding(.horizontal, PaeoniaSpacing.space20)
        }
    }
}

struct PendingInvitePresentationID: Equatable {
    let code: String?
    let allowsInviteEntry: Bool
    let isPresentationReady: Bool
}

enum PaywallInviteConfirmation {
    static func title(for preview: PairingInvitePreview?) -> LocalizedStringResource {
        guard let inviterName = preview?.inviterDisplayName?.trimmedNonEmpty else {
            return .paywallInviteConfirmTitleFallback
        }

        return .paywallInviteConfirmTitle(inviterName)
    }

    static func message(for preview: PairingInvitePreview?) -> LocalizedStringResource {
        preview?.hasSafetyWarning == true
            ? .paywallInviteConfirmSafetyMessage
            : .paywallInviteConfirmMessage
    }
}
