import Foundation

extension RelationshipMilestone.Kind {
    /// The milestone's user-facing name (e.g. "Your first month together"), shared
    /// by the Us-tab countdown card and the milestone timeline sheet.
    var displayName: LocalizedStringResource {
        switch self {
        case .firstMonth:
            .homeMilestoneTitleFirstMonth
        case let .months(months):
            .homeMilestoneTitleMonths(months.formatted())
        case .halfYear:
            .homeMilestoneTitleHalfYear
        case .firstAnniversary:
            .homeMilestoneTitleFirstAnniversary
        case let .years(years):
            .homeMilestoneTitleYears(years.formatted())
        case let .days(days):
            .homeMilestoneTitleDays(days.formatted())
        }
    }
}
