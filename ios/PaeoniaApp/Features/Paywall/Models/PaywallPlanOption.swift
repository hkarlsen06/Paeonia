import Foundation

/// One plan card on the paywall.
struct PaywallPlanOption: Identifiable, Equatable {
    let period: PaeoniaBillingPeriod
    /// `nil` until the App Store has answered.
    let price: PaywallPrice?
    let freeTrial: PaeoniaFreeTrial?
    /// Yearly only: what the year works out to per month.
    let monthlyEquivalent: PaywallPrice?
    /// Yearly only: how much less a year costs than twelve monthly payments.
    let savingsPercent: Int?

    var id: PaeoniaBillingPeriod { period }

    /// Yearly first, so the cheaper plan is the first one people read.
    static func options(monthly: PaywallPresentation, yearly: PaywallPresentation) -> [PaywallPlanOption] {
        [
            PaywallPlanOption(
                period: .yearly,
                price: yearly.price,
                freeTrial: yearly.freeTrial,
                monthlyEquivalent: yearly.price.map {
                    PaywallPrice(amount: $0.amount / 12, format: $0.format)
                },
                savingsPercent: savingsPercent(monthly: monthly.price?.amount, yearly: yearly.price?.amount)
            ),
            PaywallPlanOption(
                period: .monthly,
                price: monthly.price,
                freeTrial: monthly.freeTrial,
                monthlyEquivalent: nil,
                savingsPercent: nil
            ),
        ]
    }

    /// Rounded down so the badge never promises more than the real saving. Small
    /// savings get no badge.
    static func savingsPercent(monthly: Decimal?, yearly: Decimal?) -> Int? {
        guard let monthly, let yearly else {
            return nil
        }

        let twelveMonths = monthly * 12
        guard twelveMonths > 0, yearly < twelveMonths else {
            return nil
        }

        let saving = NSDecimalNumber(decimal: (twelveMonths - yearly) / twelveMonths * 100).doubleValue
        let percent = Int(saving.rounded(.down))
        return percent >= 5 ? percent : nil
    }
}
