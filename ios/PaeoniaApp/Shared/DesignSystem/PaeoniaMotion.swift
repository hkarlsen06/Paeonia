import Foundation
import SwiftUI

enum PaeoniaMotion {
    static let motionFast: TimeInterval = 0.16
    static let motionDefault: TimeInterval = 0.24
    static let motionSlow: TimeInterval = 0.36
    static let motionMorph: TimeInterval = 0.5
    static let motionCelebration: TimeInterval = 0.55
    static let homeLayoutDuration: TimeInterval = 0.9

    /// Paeonia's ease-out, `cubic-bezier(0.23, 1, 0.32, 1)`. It moves most of the way in the
    /// first third, so a press, a view coming in or going out, or a change of state answers
    /// at once and then settles. Use it for anything that enters, leaves or changes state.
    /// The built-in `.easeOut` starts too gently to feel instant.
    static func easeOut(duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// Paeonia's ease-in-out, `cubic-bezier(0.65, 0, 0.35, 1)`, for something that travels
    /// on screen from one place to another, a morph, and a loop that breathes or drifts.
    /// Home's map camera moves along the same curve. Never use it for a press or for a view
    /// coming in, because its slow start delays the moment the person is watching.
    static func standardCurve(duration: TimeInterval) -> Animation {
        .timingCurve(0.65, 0, 0.35, 1, duration: duration)
    }

    static let buttonPress = easeOut(duration: motionFast)
    static let stateChange = easeOut(duration: motionDefault)
    /// Follows the keyboard's own slide, for layout that changes as it opens or closes.
    /// Its notification says 0.38 s, but measured frame by frame on iOS 27 it moves
    /// like this spring.
    static let keyboard = Animation.spring(duration: 0.25, bounce: 0)
    /// Something a finger dragged going back to rest, or on to where the drag sent it. A
    /// spring keeps the finger's speed when a new drag catches it halfway.
    static let dragRelease = Animation.spring(duration: motionDefault, bounce: 0.15)
    /// Home's cards and map camera share this timing when the page changes height.
    static let homeLayoutChange = standardCurve(duration: homeLayoutDuration)
    static let cardReveal = Animation.spring(duration: motionDefault, bounce: 0.18)
    /// A screen, step or game phase giving way to the next. Longer than `stateChange`
    /// because the whole screen changes.
    static let meaningfulMoment = easeOut(duration: motionSlow)
    /// Text and numbers coming into focus once their data loads (`paeoniaLoadingReveal`).
    static let loadingReveal = Animation.spring(duration: 0.5, bounce: 0)
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

    /// The call overlay's layers growing into each other, and the call bubble and the partner's
    /// avatar settling in a corner, so the avatar moves like the bubble it becomes.
    static let callOverlay = Animation.spring(duration: 0.4, bounce: 0.12)

    /// The streak sheet's stem growing out to the couple's day count, opening each
    /// flower it passes.
    static let stemGrowth = standardCurve(duration: 0.9).delay(0.25)
}

extension AnyTransition {
    /// A small mark, such as a checkmark or a badge, popping in. It grows from 90% while it
    /// fades, because a mark that grows from nothing looks like it came from nowhere.
    static let paeoniaPop = AnyTransition.scale(scale: 0.9).combined(with: .opacity)
}
