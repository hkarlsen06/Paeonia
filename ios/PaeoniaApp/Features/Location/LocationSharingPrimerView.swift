import SwiftUI

/// Explains Paeonia's deliberately narrow location behavior before iOS asks
/// for access. Choosing "Not now" is final for automatic prompts in this
/// relationship; sharing remains available from Settings.
struct LocationSharingPrimerView: View {
    let partnerName: String
    let onShare: () -> Void
    let onNotNow: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: PaeoniaSpacing.space24) {
                    Spacer(minLength: PaeoniaSpacing.space24)
                    message
                    Spacer(minLength: PaeoniaSpacing.space32)
                    actions
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.space24)
            }
            .scrollIndicators(.hidden)
        }
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }

    private var message: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Image(systemName: "location.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space12) {
                Text(.locationPermissionPrimerTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.locationPermissionPrimerMessage(partnerName))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button(action: onShare) {
                Text(.locationPermissionPrimerShare)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())

            Button(action: onNotNow) {
                Text(.locationPermissionPrimerNotNow)
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
            LocationSharingPrimerView(
                partnerName: "Robin",
                onShare: {},
                onNotNow: {}
            )
        }
        .preferredColorScheme(.dark)
}
#endif
