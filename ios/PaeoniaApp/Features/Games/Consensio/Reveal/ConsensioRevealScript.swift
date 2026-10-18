import Foundation
import SwiftUI

nonisolated struct ConsensioRevealPlan: Equatable, Sendable {
    var verdict: ConsensioVerdict
    var points: Int
}

/// When each beat happens, in seconds after the reveal starts. The table is in
/// `docs/games/consensio.md` ("Reveal").
nonisolated struct ConsensioRevealSchedule: Sendable {
    var pulses: [TimeInterval] = [0.20, 0.50, 0.80]
    /// The other marker drops onto the line.
    var drop: TimeInterval = 1.25
    /// The gold thread draws between the two markers.
    var thread: TimeInterval = 1.55
    var verdict: TimeInterval = 1.95
    var title: TimeInterval = 2.35
    /// The first point counts up. Each next point follows `pointGap` later.
    var points: TimeInterval = 2.65
    var pointGap: TimeInterval = 0.07
    var actions: TimeInterval = 3.05
    /// How long the petal bloom runs. It is `GamePetalBloom.duration`.
    var bloomDuration: TimeInterval = 0.9

    static let standard = Self()
    static let instant = Self(
        pulses: [0, 0, 0], drop: 0, thread: 0, verdict: 0, title: 0, points: 0, pointGap: 0, actions: 0,
        bloomDuration: 0
    )
}

nonisolated enum ConsensioRevealEvent: Equatable, Sendable {
    /// The line dims and the known marker stands alone.
    case start
    case pulse(intensity: CGFloat)
    case drop
    case thread
    case verdict(ConsensioVerdict)
    case bloomEnd
    case title
    /// The shared total counts up to `count` points of this round.
    case point(count: Int)
    case actions
}

nonisolated struct ConsensioRevealStep: Equatable, Sendable {
    let at: TimeInterval
    let event: ConsensioRevealEvent
}

/// The beats of a reveal, in order.
nonisolated enum ConsensioRevealScript {
    static let pulseIntensities: [CGFloat] = [0.3, 0.5, 0.7]
    static let pointIntensity: CGFloat = 0.4

    static func steps(for plan: ConsensioRevealPlan, schedule: ConsensioRevealSchedule) -> [ConsensioRevealStep] {
        var steps = [ConsensioRevealStep(at: 0, event: .start)]
        for (time, intensity) in zip(schedule.pulses, pulseIntensities) {
            steps.append(ConsensioRevealStep(at: time, event: .pulse(intensity: intensity)))
        }
        steps.append(ConsensioRevealStep(at: schedule.drop, event: .drop))
        steps.append(ConsensioRevealStep(at: schedule.thread, event: .thread))
        steps.append(ConsensioRevealStep(at: schedule.verdict, event: .verdict(plan.verdict)))
        if plan.verdict == .spotOn {
            steps.append(ConsensioRevealStep(at: schedule.verdict + schedule.bloomDuration, event: .bloomEnd))
        }
        steps.append(ConsensioRevealStep(at: schedule.title, event: .title))
        if plan.points > 0 {
            for count in 1...plan.points {
                let time = schedule.points + Double(count - 1) * schedule.pointGap
                steps.append(ConsensioRevealStep(at: time, event: .point(count: count)))
            }
        }
        steps.append(ConsensioRevealStep(at: schedule.actions, event: .actions))
        return steps.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }
}
