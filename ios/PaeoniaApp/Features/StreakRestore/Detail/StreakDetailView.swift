import SwiftUI

/// A calm, read-only look at the couple's connection streak: the live flame and
/// day count, a short, forgiving note on how it works, who has done something
/// today, the milestone stem with their record, and whether their free streak
/// freeze is ready.
///
/// Opened by tapping the streak badge while the streak is healthy, and on a broken
/// streak's free save day, when it says how both partners bring it back today. A
/// broken streak past its save day opens `StreakRestoreView` (the paid buy-it-back
/// offer) instead, so this sheet stays purely informative and never sells anything.
/// The restore flow also reuses this surface with celebratory copy once a purchase
/// brings the streak back.
struct StreakDetailView: View {
    let streak: CoupleStreak
    /// Both partners, for the row about today. The restore celebration passes none.
    var people: StreakPeople?
    /// The count and its label under the flame already say what this is, so the
    /// sheet has no title of its own unless a moment needs one.
    var title: LocalizedStringResource?
    /// Overrides the default copy. Without it, a streak at zero invites the couple to
    /// start one and any other streak explains how the flame stays lit.
    var message: LocalizedStringResource?
    var playsCelebration = false
    var ambientMotion = true
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCelebrationDetails = false

    private var shouldShowDetails: Bool {
        !playsCelebration || showCelebrationDetails
    }

    /// The streak broke and both partners can still bring it back for free today.
    /// Custom copy, such as the restore celebration, is never about a save day.
    private var isSaveDay: Bool {
        message == nil && streak.isSavable
    }

    private var hasNotStarted: Bool {
        streak.currentCount == 0 && !isSaveDay
    }

    private var titleText: LocalizedStringResource? {
        isSaveDay ? .streakSaveTitle : title
    }

    private var messageText: LocalizedStringResource {
        if let message { return message }
        if isSaveDay { return .streakSaveMessage(streak.restorableCount) }
        return hasNotStarted ? .streakDetailEmptyMessage : .streakDetailMessage
    }

    /// Custom copy, such as the restore celebration, replaces the whole note, freeze line included.
    private var freezeNoteText: LocalizedStringResource? {
        guard message == nil, let note = streak.freezeNote() else { return nil }
        switch note {
        case .savedStreak:
            return .streakDetailFreezeSaved
        case .ready:
            return .streakDetailFreezeReady
        case .readyOn(let date):
            return .streakDetailFreezeReadyOn(date.formatted(.dateTime.day().month(.wide)))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space16) {
                hero

                heading
                    .modifier(StreakDetailReveal(shown: shouldShowDetails))

                notes
                    .modifier(StreakDetailReveal(shown: shouldShowDetails))

                Button(action: onClose) {
                    Text(.streakDetailDone)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                .modifier(StreakDetailReveal(shown: shouldShowDetails))
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space24)
            .paeoniaReadableWidth()
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .background(.paeoniaSurfacePrimary)
        // The app's petal shower draws under this sheet, so the stem's flowers need their own.
        .modifier(PaeoniaPetalShowerHost())
        .onAppear(perform: revealCelebrationDetails)
    }

    private var heading: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            if let titleText {
                Text(titleText)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
            }

            Text(messageText)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var hero: some View {
        if isSaveDay {
            // The cooled flame with the days that come back, as on the restore offer.
            PaeoniaStreakFlame(count: streak.restorableCount, isBroken: true)
        } else {
            PaeoniaStreakFlame(
                count: streak.currentCount,
                playsCelebration: playsCelebration,
                isFrozen: streak.freezeSavedStreak,
                ambientMotion: ambientMotion && !playsCelebration
            )
            // The flame has no empty level of its own, so a streak that has not started
            // is dimmed here instead of showing a fully lit "0".
            .saturation(hasNotStarted ? 0.15 : 1)
            .opacity(hasNotStarted ? 0.8 : 1)
        }
    }

    /// Today, the milestone stem and the freeze line. Custom copy, such as the restore
    /// celebration, leaves them all out. A save day has no stem, because the streak
    /// it would show is the one that broke.
    @ViewBuilder
    private var notes: some View {
        if message == nil {
            VStack(spacing: PaeoniaSpacing.space16) {
                if let people {
                    StreakTodayRow(streak: streak, people: people)
                }
                if !isSaveDay {
                    StreakMilestoneStem(currentCount: streak.currentCount, longestCount: streak.longestCount)
                }
                if let freezeNoteText {
                    freezeNote(freezeNoteText)
                }
            }
        }
    }

    private func freezeNote(_ text: LocalizedStringResource) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "snowflake")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextSecondary)
        .multilineTextAlignment(.leading)
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

#Preview("Freeze ready") {
    StreakDetailView(
        streak: CoupleStreak(
            currentCount: 6,
            longestCount: 21,
            lastQualifiedDate: "2026-06-28",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil,
            freezeAvailable: true
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Saved by a freeze") {
    StreakDetailView(
        streak: CoupleStreak(
            currentCount: 6,
            longestCount: 21,
            lastQualifiedDate: "2026-06-27",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil,
            freezeReadyAt: .now.addingTimeInterval(30 * 86_400),
            freezeSavedStreak: true
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Not started") {
    StreakDetailView(
        streak: CoupleStreak(
            currentCount: 0,
            longestCount: 0,
            lastQualifiedDate: nil,
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

#Preview("Save day") {
    StreakDetailView(
        streak: CoupleStreak(
            currentCount: 0,
            longestCount: 18,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: false,
            restorableCount: 18,
            restoreDeadline: .now.addingTimeInterval(54 * 3_600),
            currentUserContributedToday: true,
            saveDeadline: .now.addingTimeInterval(6 * 3_600)
        )
    )
    .preferredColorScheme(.dark)
}
#endif
