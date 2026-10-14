import SwiftUI

/// The timings of the Dots and Boxes board. Everything here belongs to this one
/// board. Shared timings live in `PaeoniaMotion`.
enum DotsAndBoxesMotion {
    /// A line grows from its middle to both dots, with a little overshoot.
    static let lineSnap = Animation.spring(duration: 0.3, bounce: 0.3)
    /// A closed box scales up from 0.85 and fades in.
    static let boxPop = Animation.spring(duration: 0.42, bounce: 0.25)
    /// The owner's color sweeps once across a closed box.
    static let shimmer = PaeoniaMotion.standardCurve(duration: 0.7)
    /// The tints lift off the photo and the gaps between the pieces close.
    static let lift = PaeoniaMotion.standardCurve(duration: 0.8)
    static let dim = PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow)
    /// What Reduce Motion uses in place of movement.
    static let fade = PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)

    /// A closed box appears this long after its line landed.
    static let firstBoxDelay: TimeInterval = 0.1
    /// A second box from the same line follows this much later.
    static let boxStagger: TimeInterval = 0.12
    /// The dots at the ends of a new line pulse when the line reaches them.
    static let dotPulseDelay: TimeInterval = 0.08
    /// The winner's boxes pulse one after another.
    static let winnerStagger: TimeInterval = 0.06
    /// On a draw every box pulses, closer together.
    static let drawStagger: TimeInterval = 0.03
    /// The bloom starts this long after the outcome reveal began.
    static let bloomDelay: TimeInterval = 0.55
    /// How much of the lines and dots is left once the photo shows whole.
    static let restingChrome = 0.15
}
