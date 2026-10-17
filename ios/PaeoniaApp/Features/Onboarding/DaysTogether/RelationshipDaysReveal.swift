import SwiftUI

/// Counts up from 0 to the number of days a couple has been together, with soft ticks
/// that rise as the number climbs and a heart burst when it lands. The day count is
/// the one the milestone card uses (`RelationshipMilestoneCalculator.daysTogether`),
/// so the two always agree.
///
/// A couple that got together today sees "Today is day one" instead of a 0. A long
/// relationship counts no slower than `DaysTogetherCountUp.maxDuration`. Under Reduce
/// Motion the final number fades in with no ticks. `onFinished` runs once the payoff
/// has played, for the caller to bring in what comes next.
struct RelationshipDaysReveal: View {
    let onFinished: () -> Void
    private let days: Int

    @State private var isShown = false
    @State private var countStart: Date?
    @State private var hasLanded = false
    @State private var burstID: Int?
    @State private var popCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 88

    /// `startedOn` is the couple's start date as `yyyy-MM-dd`, the stored format.
    init(startedOn: String, now: Date = Date(), onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
        days = max(0, RelationshipMilestoneCalculator().daysTogether(startedOn: startedOn, now: now) ?? 0)
    }

    private var countUp: DaysTogetherCountUp {
        DaysTogetherCountUp(days: days)
    }

    var body: some View {
        // Read here, since the keyframe closure can't read view state.
        let pops = !reduceMotion

        VStack(spacing: PaeoniaSpacing.space4) {
            if days == 0 {
                Text(.onboardingDaysTogetherDayOne)
                    .font(.system(size: numberSize * 0.5, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TimelineView(.animation(paused: countStart == nil || hasLanded)) { context in
                    Text(shownDays(at: context.date), format: .number)
                }
                .font(.system(size: numberSize, weight: .semibold, design: .serif))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)

                Text(.onboardingDaysTogetherUnit(count: days))
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .foregroundStyle(.paeoniaTextPrimary)
        // Behind the number, so the hearts come out from under it.
        .background {
            if let burstID {
                MilestoneHeartBurst(unit: numberSize)
                    .id(burstID)
            }
        }
        .keyframeAnimator(initialValue: CGFloat(1), trigger: popCount) { content, scale in
            content.scaleEffect(pops ? scale : 1)
        } keyframes: { _ in
            SpringKeyframe(1.12, duration: 0.18, spring: .snappy)
            SpringKeyframe(1, duration: 0.5, spring: .bouncy)
        }
        .scaleEffect(isShown || reduceMotion ? 1 : 0.85)
        .opacity(isShown ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            days == 0
                ? Text(.onboardingDaysTogetherDayOne)
                : Text(.onboardingDaysTogetherAccessibility(days))
        )
        .task {
            await run()
        }
    }

    private func shownDays(at date: Date) -> Int {
        if hasLanded {
            return days
        }
        guard let countStart else {
            return 0
        }
        return countUp.value(at: date.timeIntervalSince(countStart))
    }

    // MARK: Script

    private func run() async {
        guard !isShown else {
            return
        }

        if reduceMotion {
            hasLanded = true
            withAnimation(.easeOut(duration: PaeoniaMotion.motionSlow)) {
                isShown = true
            }
            guard await sleep(PaeoniaMotion.motionSlow) else { return }
            payoff()
            guard await sleep(0.6) else { return }
            onFinished()
            return
        }

        withAnimation(PaeoniaMotion.cardReveal) {
            isShown = true
        }
        // A beat on 0 before it starts climbing.
        guard await sleep(0.45) else { return }

        if days > 0 {
            await count()
            guard !Task.isCancelled else { return }
        }

        hasLanded = true
        payoff()
        // Lets the hearts finish before what comes next.
        guard await sleep(1.3) else { return }
        onFinished()
    }

    /// Plays the ticks in step with the number, and returns as it lands.
    private func count() async {
        let countUp = countUp
        countStart = Date()
        var elapsed: TimeInterval = 0

        for tick in countUp.ticks {
            guard await sleep(tick.time - elapsed) else { return }
            elapsed = tick.time
            PaeoniaHaptics.streakTick(intensity: tick.intensity)
            GameSound.tick.play(volume: tick.intensity * 0.8)
        }

        _ = await sleep(countUp.duration - elapsed)
    }

    private func payoff() {
        popCount += 1
        burstID = popCount
        PaeoniaHaptics.milestoneReached()
        GameSound.win.play()
    }

    /// Sleeps for `seconds`, returning false if the reveal went away meanwhile.
    private func sleep(_ seconds: TimeInterval) async -> Bool {
        if seconds > 0 {
            try? await Task.sleep(for: .seconds(seconds))
        }
        return !Task.isCancelled
    }
}

#if DEBUG
#Preview("Two years") {
    RelationshipDaysReveal(startedOn: "2024-08-17", now: Date())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaeoniaGlowBackground())
        .preferredColorScheme(.dark)
}

#Preview("A few days") {
    RelationshipDaysReveal(startedOn: "2026-10-12", now: Date())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaeoniaGlowBackground())
        .preferredColorScheme(.dark)
}

#Preview("Today") {
    RelationshipDaysReveal(
        startedOn: Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()),
        now: Date()
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(PaeoniaGlowBackground())
    .preferredColorScheme(.dark)
}
#endif
