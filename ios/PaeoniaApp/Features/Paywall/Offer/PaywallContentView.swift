import SwiftUI

/// The scrolling part of the paywall: what Paeonia is, what you get, and the plans.
/// It cascades in like the profile screen before it, once
/// `isEntranceReady` says the prices are in or have taken too long.
struct PaywallContentView: View {
    let audience: PaywallAudience
    let plans: [PaywallPlanOption]
    let isLoadingPlans: Bool
    let trialReminder: PaywallTrialReminder?
    let isEntranceReady: Bool
    @Binding var billingPeriod: PaeoniaBillingPeriod

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            header
                .screenEntrance(order: 1, isReady: isEntranceReady)

            PaywallFeatureList()
                .screenEntrance(order: 2, isReady: isEntranceReady)

            // Someone whose payment Apple is still retrying fixes it in the App
            // Store, so there is nothing here to buy.
            if !audience.asksToUpdatePayment {
                plansSection
                    .screenEntrance(order: 3, isReady: isEntranceReady)
            }
        }
    }

    private var plansSection: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            PaywallPlanPicker(plans: plans, isLoading: isLoadingPlans, selection: $billingPeriod)

            if let trialReminder {
                trialReminderLine(trialReminder)
            }
        }
        // Prices that come in after the drop grow the cards instead of jumping.
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: isLoadingPlans)
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(audience.headline)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(audience.message)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func trialReminderLine(_ reminder: PaywallTrialReminder) -> some View {
        Label {
            switch reminder {
            case let .dated(trialEnd, reminderDay):
                Text(.paywallTrialReminderDated(Self.dayText(trialEnd), Self.dayText(reminderDay)))
            case .undated:
                Text(.paywallTrialReminder)
            }
        } icon: {
            Image(systemName: "bell.fill")
                .foregroundStyle(.paeoniaAccentPrimary)
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaeoniaSpacing.space4)
    }

    /// "7 November", or "7. november" in Norwegian.
    private static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
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
