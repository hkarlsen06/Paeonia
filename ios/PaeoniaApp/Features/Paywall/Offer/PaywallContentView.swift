import SwiftUI

/// The scrolling part of the paywall: what Paeonia is, what you get, and the plans.
/// It cascades in under the logo like the profile screen before it.
struct PaywallContentView: View {
    let audience: PaywallAudience
    let plans: [PaywallPlanOption]
    let isLoadingPlans: Bool
    let showsTrialReminder: Bool
    @Binding var billingPeriod: PaeoniaBillingPeriod

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            header
                .screenEntrance(order: 1)

            PaywallFeatureList()
                .screenEntrance(order: 2)

            VStack(spacing: PaeoniaSpacing.space12) {
                PaywallPlanPicker(plans: plans, isLoading: isLoadingPlans, selection: $billingPeriod)

                if showsTrialReminder {
                    trialReminder
                }
            }
            .screenEntrance(order: 3)
        }
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            if let headline = audience.headline {
                Text(headline)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(audience.message)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private var trialReminder: some View {
        Label {
            Text(.paywallTrialReminder)
        } icon: {
            Image(systemName: "bell.fill")
                .foregroundStyle(.paeoniaAccentPrimary)
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaeoniaSpacing.space4)
    }
}

/// What a subscription opens, one line per feature. The same features the welcome
/// screen describes, kept short here so the plans stay in view.
private struct PaywallFeatureList: View {
    private let features: [(systemImage: String, title: LocalizedStringResource)] = [
        ("scribble.variable", .welcomeFeatureDrawingTitle),
        ("bubble.left.and.bubble.right.fill", .welcomeFeatureQuestionsTitle),
        ("photo.on.rectangle.angled", .welcomeFeatureMemoriesTitle),
        ("calendar.badge.clock", .welcomeFeatureMilestonesTitle),
    ]

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            ForEach(features, id: \.systemImage) { feature in
                HStack(spacing: PaeoniaSpacing.space12) {
                    Image(systemName: feature.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .frame(width: iconSize, height: iconSize)
                        .background(.paeoniaAccentPrimary.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)

                    Text(feature.title)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaeoniaSpacing.space4)
    }
}
