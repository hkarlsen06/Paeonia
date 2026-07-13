import SwiftUI

struct PaywallBillingSelector: View {
    @Binding var billingPeriod: PaeoniaBillingPeriod

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            billingOption(.monthly)
            billingOption(.yearly)
        }
        .padding(PaeoniaSpacing.space4)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.paywallBillingPicker))
    }

    private func billingOption(_ period: PaeoniaBillingPeriod) -> some View {
        let isSelected = billingPeriod == period

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                billingPeriod = period
            }
        } label: {
            VStack(spacing: 1) {
                Text(period.displayName)
                    .font(isSelected ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
                    .foregroundStyle(isSelected ? .paeoniaTextPrimary : .paeoniaTextTertiary)

                if period == .yearly {
                    Text(.paywallBestValue)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(isSelected ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(isSelected ? Color.paeoniaBackgroundElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension PaeoniaBillingPeriod {
    var displayName: LocalizedStringResource {
        switch self {
        case .monthly:
            .paywallBillingMonthly
        case .yearly:
            .paywallBillingYearly
        }
    }
}
