import SwiftUI

/// A calm, read-only look at the couple's daily-challenge streak: the live flame and
/// day count, their longest run so far, and a short, forgiving note on how it works.
///
/// Opened by tapping the streak badge while the streak is healthy. A broken streak
/// opens `StreakRestoreView` (the paid buy-it-back offer) instead, so this sheet stays
/// purely informative and never sells anything.
struct StreakDetailView: View {
    let streak: CoupleStreak
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Spacer()

            // A gently alive flame — breathing liquid and a soft flicker — without the
            // count-up celebration or its haptics. This is a quiet peek, not the moment
            // a streak is earned.
            PaeoniaStreakFlame(count: streak.currentCount, playsCelebration: false, ambientMotion: true)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.streakDetailTitle)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.streakDetailMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            // Their record, shown only when it beats the current run so it adds
            // something the hero flame doesn't already say.
            if streak.longestCount > streak.currentCount {
                longestStat
            }

            Spacer()

            Button(action: onClose) {
                Text(.streakDetailDone)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaSurfacePrimary)
    }

    private var longestStat: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(streak.longestCount, format: .number)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.paeoniaTextPrimary)

            Text(.streakDetailLongestLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("With a record") {
    StreakDetailView(
        streak: CoupleStreak(
            currentCount: 6,
            longestCount: 21,
            lastQualifiedDate: "2026-06-28",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("At their best") {
    StreakDetailView(
        streak: CoupleStreak(
            currentCount: 12,
            longestCount: 12,
            lastQualifiedDate: "2026-06-28",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil
        )
    )
    .preferredColorScheme(.dark)
}
#endif
