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
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            PaeoniaCardEyebrow(.homeMilestoneEyebrow)

            Text(verbatim: Self.placeholderMilestone)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: PaeoniaSpacing.space8)

            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space4) {
                Text(Self.placeholderDays, format: .number)
                    .font(PaeoniaTypography.countdownNumber)
                    .foregroundStyle(.paeoniaAccentPrimary)

                Text(.homeMilestoneDayUnit)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(verbatim: Self.placeholderDate)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        // Match the side-by-side tiles in the same row: square footprint, the same
        // rounded corners, hairline stroke, and lift as the widget tile.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(PaeoniaSpacing.space16)
        .aspectRatio(1, contentMode: .fit)
        .background(.paeoniaSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }
}

#if DEBUG
#Preview {
    HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
        MilestoneCountdownCard()
        Color.clear
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
