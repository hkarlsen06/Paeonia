import SwiftUI

/// The countdown to the couple's next milestone on the Us tab. Countdown is not a
/// tab of its own — it lives here as a derived anniversary/monthly milestone.
///
/// The milestone name, day count, and date are placeholder values for now. They
/// will be computed from the relationship date once milestone math is wired up.
struct MilestoneCountdownCard: View {
    // Placeholders until milestone math is wired up.
    private static let placeholderMilestone = "Your 6-month milestone"
    private static let placeholderDays = 12
    private static let placeholderDate = "Saturday, 8 July"

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                PaeoniaCardEyebrow(.homeMilestoneEyebrow)

                Text(verbatim: Self.placeholderMilestone)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
                    Text(Self.placeholderDays, format: .number)
                        .font(PaeoniaTypography.countdownNumber)
                        .foregroundStyle(.paeoniaAccentPrimary)

                    Text(.homeMilestoneDayUnit)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                .padding(.top, PaeoniaSpacing.space4)

                Text(verbatim: Self.placeholderDate)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
    }
}

#if DEBUG
#Preview {
    MilestoneCountdownCard()
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
