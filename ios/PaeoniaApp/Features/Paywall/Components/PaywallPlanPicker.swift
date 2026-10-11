import SwiftUI

/// The plans as cards, each with its own price, so both can be compared without
/// switching. Prices show as placeholders until the App Store answers.
struct PaywallPlanPicker: View {
    let plans: [PaywallPlanOption]
    let isLoading: Bool
    @Binding var selection: PaeoniaBillingPeriod

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            ForEach(plans) { plan in
                PaywallPlanCard(
                    plan: plan,
                    isSelected: plan.period == selection,
                    isLoading: isLoading
                ) {
                    withAnimation(reduceMotion ? nil : PaeoniaMotion.buttonPress) {
                        selection = plan.period
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.paywallBillingPicker))
    }
}

private struct PaywallPlanCard: View {
    let plan: PaywallPlanOption
    let isSelected: Bool
    let isLoading: Bool
    let onSelect: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
    }

    var body: some View {
        Button(action: onSelect) {
            label
                .padding(PaeoniaSpacing.space16)
                .background(isSelected ? Color.paeoniaSurfacePrimary : Color.paeoniaSurfaceSecondary, in: shape)
                .overlay {
                    shape.strokeBorder(
                        isSelected ? Color.paeoniaAccentPrimary : Color.paeoniaSurfacePressed,
                        lineWidth: isSelected ? 2 : PaeoniaRadius.strokeDefault
                    )
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                HStack(spacing: PaeoniaSpacing.space8) {
                    Text(plan.period.planName)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)

                    if let savingsPercent = plan.savingsPercent {
                        savingsBadge(savingsPercent)
                    }
                }

                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            priceColumn
        }
    }

    private var priceColumn: some View {
        VStack(alignment: .trailing, spacing: PaeoniaSpacing.space2) {
            Text(plan.price?.text ?? "000 kr")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .monospacedDigit()

            Text(plan.period.perPeriodLabel)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .redacted(reason: plan.price == nil ? .placeholder : [])
        // An unavailable price says so on the button below. Here it only leaves out
        // a placeholder that would never fill in.
        .opacity(plan.price == nil && !isLoading ? 0 : 1)
    }

    /// "14 days free" and, for the year, what it works out to per month.
    private var detail: String? {
        let trial = plan.freeTrial.map {
            "\($0.localizedDurationText) \(String(localized: .paywallTrialFreeWord))"
        }
        let perMonth = plan.monthlyEquivalent.map {
            "\($0.text)\(String(localized: .paywallPeriodMonthlyCompact))"
        }
        let parts = [trial, perMonth].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func savingsBadge(_ percent: Int) -> some View {
        let percentText = (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
        return Text(.paywallPlanSave(percentText))
            .font(PaeoniaTypography.caption.weight(.bold))
            .foregroundStyle(.paeoniaTextInverse)
            .padding(.horizontal, PaeoniaSpacing.space8)
            .padding(.vertical, PaeoniaSpacing.space2)
            .background(.paeoniaAccentPrimary, in: Capsule(style: .continuous))
    }
}
