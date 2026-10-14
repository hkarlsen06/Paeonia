import SwiftUI

/// A celebratory streak indicator: a flame that fills liquid-style from the
/// bottom up while the day count ticks toward its value, embers drift off the
/// top, and the haptics build to a payoff pop as it lands. It's the dopamine
/// moment for keeping a streak alive.
///
/// The component is purely presentational. Pass the streak `count` and it plays
/// the count-up on appear. It is deliberately reusable: the answer-flow
/// completion screen uses it as a hero now, and a calmer `playsCelebration:
/// false` form is ready for a static surface (e.g. the Home tab streak label,
/// `home.streak.label`) when that lands.
///
/// Everything is time-driven and deterministic (no external animation state), so
/// it renders the same every play and stays smooth. Once the celebration has
/// played out, the embers fade and the timeline pauses, so an idle screen stops
/// redrawing. With Reduce Motion on, or `playsCelebration: false`, it shows the
/// final, full-flame state immediately with a single light haptic instead of the
/// build-up.
struct PaeoniaStreakFlame: View {
    let count: Int
    var playsCelebration: Bool = true
    /// A broken streak that can be bought back: the flame renders cold and dim
    /// (no fill, glow, embers, or celebration) so it reads as "slipped". The
    /// `count` is then the lost streak length the restore would bring back. The
    /// "get it back" action lives in the surrounding surface, not here.
    var isBroken: Bool = false
    /// Keeps the flame gently "alive" at rest with a breathing liquid level and
    /// the living flicker, without the count-up celebration or its haptics. For
    /// surfaces that show the streak on its own (e.g. the streak detail sheet),
    /// not the earn-it moment. Ignored while celebrating, broken, or Reduce Motion.
    var ambientMotion: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAnimating = false
    /// True while running the calm continuous motion (vs. the count-up celebration),
    /// so the timeline keeps the level high and breathing instead of filling from zero.
    @State private var isAmbient = false
    /// True while running the one-shot drain that turns a full flame into the cold,
    /// frozen broken pool when a slipped streak first appears.
    @State private var isBreaking = false
    /// True once the celebration has played out. The timeline pauses and the embers
    /// are removed so nothing redraws while the screen sits idle.
    @State private var isSettled = false
    @State private var hasStarted = false
    @State private var animationStart = Date()
    @State private var driver: Task<Void, Never>?
    /// The wave phase the drain settles on, so the static frozen pool matches the
    /// last animated frame instead of snapping to a different ripple.
    @State private var frozenPhase: CGFloat = 0

    // Payoff accents, nudged by the driver the instant the flame fills.
    @State private var flameScale: CGFloat = 1
    @State private var glowFlare: CGFloat = 0
    @State private var emberOpacity: Double = 1

    @ScaledMetric(relativeTo: .largeTitle) private var scaledFlameHeight: CGFloat = Self.baseFlameHeight
    @ScaledMetric(relativeTo: .largeTitle) private var scaledNumberSize: CGFloat = Self.baseNumberSize

    private static let baseFlameHeight: CGFloat = 132
    private static let baseNumberSize: CGFloat = 54
    /// Largest Dynamic Type growth the flame follows. Past this (about the
    /// accessibility2 size) the flame and number stay put so they don't crowd out
    /// the rest of the screen. The caption under the number keeps scaling.
    private static let maxTextScale: CGFloat = 1.4
    /// Frame spacing for the ambient breathing. It moves slowly, so 30 fps reads as smooth.
    private static let ambientFrameInterval: TimeInterval = 1.0 / 30
    /// How long the payoff pop and glow get to finish before the embers fade.
    private static let afterglowDuration: Double = 1.0
    private static let emberFadeDuration: Double = 0.6

    private var flameHeight: CGFloat { min(scaledFlameHeight, Self.baseFlameHeight * Self.maxTextScale) }
    private var numberSize: CGFloat { min(scaledNumberSize, Self.baseNumberSize * Self.maxTextScale) }
    private var flameWidth: CGFloat { flameHeight * 0.84 }

    /// One frame of the flame. `brokenness` (0 alive, 1 slipped) crossfades the warm
    /// flame into the cold frozen pool, so the same layout serves the living flame,
    /// the static broken state, and every frame of the drain between.
    private struct Frame {
        var level: CGFloat
        var phase: CGFloat
        var flicker: CGFloat
        var value: Int
        var emits = false
        var brokenness: CGFloat = 0
    }

