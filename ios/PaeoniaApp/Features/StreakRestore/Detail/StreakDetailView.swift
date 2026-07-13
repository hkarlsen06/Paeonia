import SwiftUI

/// A calm, read-only look at the couple's connection streak: the live flame and
/// day count, their longest run so far, and a short, forgiving note on how it works.
///
/// Opened by tapping the streak badge while the streak is healthy. A broken streak
/// opens `StreakRestoreView` (the paid buy-it-back offer) instead, so this sheet stays
/// purely informative and never sells anything. The restore flow also reuses this
/// surface with celebratory copy once a purchase brings the streak back.
struct StreakDetailView: View {
    let streak: CoupleStreak
    var title: LocalizedStringResource = .streakDetailTitle
    var message: LocalizedStringResource = .streakDetailMessage
    var playsCelebration = false
    var ambientMotion = true
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCelebrationDetails = false

    private var shouldShowDetails: Bool {
        !playsCelebration || showCelebrationDetails
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Spacer()

            PaeoniaStreakFlame(
                count: streak.currentCount,
                playsCelebration: playsCelebration,
                ambientMotion: ambientMotion && !playsCelebration
            )

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(title)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(message)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .modifier(StreakDetailReveal(shown: shouldShowDetails))

            // Their record, shown only when it beats the current run so it adds
            // something the hero flame doesn't already say.
            if streak.longestCount > streak.currentCount {
                longestStat
                    .modifier(StreakDetailReveal(shown: shouldShowDetails))
            }

            Spacer()

            Button(action: onClose) {
                Text(.streakDetailDone)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            .modifier(StreakDetailReveal(shown: shouldShowDetails))
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaSurfacePrimary)
        .onAppear(perform: revealCelebrationDetails)
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

    private func revealCelebrationDetails() {
        guard playsCelebration, !showCelebrationDetails else { return }
        if reduceMotion {
            showCelebrationDetails = true
        } else {
            withAnimation(PaeoniaMotion.meaningfulMoment.delay(0.28)) {
                showCelebrationDetails = true
            }
        }
    }
}

/// Fades and lifts the streak sheet's supporting copy and actions in after the
/// flame has had a beat to land.
private struct StreakDetailReveal: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : PaeoniaSpacing.space12)
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

#Preview("Restored") {
    StreakDetailView(
        streak: CoupleStreak(
            currentCount: 30,
            longestCount: 30,
            lastQualifiedDate: "2026-06-28",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil
        ),
        title: .streakRestoreSuccessTitle,
        message: .streakRestoreSuccessMessage,
        playsCelebration: true,
        ambientMotion: false
    )
    .preferredColorScheme(.dark)
}
#endif
