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

    /// Drives the hero morph that expands the daily prompt card into the full
    /// answering flow. A smooth spring with only a hint of settle, so the morphing
    /// eyebrow, progress bar, and button glide into their new positions and sizes
    /// without visibly overshooting — bouncier springs make morphing text wobble.
    static let heroMorph = Animation.spring(duration: motionMorph, bounce: 0.1)

    /// The surface-and-supporting-content fade that rides alongside `heroMorph`.
    /// Kept short so the full-screen background has settled by the time the gliding
    /// elements arrive, which keeps the card's growth reading as one clean motion
    /// rather than a long cross-dissolve over the still-visible card behind it.
    static let heroMorphChrome = Animation.easeOut(duration: motionDefault)
}
