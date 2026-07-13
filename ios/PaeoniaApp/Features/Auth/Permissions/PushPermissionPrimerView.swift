import SwiftUI

/// A one-benefit explanation shown after pairing and before iOS asks for
/// notification permission. Either choice is final for automatic priming; the
/// app does not keep interrupting a user who chooses "Not now".
struct PushPermissionPrimerView: View {
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
            .frame(minHeight: minHeight)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space24)
        }
        .scrollIndicators(.hidden)
    }

    private var primerMessage: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Image(systemName: "bell.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space12) {
                Text(.notificationsPermissionPrimerTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.notificationsPermissionPrimerMessage(partnerName))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
                partnerName: "Riley",
                onEnable: {},
                onNotNow: {}
            )
        }
        .preferredColorScheme(.dark)
}
#endif
