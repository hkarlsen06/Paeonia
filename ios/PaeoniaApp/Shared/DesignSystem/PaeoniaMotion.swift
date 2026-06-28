import Foundation
import SwiftUI

enum PaeoniaMotion {
    static let motionFast: TimeInterval = 0.16
    static let motionDefault: TimeInterval = 0.24
    static let motionSlow: TimeInterval = 0.36
    static let motionMorph: TimeInterval = 0.5
    static let motionCelebration: TimeInterval = 0.55

    static let buttonPress = Animation.easeOut(duration: motionFast)
    static let stateChange = Animation.easeOut(duration: motionDefault)
    static let cardReveal = Animation.spring(duration: motionDefault, bounce: 0.18)
    static let meaningfulMoment = Animation.easeInOut(duration: motionSlow)
    static let pairedScreenTransition = Animation.spring(duration: motionCelebration, bounce: 0.16)

    /// Blooms a celebratory reward surface — the daily-challenge streak screen — into
    /// place. A gentle, slightly-settling spring, slower than `cardReveal`, so the
    /// content arrives like a reward growing in rather than snapping. Paced to give
    /// the streak flame's own count-up room to take over once it lands.
    static let celebrationReveal = Animation.spring(duration: motionCelebration, bounce: 0.18)

    /// Drives the hero morph that expands the daily prompt card into the full
    /// answering flow. A smooth spring with only a hint of settle, so the morphing
    /// eyebrow, progress bar, and button glide into their new positions and sizes
    /// without visibly overshooting — bouncier springs make morphing text wobble.
    ///
    /// The flow's content reveal is animated with this same curve so the surface
    /// uncovers in lockstep with the gliding elements rather than drifting out of
    /// sync with them.
    static let heroMorph = Animation.spring(duration: motionMorph, bounce: 0.1)
}
