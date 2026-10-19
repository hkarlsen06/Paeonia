import Foundation
import SwiftUI

nonisolated struct GuessMySpotRevealPlan: Equatable, Sendable {
    var verdict: GuessMySpotVerdict
    var distanceMeters: Int
    var points: Int
}

/// When each beat happens, in seconds after the reveal starts. The table is in
/// `docs/games/guess-my-spot.md` ("Reveal").
nonisolated struct GuessMySpotRevealSchedule: Sendable {
    var pulses: [TimeInterval] = [0.20, 0.45, 0.70]
    /// The camera zooms out until both spots fit.
    var zoomOut: TimeInterval = 0.90
    var zoomOutDuration: TimeInterval = 0.9
    /// The line starts drawing from the guess.
    var line: TimeInterval = 1.55
    var lineDuration: TimeInterval = 0.7
    /// The real pin drops onto the end of the line.
    var drop: TimeInterval = 2.30
    /// How long the real pin falls. The chime plays when it hits.
    var fallDuration: TimeInterval = 0.25
    /// The camera lands on the real spot, and the distance counts up.
    /// After the pin has planted and the screen held still for a moment.
    var land: TimeInterval = 2.85
    var landDuration: TimeInterval = 1.0
    var distanceSteps = 10
    var distanceGap: TimeInterval = 0.07
    var verdict: TimeInterval = 3.60
    /// The result card rises with the photo.
    var card: TimeInterval = 3.90
    var points: TimeInterval = 4.20
    var pointSteps = 10
    var pointGap: TimeInterval = 0.07
    var actions: TimeInterval = 4.90
    /// How long the petal bloom runs. It is `GamePetalBloom.duration`.
    var bloomDuration: TimeInterval = 0.9

    static let standard = Self()
}

nonisolated enum GuessMySpotRevealEvent: Equatable, Sendable {
    /// The photo slides away and the map fills the screen.
    case start
    case pulse(intensity: CGFloat)
    case zoomOut
    case line
    case drop
    case land
    /// The distance counts up to `step` of `distanceSteps`.
    case distance(step: Int)
    case verdict(GuessMySpotVerdict)
    case bloomEnd
    case card
    /// The shared total counts up to `step` of `pointSteps`.
    case points(step: Int)
    case actions
}

nonisolated struct GuessMySpotRevealStep: Equatable, Sendable {
    let at: TimeInterval
    let event: GuessMySpotRevealEvent
}

/// The beats of a reveal, in order.
nonisolated enum GuessMySpotRevealScript {
    static let pulseIntensities: [CGFloat] = [0.3, 0.5, 0.7]
    static let distanceIntensity: CGFloat = 0.3
    static let pointIntensity: CGFloat = 0.4

    static func steps(for plan: GuessMySpotRevealPlan, schedule: GuessMySpotRevealSchedule) -> [GuessMySpotRevealStep] {
        var steps = [GuessMySpotRevealStep(at: 0, event: .start)]
        for (time, intensity) in zip(schedule.pulses, pulseIntensities) {
            steps.append(GuessMySpotRevealStep(at: time, event: .pulse(intensity: intensity)))
        }
        steps.append(GuessMySpotRevealStep(at: schedule.zoomOut, event: .zoomOut))
        steps.append(GuessMySpotRevealStep(at: schedule.line, event: .line))
        steps.append(GuessMySpotRevealStep(at: schedule.drop, event: .drop))
        steps.append(GuessMySpotRevealStep(at: schedule.land, event: .land))
        for step in 1...max(1, schedule.distanceSteps) {
            let time = schedule.land + Double(step - 1) * schedule.distanceGap
            steps.append(GuessMySpotRevealStep(at: time, event: .distance(step: step)))
        }
        steps.append(GuessMySpotRevealStep(at: schedule.verdict, event: .verdict(plan.verdict)))
        if plan.verdict == .spotOn {
            steps.append(GuessMySpotRevealStep(at: schedule.verdict + schedule.bloomDuration, event: .bloomEnd))
        }
        steps.append(GuessMySpotRevealStep(at: schedule.card, event: .card))
        if plan.points > 0 {
            for step in 1...max(1, schedule.pointSteps) {
                let time = schedule.points + Double(step - 1) * schedule.pointGap
                steps.append(GuessMySpotRevealStep(at: time, event: .points(step: step)))
            }
        }
        steps.append(GuessMySpotRevealStep(at: schedule.actions, event: .actions))
        return steps.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    /// What a counter shows at `step` of `steps`: an ease out, so it slows into the
    /// final number, which it reaches exactly at the last step.
    static func counted(_ value: Int, step: Int, of steps: Int) -> Int {
        guard steps > 0, step < steps else { return value }
        let fraction = Double(max(0, step)) / Double(steps)
        let eased = 1 - pow(1 - fraction, 2)
        return Int((Double(value) * eased).rounded())
    }
}
