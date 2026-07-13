import Foundation
import StoreKit

struct PaywallPresentation {
    let billingPeriod: PaeoniaBillingPeriod
    let product: Product?
    let freeTrial: PaeoniaFreeTrial?
    let isPurchasing: Bool
    let isLoading: Bool

    var primaryButtonIsEnabled: Bool {
        product != nil && !isPurchasing && !isLoading
    }

    var hasFreeTrial: Bool {
        freeTrial != nil
    }

    var primaryButtonTitle: LocalizedStringResource {
        if isPurchasing {
            return .paywallCtaPurchasing
        }

        if freeTrial != nil {
            return .paywallCtaFreeTrial
        }

        return .paywallCtaSubscribe
    }

    var priceLine: String {
        guard let product else {
            return String(localized: .paywallPriceLoading)
        }

        let renewal = "\(compactDisplayPrice(for: product))\(String(localized: compactPeriodLabel))"
        guard let freeTrial else {
            return renewal
        }

        let freeWord = String(localized: .paywallTrialFreeWord)
        let then = String(localized: .paywallTrialThen)
            .lowercased(with: Locale.current)

        return "\(freeTrial.localizedDurationText) \(freeWord), \(then) \(renewal)"
    }

    var timelineItems: [PaywallTimelineItem] {
        if freeTrial != nil {
            return [
                PaywallTimelineItem(
                    id: "today",
                    title: String(localized: .paywallTimelineToday),
                    message: String(localized: .paywallTimelineTodayBody),
                    systemImage: "lock.open.fill",
                    isActive: true
                ),
                PaywallTimelineItem(
                    id: "reminder",
                    title: trialTimelineDayTitle(day: trialReminderDay),
                    message: String(localized: .paywallTimelineReminderBody),
                    systemImage: "bell.fill",
                    isActive: false
                ),
                PaywallTimelineItem(
                    id: "charge",
                    title: trialTimelineDayTitle(day: trialDurationDay),
                    message: String(localized: .paywallTimelineChargeBody),
                    systemImage: "calendar.badge.clock",
                    isActive: false
                ),
            ]
        }

        return [
            PaywallTimelineItem(
                id: "today",
                title: String(localized: .paywallTimelineToday),
                message: String(localized: .paywallTimelineTodayBody),
                systemImage: "lock.open.fill",
                isActive: true
            ),
            PaywallTimelineItem(
                id: "manage",
                title: String(localized: .paywallTimelineManage),
                message: String(localized: .paywallTimelineManageBody),
                systemImage: "gearshape.fill",
                isActive: false
            ),
            PaywallTimelineItem(
                id: "renewal",
                title: String(localized: .paywallTimelineRenewal),
                message: String(localized: renewalTimelineBody),
                systemImage: "calendar",
                isActive: false
            ),
        ]
    }

    private var trialDurationDay: Int {
        freeTrial?.approximateDayCount ?? 14
    }

    private var trialReminderDay: Int {
        max(trialDurationDay - 2, 1)
    }

    private func trialTimelineDayTitle(day: Int) -> String {
        "\(String(localized: .paywallTimelineDayPrefix)) \(day)"
    }

    private var renewalTimelineBody: LocalizedStringResource {
        switch billingPeriod {
        case .monthly:
            .paywallTimelineRenewalMonthlyBody
        case .yearly:
            .paywallTimelineRenewalYearlyBody
        }
    }

    private var compactPeriodLabel: LocalizedStringResource {
        switch billingPeriod {
        case .monthly:
            .paywallPeriodMonthlyCompact
        case .yearly:
            .paywallPeriodYearlyCompact
        }
    }

    private func compactDisplayPrice(for product: Product) -> String {
        var price = product.price
        var rounded = Decimal()
        NSDecimalRound(&rounded, &price, 0, .plain)

        if rounded == product.price {
            return product.price.formatted(product.priceFormatStyle.precision(.fractionLength(0)))
        }

        return product.displayPrice
    }
}