    var body: some View {
        content
            .onAppear(perform: start)
            .onDisappear(perform: stop)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    @ViewBuilder
    private var content: some View {
        if isAnimating {
            TimelineView(
                .animation(minimumInterval: isAmbient ? Self.ambientFrameInterval : nil, paused: isSettled)
            ) { timeline in
                let elapsed = timeline.date.timeIntervalSince(animationStart)
                layout(isBreaking ? breakingFrame(elapsed: elapsed) : playingFrame(elapsed: elapsed))
            }
        } else {
            // Reduce Motion, a calm/static use, or the settled end of a drain: the
            // full settled flame, or the cold frozen pool once a streak has slipped.
            layout(restingFrame)
        }
    }

    private var restingFrame: Frame {
        Frame(
            level: isBroken || isUnlit ? StreakFlameMotion.brokenLevel : 1,
            phase: isBroken ? frozenPhase : 0,
            flicker: 0,
            value: count,
            brokenness: isBroken ? 1 : 0
        )
    }

    /// One frame of the celebration or the ambient loop. Ambient stays high and
    /// breathing with the number settled. The celebration fills from empty while the
    /// number climbs.
    private func playingFrame(elapsed: TimeInterval) -> Frame {
        let level = isAmbient
            ? StreakFlameMotion.ambientLevel(at: elapsed)
            : StreakFlameMotion.fillLevel(at: elapsed)
        return Frame(
            level: level,
            phase: CGFloat(elapsed * StreakFlameMotion.waveSpeed),
            flicker: StreakFlameMotion.flicker(at: elapsed),
            value: isAmbient ? count : Int((Double(count) * Double(level)).rounded()),
            emits: !isAmbient && !isSettled
        )
    }

    /// One frame of the drain: the flame falls from full to the cold pool while the
    /// wave eases to a freeze and the warm color bleeds out to grey.
    private func breakingFrame(elapsed: TimeInterval) -> Frame {
        let progress = CGFloat(StreakFlameMotion.smoothstep(min(elapsed / StreakFlameMotion.breakDuration, 1)))
        let startLevel = StreakFlameMotion.brokenStartLevel
        return Frame(
            level: startLevel + (StreakFlameMotion.brokenLevel - startLevel) * progress,
            phase: StreakFlameMotion.breakPhase(at: elapsed),
            // The living flicker fades out as the flame goes still.
            flicker: StreakFlameMotion.flicker(at: elapsed) * (1 - progress),
            value: count,
            brokenness: progress
        )
    }

    private func layout(_ frame: Frame) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            flameView(frame)
            counter(frame)
        }
    }

    private func flameView(_ frame: Frame) -> some View {
        // An unlit flame has no warm glow.
        let alive = isUnlit ? 0 : Double(1 - frame.brokenness)
        return StreakFlameArt(
            level: frame.level,
            phase: frame.phase,
            flicker: frame.flicker,
            brokenness: frame.brokenness,
            width: flameWidth
        )
        .frame(width: flameWidth, height: flameHeight)
        .overlay {
            if frame.emits {
                StreakEmberField(start: animationStart)
                    .opacity(emberOpacity)
            }
        }
        .scaleEffect(flameScale)
        // The warm glow shrinks and fades out as the flame cools, with a
        // faint dark shadow fading in to anchor the spent pool.
        .shadow(
            color: .paeoniaAccentPrimary.opacity((0.4 + 0.4 * Double(glowFlare)) * alive),
            radius: (22 + 26 * glowFlare) * (1 - frame.brokenness) + 8 * frame.brokenness
        )
        .shadow(color: .black.opacity(0.18 * Double(frame.brokenness)), radius: 8)
        .shadow(color: .paeoniaAccentSecondary.opacity(0.35 * Double(glowFlare) * alive), radius: 10)
        .opacity(isUnlit ? 0.5 : 1)
    }

    /// A paused streak is dimmed, not crossed out: the count is still the
    /// person's to win back, so it should read as resting rather than cancelled.
    private func counter(_ frame: Frame) -> some View {
        let brokenness = Double(frame.brokenness)
        return VStack(spacing: PaeoniaSpacing.space4) {
            Text(verbatim: frame.value.formatted())
                .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.paeoniaTextPrimary.mix(with: .paeoniaTextSecondary, by: brokenness))
                .opacity(1 - 0.3 * brokenness)

            Text(.homeStreakLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(Color.paeoniaAccentPrimary.mix(with: .paeoniaTextTertiary, by: brokenness))
        }
        .opacity(isUnlit ? 0.6 : 1)
    }

    /// No streak yet: the flame waits nearly empty and dim instead of fully lit.
    private var isUnlit: Bool {
        !isBroken && count < 1
    }

    private var accessibilityLabel: String {
        if isBroken {
            return String(localized: .streakFlameLostAccessibility(count.formatted()))
        }

        return "\(count) \(String(localized: .homeStreakLabel))"
    }

    // MARK: - Sequence

    private func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let celebrates = playsCelebration && !reduceMotion && !isBroken && count >= 1
        if celebrates {
            animationStart = Date()
            isAmbient = false
            isAnimating = true
            driver = Task { @MainActor in
                await runCountUp()
            }
            return
        }

        // A slipped streak drains from a full, warm flame down to the cold frozen
        // pool when the restore surface opens, instead of appearing already broken.
        let breaks = isBroken && !reduceMotion && count >= 1
        if breaks {
            animationStart = Date()
            isBreaking = true
            isAnimating = true
            driver = Task { @MainActor in
                await runBreak()
            }
            return
        }

        // A calm, continuously "alive" flame for at-rest surfaces: no count-up and
        // no haptics, just the breathing liquid and the living flicker.
        let ambient = ambientMotion && !reduceMotion && !isBroken && count >= 1
        if ambient {
            animationStart = Date()
            isAmbient = true
            isAnimating = true
            return
        }

        isAnimating = false
        // A broken streak is not a celebration, so it stays silent.
        if playsCelebration, !isBroken {
            PaeoniaHaptics.streakContinued()
        }
    }

    /// Leaves a consistent state when the view goes away. A run that already
    /// finished stays settled. A run cut short resets to the start, so the next
    /// appearance plays it again instead of showing a half-played flame with a
    /// timeline that never stops.
    private func stop() {
        guard let driver else { return }
        driver.cancel()
        self.driver = nil
        hasStarted = false
        isAnimating = false
        isBreaking = false
        isSettled = false
        flameScale = 1
        glowFlare = 0
        emberOpacity = 1
    }

    /// Fires the rising soft ticks in step with the climbing number, then the
    /// payoff hit and a quick flare the instant the flame tops out.
    @MainActor
    private func runCountUp() async {
        let pulseCount = min(max(count, 1), 14)
        var lastTime = 0.0

        for index in 0..<pulseCount {
            let fraction = pulseCount == 1 ? 1 : Double(index) / Double(pulseCount - 1)
            // Match the fill's smoothstep so ticks land with the number.
            let targetTime = StreakFlameMotion.fillDuration * StreakFlameMotion.smoothstep(fraction) * 0.95
            let gap = targetTime - lastTime
            if gap > 0, await sleep(gap) == false { return }
            lastTime = targetTime

            PaeoniaHaptics.streakTick(intensity: 0.32 + 0.5 * fraction)
        }

        let remainder = StreakFlameMotion.fillDuration - lastTime
        if remainder > 0, await sleep(remainder) == false { return }

        PaeoniaHaptics.streakCelebrated()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.45)) {
            flameScale = 1.14
            glowFlare = 1
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.16)) {
            flameScale = 1
        }
        withAnimation(.easeOut(duration: 0.9).delay(0.12)) {
            glowFlare = 0
        }

        await windDown()
    }

    /// Once the pop and glow have finished, fades the embers and pauses the
    /// timeline so an idle screen stops redrawing.
    @MainActor
    private func windDown() async {
        guard await sleep(Self.afterglowDuration) else { return }
        withAnimation(PaeoniaMotion.standardCurve(duration: Self.emberFadeDuration)) {
            emberOpacity = 0
        }
        guard await sleep(Self.emberFadeDuration) else { return }
        isSettled = true
        driver = nil
    }

    /// Holds the drain on screen for its full duration, then settles the flame into
    /// the static frozen pool so the timeline can stop redrawing.
    @MainActor
    private func runBreak() async {
        frozenPhase = StreakFlameMotion.breakPhase(at: StreakFlameMotion.breakDuration)
        try? await Task.sleep(for: .seconds(StreakFlameMotion.breakDuration))
        guard !Task.isCancelled else { return }
        isBreaking = false
        isAnimating = false
        driver = nil
    }

    /// Sleeps for `seconds`, returning `false` if the run was cancelled.
    private func sleep(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

#if DEBUG
#Preview("Count up") {
    PaeoniaStreakFlame(count: 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Big streak") {
    PaeoniaStreakFlame(count: 128)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Static (settled)") {
    PaeoniaStreakFlame(count: 7, playsCelebration: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
