import Foundation
import SwiftUI

enum PaeoniaMotion {
    static let motionFast: TimeInterval = 0.16
    static let motionDefault: TimeInterval = 0.24
    static let motionSlow: TimeInterval = 0.36
    static let motionCelebration: TimeInterval = 0.55

    static let buttonPress = Animation.easeOut(duration: motionFast)
    static let stateChange = Animation.easeOut(duration: motionDefault)
    static let cardReveal = Animation.spring(duration: motionDefault, bounce: 0.18)
    static let meaningfulMoment = Animation.easeInOut(duration: motionSlow)
    static let pairedScreenTransition = Animation.spring(duration: motionCelebration, bounce: 0.16)
}
