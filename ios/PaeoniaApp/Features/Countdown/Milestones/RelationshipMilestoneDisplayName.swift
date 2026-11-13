import Foundation

extension RelationshipMilestone.Kind {
    /// The milestone's user-facing name (e.g. "Your first month together"), shared
    /// by the Us tab countdown card and the milestone timeline sheet.
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

    /// The milestone's short name on the Us tab calendar tile, without "together" (e.g.
    /// "2 months"), so the line under the calendar fits on one line.
    var shortName: LocalizedStringResource {
        switch self {
        case .firstMonth:
            .homeMilestoneTimelineMonthsOne
        case let .months(months):
            .homeMilestoneTimelineMonths(months.formatted())
        case .halfYear:
            .homeMilestoneShortHalfYear
        case .firstAnniversary:
            .homeMilestoneTimelineYearsOne
        case let .years(years):
            .homeMilestoneTimelineYears(years.formatted())
        case let .days(days):
            .homeMilestoneTimelineDays(days.formatted())
        }
    }
}
