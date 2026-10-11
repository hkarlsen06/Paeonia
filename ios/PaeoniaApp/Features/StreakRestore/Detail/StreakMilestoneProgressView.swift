import SwiftUI

/// The streak sheet's milestone block: how far the couple is from the next
/// milestone, and a row of badges. Earned badges stay lit after a break, because
/// they follow the longest streak.
struct StreakMilestoneProgressView: View {
    let currentCount: Int
    let longestCount: Int

    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 34

    private var nextMilestone: Int { StreakMilestones.next(after: currentCount) }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            VStack(spacing: PaeoniaSpacing.space8) {
                HStack {
                    Text(.streakDetailNextMilestoneLabel)
                        .foregroundStyle(.paeoniaTextSecondary)
                    Spacer()
                    Text(.streakDetailNextMilestoneDays(nextMilestone))
                        .foregroundStyle(.paeoniaTextPrimary)
                        .fontWeight(.semibold)
                }
                .font(PaeoniaTypography.caption)

                ProgressView(value: StreakMilestones.progress(toward: nextMilestone, from: currentCount))
                    .tint(.paeoniaAccentPrimary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: PaeoniaSpacing.space8) {
                ForEach(StreakMilestones.badges(currentCount: currentCount, longestCount: longestCount)) { badge in
                    badgeView(badge)
                }
            }
        }
    }

    private func badgeView(_ badge: StreakMilestoneBadge) -> some View {
        Text(badge.days, format: .number)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .monospacedDigit()
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .foregroundStyle(badgeColor(badge))
            .frame(width: badgeSize, height: badgeSize)
            .background {
                Circle()
                    .fill(badge.isEarned ? Color.paeoniaInkGold.opacity(0.12) : .clear)
                Circle()
                    .strokeBorder(
                        badgeColor(badge).opacity(badge.isEarned || badge.isNext ? 1 : 0.4),
                        style: StrokeStyle(lineWidth: 1.5, dash: badge.isNext && !badge.isEarned ? [3, 3] : [])
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                badge.isEarned
                    ? Text(.streakDetailMilestoneReachedAccessibility(badge.days))
                    : Text(.streakDetailMilestoneNotReachedAccessibility(badge.days))
            )
    }

    private func badgeColor(_ badge: StreakMilestoneBadge) -> Color {
        if badge.isEarned { return .paeoniaInkGold }
        return badge.isNext ? .paeoniaAccentPrimary : .paeoniaTextTertiary
    }
}

#if DEBUG
#Preview {
    StreakMilestoneProgressView(currentCount: 12, longestCount: 12)
        .padding()
        .background(.paeoniaSurfacePrimary)
        .preferredColorScheme(.dark)
}
#endif
