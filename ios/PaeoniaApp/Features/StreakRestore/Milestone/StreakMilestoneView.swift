import SwiftUI

/// The once-per-milestone celebration: the flame fills and counts up to the
/// milestone, then a title and a short line for it. Shown as a sheet the first
/// time the app is in front after the couple reaches it, and again from the streak
/// pill for the rest of that streak day. The daily questions completion screen
/// shows the same moment in place when finishing them reaches the milestone.
struct StreakMilestoneView: View {
    let days: Int
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var flameStarted = false
    @State private var showDetails = false

    /// Lets the sheet finish sliding up before the flame starts, so its fill and
    /// haptics play while the person is looking.
    private static let flameStartDelay: Duration = .milliseconds(450)

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Spacer()

            flame

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.streakMilestoneEyebrow)
                    .font(PaeoniaTypography.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(Color.paeoniaInkGold)

                Text(StreakMilestoneCopy.title(days: days))
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(StreakMilestoneCopy.message(days: days))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .opacity(showDetails ? 1 : 0)
            .offset(y: showDetails ? 0 : PaeoniaSpacing.space12)

            Spacer()

            Button(action: close) {
                Text(.streakMilestoneKeepGoingButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .opacity(showDetails ? 1 : 0)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaSurfacePrimary)
        // Waits for the app to be in front. Haptics do not play while it is opening.
        .task(id: scenePhase) {
            guard scenePhase == .active, !flameStarted else { return }
            try? await Task.sleep(for: Self.flameStartDelay)
            guard !Task.isCancelled else { return }
            flameStarted = true
            revealDetails()
        }
    }

    @ViewBuilder
    private var flame: some View {
        if flameStarted {
            PaeoniaStreakFlame(count: days, playsCelebration: true)
        } else {
            // Holds the flame's space without starting its count-up or haptics.
            PaeoniaStreakFlame(count: days, playsCelebration: false)
                .hidden()
        }
    }

    private func close() {
        PaeoniaHaptics.celebrationContinued()
        onClose()
    }

    private func revealDetails() {
        if reduceMotion {
            showDetails = true
        } else {
            withAnimation(PaeoniaMotion.meaningfulMoment.delay(0.28)) {
                showDetails = true
            }
        }
    }
}

/// A milestone moment to present, identified by its number of days.
struct StreakMilestoneMoment: Identifiable, Equatable {
    let days: Int
    var id: Int { days }
}

/// What decides whether the milestone moment can show right now.
struct StreakMilestoneCheck: Equatable {
    let count: Int
    let userID: UUID?
    let isScreenBusy: Bool
}

/// The title and line for each celebrated streak length. The flame already shows
/// the number of days, so neither repeats it.
enum StreakMilestoneCopy {
    private static let copy: [Int: (title: LocalizedStringResource, message: LocalizedStringResource)] = [
        3: (.streakMilestoneTitleThreeDays, .streakMilestoneMessageThreeDays),
        7: (.streakMilestoneTitleOneWeek, .streakMilestoneMessageOneWeek),
        14: (.streakMilestoneTitleTwoWeeks, .streakMilestoneMessageTwoWeeks),
        30: (.streakMilestoneTitleOneMonth, .streakMilestoneMessageOneMonth),
        50: (.streakMilestoneTitleFiftyDays, .streakMilestoneMessageFiftyDays),
        100: (.streakMilestoneTitleHundredDays, .streakMilestoneMessageHundredDays),
        200: (.streakMilestoneTitleTwoHundredDays, .streakMilestoneMessageTwoHundredDays),
        365: (.streakMilestoneTitleOneYear, .streakMilestoneMessageOneYear),
        500: (.streakMilestoneTitleFiveHundredDays, .streakMilestoneMessageFiveHundredDays),
    ]

    /// Every full year after the first shares one title and line.
    static func title(days: Int) -> LocalizedStringResource {
        copy[days]?.title ?? .streakMilestoneTitleAnotherYear
    }

    static func message(days: Int) -> LocalizedStringResource {
        copy[days]?.message ?? .streakMilestoneMessageAnotherYear
    }
}

#if DEBUG
#Preview("One week") {
    StreakMilestoneView(days: 7)
        .preferredColorScheme(.dark)
}
#endif
