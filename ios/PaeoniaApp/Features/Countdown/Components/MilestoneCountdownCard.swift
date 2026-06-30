import SwiftUI

/// The countdown to the couple's next milestone on the Us tab. Countdown is not a
/// tab of its own — it lives here as a derived value computed from when the couple
/// started (`couples.started_on`).
///
/// The card reads as one sentence the number leads: "25 days until · your first
/// month together", with the date underneath. Leading with the day count makes the
/// countdown the hero (instead of competing with the milestone name) and folds the
/// "counting down to" framing into the same line, so there's no separate overline.
/// The milestone, its day count, and its date all come from
/// `RelationshipMilestoneCalculator`, so it stays current: a new couple counts down
/// to their first month, while a couple of years counts down to their next
/// anniversary or their next round day count.
struct MilestoneCountdownCard: View {
    /// The couple's start date as an `yyyy-MM-dd` string (`couples.started_on`).
    let startedOn: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var milestone: RelationshipMilestone? {
        guard let startedOn else { return nil }
        // Built per read so it reflects the current calendar/time zone, and so the
        // day count refreshes whenever the card re-renders.
        return RelationshipMilestoneCalculator().nextMilestone(startedOn: startedOn)
    }

    var body: some View {
        if let milestone {
            card(for: milestone)
        } else {
            // `started_on` is set when a couple pairs, so this is effectively
            // unreachable for an active relationship. Hold the square footprint so
            // the side-by-side tile grid doesn't reflow if it ever is missing.
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private func card(for milestone: RelationshipMilestone) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            countdown(for: milestone)

            // The target date sits right under the count, so "25 days until" and
            // "Saturday 25 July" read together as the countdown.
            Text(milestone.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)

            Spacer(minLength: PaeoniaSpacing.space8)

            // The milestone name anchors the bottom, lining up with the
            // neighbouring tiles' captions.
            Text(Self.subject(for: milestone.kind))
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Match the side-by-side tiles in the same row: same fill, square footprint,
        // rounded corners, hairline stroke, and lift as the widget drawing tile.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(PaeoniaSpacing.space16)
        .aspectRatio(1, contentMode: .fit)
        .background(.paeoniaBackgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func countdown(for milestone: RelationshipMilestone) -> some View {
        if milestone.daysRemaining == 0 {
            // On the day itself there's nothing to count down — say so instead of "0".
            Text(.homeMilestoneToday)
                .font(PaeoniaTypography.countdownNumber)
                .foregroundStyle(.paeoniaAccentPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        } else {
            // Number leads as the hero; "days until" carries into the subject line.
            ViewThatFits(in: .horizontal) {
                countdownLine(for: milestone)

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(milestone.daysRemaining, format: .number)
                        .font(PaeoniaTypography.countdownNumber)
                        .foregroundStyle(.paeoniaAccentPrimary)

                    Text(milestone.daysRemaining == 1 ? .homeMilestoneUntilOne : .homeMilestoneUntil)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(2)
                }
            }
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        }
    }

    private func countdownLine(for milestone: RelationshipMilestone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space4) {
            Text(milestone.daysRemaining, format: .number)
                .font(PaeoniaTypography.countdownNumber)
                .foregroundStyle(.paeoniaAccentPrimary)

            // Same size as the subject line below so "… days until <milestone>"
            // reads as one sentence, leaving the number as the only large element.
            Text(milestone.daysRemaining == 1 ? .homeMilestoneUntilOne : .homeMilestoneUntil)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .lineLimit(1)
    }

    /// The milestone name shown at the bottom of the card (e.g. "Your first month together").
    private static func subject(for kind: RelationshipMilestone.Kind) -> LocalizedStringResource {
        switch kind {
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

#if DEBUG
#Preview {
    HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
        MilestoneCountdownCard(startedOn: "2026-01-08")
        Color.clear
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
