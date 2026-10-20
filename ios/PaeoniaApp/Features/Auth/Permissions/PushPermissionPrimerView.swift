import SwiftUI

/// A one-benefit explanation shown before iOS asks for notification permission.
/// After "Not now" the app asks once more, on a later day, and never again after
/// that (`RootPairingPermissionPrimerCoordinator`).
struct PushPermissionPrimerView: View {
    enum Ask {
        /// The first ask, after the person first sends their partner something.
        case afterSharing
        /// The one later ask, right after an answer the partner has not answered yet.
        case whileWaitingForPartner
    }

    let ask: Ask
    let partnerName: String
    let onEnable: () -> Void
    let onNotNow: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            primerContent(minHeight: proxy.size.height)
        }
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }

    private func primerContent(minHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space24)
                primerMessage
                Spacer(minLength: PaeoniaSpacing.space32)
                actions
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space24)
            .frame(minHeight: minHeight)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var primerMessage: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Image(systemName: "bell.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space12) {
                Text(title)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(message)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: LocalizedStringResource {
        switch ask {
        case .afterSharing:
            .notificationsPermissionPrimerTitle
        case .whileWaitingForPartner:
            .notificationsPermissionPrimerWaitingTitle(partnerName)
        }
    }

    private var message: LocalizedStringResource {
        switch ask {
        case .afterSharing:
            .notificationsPermissionPrimerMessage(partnerName)
        case .whileWaitingForPartner:
            .notificationsPermissionPrimerWaitingMessage(partnerName)
        }
    }

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button(action: onEnable) {
                Text(.notificationsPermissionPrimerEnable)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())

            Button(action: onNotNow) {
                Text(.notificationsPermissionPrimerNotNow)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
        }
    }
}

#if DEBUG
#Preview {
    Color.paeoniaBackgroundPrimary
        .sheet(isPresented: .constant(true)) {
            PushPermissionPrimerView(
                ask: .afterSharing,
                partnerName: "Riley",
                onEnable: {},
                onNotNow: {}
            )
        }
        .preferredColorScheme(.dark)
}

#Preview("While waiting for the partner") {
    Color.paeoniaBackgroundPrimary
        .sheet(isPresented: .constant(true)) {
            PushPermissionPrimerView(
                ask: .whileWaitingForPartner,
                partnerName: "Riley",
                onEnable: {},
                onNotNow: {}
            )
        }
        .preferredColorScheme(.dark)
}
#endif
