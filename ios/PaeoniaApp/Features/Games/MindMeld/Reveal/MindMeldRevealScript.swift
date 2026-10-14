import Foundation
import SwiftUI

/// How a revealed round reads on screen.
nonisolated enum MindMeldRevealOutcome: Equatable, Sendable {
    /// The words match, or a partner counted a near miss.
    case meld
    /// Almost the same word. A partner can still count it.
    case near
    case miss
    /// The miss in the last round of a game. The game is over.
    case gotAway
}

nonisolated struct MindMeldRevealPlan: Equatable, Sendable {
    var outcome: MindMeldRevealOutcome
}

/// When each beat happens, in seconds after the reveal starts.
nonisolated struct MindMeldRevealSchedule: Sendable {
    /// The three build-up pulses.
    var pulses: [TimeInterval] = [0.20, 0.50, 0.80]
    var myFlip: TimeInterval = 1.10
    var partnerFlip: TimeInterval = 1.55
    var verdict: TimeInterval = 2.10
    var title: TimeInterval = 2.60
    /// The stats line, for a meld only.
    var stats: TimeInterval = 2.90
    var actions: TimeInterval = 3.00
    /// How long the petal bloom runs. It is `GamePetalBloom.duration`,
    /// which is main-actor isolated, and a test keeps the two equal.
    var bloomDuration: TimeInterval = 0.9

    static let standard = Self()
    static let instant = Self(
        pulses: [0, 0, 0], myFlip: 0, partnerFlip: 0, verdict: 0, title: 0, stats: 0, actions: 0, bloomDuration: 0
    )
}

nonisolated enum MindMeldRevealEvent: Equatable, Sendable {
    /// The glow rises behind the cards.
    case start
    case pulse(intensity: CGFloat)
    case flipMine
    case flipPartner
    case verdict(MindMeldRevealOutcome)
    /// The petals are done, so the canvas can stop.
    case bloomEnd
    case title
    case stats
    case actions
    /// A counted near miss turns into a meld.
    case merge
}

nonisolated struct MindMeldRevealStep: Equatable, Sendable {
    let at: TimeInterval
    let event: MindMeldRevealEvent
}

/// The beats of a reveal, in order.
nonisolated enum MindMeldRevealScript {
    typealias Step = MindMeldRevealStep
    typealias Schedule = MindMeldRevealSchedule

    static let pulseIntensities: [CGFloat] = [0.3, 0.5, 0.7]
    static let flipIntensity: CGFloat = 0.85

    static func steps(for plan: MindMeldRevealPlan, schedule: Schedule) -> [Step] {
        var steps = [Step(at: 0, event: .start)]
        for (time, intensity) in zip(schedule.pulses, pulseIntensities) {
            steps.append(Step(at: time, event: .pulse(intensity: intensity)))
        }
        steps.append(Step(at: schedule.myFlip, event: .flipMine))
        steps.append(Step(at: schedule.partnerFlip, event: .flipPartner))
        steps.append(Step(at: schedule.verdict, event: .verdict(plan.outcome)))
        if plan.outcome == .meld {
            steps.append(Step(at: schedule.verdict + schedule.bloomDuration, event: .bloomEnd))
        }
        steps.append(Step(at: schedule.title, event: .title))
        if plan.outcome == .meld {
            steps.append(Step(at: schedule.stats, event: .stats))
        }
        steps.append(Step(at: schedule.actions, event: .actions))
        return stable(steps)
    }

    /// The beats after a counted near miss, with the same gaps as after the
    /// verdict of a meld. Times are relative to the merge.
    static func meldFromNearSteps(schedule: Schedule) -> [Step] {
        stable([
            Step(at: 0, event: .merge),
            Step(at: schedule.bloomDuration, event: .bloomEnd),
            Step(at: schedule.title - schedule.verdict, event: .title),
            Step(at: schedule.stats - schedule.verdict, event: .stats),
            Step(at: schedule.actions - schedule.verdict, event: .actions)
        ])
    }

    /// Stable by time, so events at the same moment keep the order they were added.
    private static func stable(_ steps: [Step]) -> [Step] {
        steps.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }
}
