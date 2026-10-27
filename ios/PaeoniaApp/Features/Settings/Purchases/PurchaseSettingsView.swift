import StoreKit
import SwiftUI

/// What Paeonia has on record for the subscription, with Apple's management sheet
/// and purchase restore below it. Every change goes through Apple, so the record
/// is there for people to compare with what Apple shows.
struct PurchaseSettingsView: View {
    let viewModel: SettingsViewModel
    /// Lets the root re-resolve access once a restore finds a subscription.
    let onPurchasesRestored: @MainActor @Sendable () async -> Void

    @State private var isManagingSubscription = false

    var body: some View {
        Form {
            detailsSection
                .listRowBackground(Color.paeoniaSurfacePrimary)

            Section {
                // Apple's own sheet, so changing or cancelling never leaves the app.
                // Apple shows only the payer's own subscriptions there, so the
                // partner who is covered has nothing to manage.
                if partnerPays == nil {
                    SettingsActionRow(
                        title: .paywallManageSubscription,
                        systemImage: "creditcard"
                    ) {
                        isManagingSubscription = true
                    }
                }

                SettingsActionRow(
                    title: viewModel.isRestoringPurchases
                        ? .settingsPurchasesRestoring
                        : .paywallRestorePurchases,
                    systemImage: "arrow.clockwise",
                    isBusy: viewModel.isRestoringPurchases,
                    action: restorePurchases
                )
            } footer: {
                Text(.paywallOneSubscription)
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsPurchasesSectionTitle))
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .task {
            await viewModel.loadSubscriptionDetails()
        }
        .task(id: viewModel.subscriptionDetailsState) {
            if case .loaded = viewModel.subscriptionDetailsState {
                await DeliveredNotifications.clear(types: [
                    "subscription_trial_reminder", "subscription_payment_failed", "subscription_ending"
                ])
            }
        }
        .refreshable {
            await viewModel.loadSubscriptionDetails()
        }
    }

    private var detailsSection: some View {
        Section {
            switch viewModel.subscriptionDetailsState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case let .failed(failure):
                // Only a phone without a connection is told to check it.
                Text(failure == .offline ? .settingsPurchasesDetailsFailed : .settingsPurchasesDetailsFailedLater)
                    .foregroundStyle(.paeoniaTextSecondary)
            case let .loaded(details):
                detailRows(details)
            }
        } header: {
            Text(.settingsPurchasesDetailsHeader)
        } footer: {
            // Apple only lets the person who pays manage the subscription, so the
            // partner who is covered gets pointed at them instead.
            if let partnerPays {
                Text(.settingsPurchasesDetailsFooterPartnerPays(partnerPays))
            } else {
                Text(.settingsPurchasesDetailsFooter)
            }
        }
    }

    /// The paying partner's name when the partner pays, otherwise nil.
    private var partnerPays: String? {
        guard case let .loaded(details) = viewModel.subscriptionDetailsState,
              case let .partner(name) = details.payer
        else {
            return nil
        }
        return name ?? String(localized: .settingsPurchasesDetailsPaidByPartnerFallback)
    }

    @ViewBuilder
    private func detailRows(_ details: SubscriptionDetails) -> some View {
        LabeledContent {
            Text(statusText(details.status))
        } label: {
            Text(.settingsPurchasesDetailsStatus)
        }

        if let billingPeriod = details.billingPeriod {
            LabeledContent {
                Text(billingPeriod == .yearly ? .paywallBillingYearly : .paywallBillingMonthly)
            } label: {
                Text(.settingsPurchasesDetailsPlan)
            }
        }

        if let periodEnd = details.periodEnd {
            LabeledContent {
                Text(periodEnd, format: .dateTime.day().month(.wide).year())
            } label: {
                Text(periodEndLabel(status: details.status, periodEnd: periodEnd))
            }
        }

        if let payer = details.payer {
            LabeledContent {
                switch payer {
                case .you:
                    Text(.settingsPurchasesDetailsPaidByYou)
                case let .partner(name?):
                    Text(name)
                case .partner(nil):
                    Text(.settingsPurchasesDetailsPaidByPartnerFallback)
                }
            } label: {
                Text(.settingsPurchasesDetailsPaidBy)
            }
        }
    }

    private func periodEndLabel(status: SubscriptionDetails.Status, periodEnd: Date) -> LocalizedStringResource {
        if status == .freeTrial {
            return .settingsPurchasesDetailsTrialEnds
        }
        return periodEnd > .now ? .settingsPurchasesDetailsAccessUntil : .settingsPurchasesDetailsEndedOn
    }

    private func statusText(_ status: SubscriptionDetails.Status) -> LocalizedStringResource {
        switch status {
        case .active:
            .settingsPurchasesDetailsStatusActive
        case .freeTrial:
            .settingsPurchasesDetailsStatusFreeTrial
        case .paymentProblem:
            .settingsPurchasesDetailsStatusPaymentProblem
        case .ended:
            .settingsPurchasesDetailsStatusEnded
        case .refunded:
            .settingsPurchasesDetailsStatusRefunded
        case .lifetime:
            .settingsPurchasesDetailsStatusLifetime
        case .freeAccess:
            .settingsPurchasesDetailsStatusFreeAccess
        case .none:
            .settingsPurchasesDetailsStatusNone
        }
    }

    private func restorePurchases() {
        Task { @MainActor in
            if await viewModel.restorePurchases() {
                await onPurchasesRestored()
            }
        }
    }
}

#Preview {
    NavigationStack {
        PurchaseSettingsView(viewModel: SettingsViewModel(), onPurchasesRestored: {})
    }
    .preferredColorScheme(.dark)
}
