import Foundation
import SwiftUI

nonisolated enum DrawAndGuessRevealKind: Equatable, Sendable {
    /// The right word. Letters light up and the petals fly.
    case solved
    /// "Show me". The answer fills in quietly.
    case missed
}

nonisolated struct DrawAndGuessRevealPlan: Equatable, Sendable {
    var kind: DrawAndGuessRevealKind
    /// Letters in the answer, without spaces.
    var letterCount: Int
    /// The most points one column gains, for the count-up ticks.
    var pointsAdded: Int
    var hasSpeedBonus: Bool
    var hasFirstTryBonus = false
}

/// When each beat happens, in seconds after the last tile lands.
nonisolated struct DrawAndGuessRevealSchedule: Sendable {
    /// The first letter lights as the last tile lands in its slot, 0.16 s after the tap.
    var lightStart: TimeInterval = 0.16
    var lightSpan: TimeInterval = 0.44
    var maxLetterGap: TimeInterval = 0.045
    var bloom: TimeInterval = 0.70
    var glowSettle: TimeInterval = 1.30
    var title: TimeInterval = 1.10
    var panel: TimeInterval = 1.40
    /// The count waits for the panel to fade in, so the first tick has a number to move.
    var countLead: TimeInterval = 0.30
    /// From the first count tick to the last.
    var countSpan: TimeInterval = 0.40
    /// The bonus lines land after the count.
    var speedBonus: TimeInterval = 2.30
    /// The first-try line lands after the speed bonus.
    var firstTryBonus: TimeInterval = 2.60
    /// The reaction row appears.
    var actions: TimeInterval = 2.90
    /// The missed round fills the answer over this long, then moves on.
    var missedFill: TimeInterval = 0.50
    var missedTitle: TimeInterval = 0.90
    var missedActions: TimeInterval = 1.10

    static let standard = Self()
    static let instant = Self(
        lightStart: 0, lightSpan: 0, maxLetterGap: 0, bloom: 0, glowSettle: 0, title: 0, panel: 0,
        countLead: 0, countSpan: 0, speedBonus: 0, firstTryBonus: 0, actions: 0,
        missedFill: 0, missedTitle: 0, missedActions: 0
    )
}

/// The haptics and sounds of the reveal, injected so tests can record them.
struct DrawAndGuessRevealHaptics {
    var selection: @MainActor () -> Void
    var letterTick: @MainActor (CGFloat) -> Void
    var answerRevealed: @MainActor () -> Void
    var soft: @MainActor () -> Void
    var scoreTick: @MainActor (CGFloat) -> Void
    /// A bonus line lands, for the speed bonus and for the first-try bonus.
    var speedBonus: @MainActor () -> Void

    static let live = Self(
        selection: {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.6)
        },
        letterTick: {
            PaeoniaHaptics.streakTick(intensity: $0)
            GameSound.tick.play(volume: $0)
        },
        answerRevealed: {
            PaeoniaHaptics.answerRevealed()
            GameSound.chime.play()
        },
        soft: {
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.nudge.play()
        },
        scoreTick: {
            PaeoniaHaptics.streakTick(intensity: $0)
            GameSound.tick.play(volume: $0)
        },
        speedBonus: {
            PaeoniaHaptics.streakContinued()
            GameSound.bonus.play()
        }
    )
}

nonisolated enum DrawAndGuessRevealEvent: Equatable, Sendable {
    case start
    case lightLetter(index: Int, tick: CGFloat?)
    case bloom
    case glowSettle
    case collapse
    case title
    case panel
    /// The totals count one step further, to `progress` of the way, with a tick.
    case scoreTick(progress: Double, intensity: CGFloat)
    case speedBonus
    case firstTryBonus
    case actions
    case fillLetter(index: Int)
    case fillStart
}

nonisolated struct DrawAndGuessRevealStep: Equatable, Sendable {
    let at: TimeInterval
    let event: DrawAndGuessRevealEvent
}

/// The beats of a reveal, in order.
nonisolated enum DrawAndGuessRevealScript {
    typealias Step = DrawAndGuessRevealStep

    static let maxLetterTicks = 8

    static func steps(for plan: DrawAndGuessRevealPlan, schedule: DrawAndGuessRevealSchedule) -> [Step] {
        let steps = switch plan.kind {
        case .solved: solvedSteps(plan, schedule)
        case .missed: missedSteps(plan, schedule)
        }
        // Stable by time, so events at the same moment keep the order they were added.
        return steps.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    private static func solvedSteps(_ plan: DrawAndGuessRevealPlan, _ schedule: DrawAndGuessRevealSchedule) -> [Step] {
        let letters = max(plan.letterCount, 0)
        var steps = [Step(at: 0, event: .start)]
        steps += lightSteps(letters: letters, schedule: schedule)
        steps.append(Step(at: schedule.bloom, event: .bloom))
        steps.append(Step(at: schedule.bloom, event: .collapse))
        steps.append(Step(at: schedule.title, event: .title))
        steps.append(Step(at: schedule.glowSettle, event: .glowSettle))
        if plan.pointsAdded > 0 {
            steps.append(Step(at: schedule.panel, event: .panel))
            let ticks = min(plan.pointsAdded, maxLetterTicks)
            // A single point lands on the first beat of the count, at full strength.
            for tick in 0..<ticks {
                let rise = ticks > 1 ? Double(tick) / Double(ticks - 1) : 0
                let strength = ticks > 1 ? rise : 1
                steps.append(Step(
                    at: schedule.panel + schedule.countLead + schedule.countSpan * rise,
                    event: .scoreTick(progress: Double(tick + 1) / Double(ticks), intensity: 0.25 + 0.6 * strength)
                ))
            }
        }
        if plan.hasSpeedBonus {
            steps.append(Step(at: schedule.speedBonus, event: .speedBonus))
        }
        if plan.hasFirstTryBonus {
            steps.append(Step(at: schedule.firstTryBonus, event: .firstTryBonus))
        }
        steps.append(Step(at: schedule.actions, event: .actions))
        return steps
    }

    /// One step per letter, with a haptic tick on at most eight of them, rising from 0.25 to 0.85.
    private static func lightSteps(letters: Int, schedule: DrawAndGuessRevealSchedule) -> [Step] {
        let gap = letters > 0 ? min(schedule.maxLetterGap, schedule.lightSpan / Double(letters)) : 0
        let tickEvery = max(1, Int((Double(letters) / Double(maxLetterTicks)).rounded(.up)))
        let tickTotal = (letters + tickEvery - 1) / tickEvery
        return (0..<letters).map { index in
            var tick: CGFloat?
            if index % tickEvery == 0 {
                let progress = tickTotal > 1 ? CGFloat(index / tickEvery) / CGFloat(tickTotal - 1) : 1
                tick = 0.25 + 0.6 * progress
            }
            return Step(at: schedule.lightStart + gap * Double(index), event: .lightLetter(index: index, tick: tick))
        }
    }

    private static func missedSteps(_ plan: DrawAndGuessRevealPlan, _ schedule: DrawAndGuessRevealSchedule) -> [Step] {
        let letters = max(plan.letterCount, 0)
        let gap = letters > 0 ? schedule.missedFill / Double(letters) : 0
        var steps = [Step(at: 0, event: .fillStart)]
        steps += (0..<letters).map { Step(at: gap * Double($0), event: .fillLetter(index: $0)) }
        steps.append(Step(at: schedule.missedFill, event: .collapse))
        steps.append(Step(at: schedule.missedTitle, event: .title))
        steps.append(Step(at: schedule.missedActions, event: .actions))
        return steps
    }
}
