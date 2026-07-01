import SwiftUI

struct PaywallBottomCTAView: View {
    let title: LocalizedStringResource
    let caption: LocalizedStringResource
    let isEnabled: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            primaryCTA
            captionLine
        }
        .padding(.horizontal, PaeoniaSpacing.space20)
        .padding(.top, PaeoniaSpacing.space24)
        .padding(.bottom, PaeoniaSpacing.space8)
        .background(barBackground)
    }

    private var primaryCTA: some View {
        Button(action: action) {
            HStack(spacing: PaeoniaSpacing.space8) {
                if isBusy {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityHidden(true)
                } else {
                    Text(title)
                        .font(PaeoniaTypography.button)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(isEnabled ? .paeoniaTextInverse : .paeoniaTextTertiary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(primaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isBusy)
    }

    private var captionLine: some View {
        Text(caption)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var primaryButtonBackground: LinearGradient {
        // Disabled uses an opaque, recessed fill (never translucent) so the
        // button reads as a solid disabled control rather than washing out.
        let enabledColors = [
            Color.paeoniaAccentPrimary,
            Color.paeoniaAccentSecondary,
        ]
        let disabledColors = [
            Color.paeoniaSurfaceSecondary,
            Color.paeoniaSurfaceSecondary,
        ]

        return LinearGradient(
            colors: isEnabled ? enabledColors : disabledColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var barBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color.paeoniaSurfacePrimary.opacity(0), location: 0),
                .init(color: Color.paeoniaSurfacePrimary.opacity(0.98), location: 0.22),
                .init(color: Color.paeoniaSurfacePrimary, location: 0.38),
                .init(color: Color.paeoniaSurfacePrimary, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
