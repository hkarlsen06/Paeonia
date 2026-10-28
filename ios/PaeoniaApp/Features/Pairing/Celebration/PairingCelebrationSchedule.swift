import CoreGraphics
import Foundation

/// The explicit beats of the celebration, used both to gate what is on screen and
/// to keep the particle field in step with the haptics and reveals.
enum PairingCelebrationPhase: Int, Comparable {
    case heartAppearing
    case absorbing
    case exploding
    case linking
    case settled

    static func < (lhs: PairingCelebrationPhase, rhs: PairingCelebrationPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PairingCelebrationTiming {
    static let centerYRatio: CGFloat = 0.46
    static let heartSize: CGFloat = 72

    static let heartAppear: Double = 0.55
    static let absorb: Double = 3.5
    static let explode: Double = 0.9
    static let partnerHold: Double = 1.1
    static let landingSettle: Double = 0.8
    static let profilePhotoRevealGrace: Double = 0.35
    /// The longest the intro waits for the partner's name before it starts anyway.
    static let partnerNameWait: Double = 1.5
}

/// The step durations the timeline sleeps for. The defaults match
/// `PairingCelebrationTiming`; tests pass short values so the intro runs fast.
struct PairingCelebrationSchedule {
    /// One soft haptic pulse in the build-up, followed by a pause of `gap` seconds.
    struct Pulse {
        var intensity: CGFloat
        var gap: Double
    }

    var heartAppear = PairingCelebrationTiming.heartAppear
    var absorb = PairingCelebrationTiming.absorb
    var partnerHold = PairingCelebrationTiming.partnerHold
    var landingSettle = PairingCelebrationTiming.landingSettle
    var partnerPhotoGrace = PairingCelebrationTiming.profilePhotoRevealGrace
    var partnerNameWait = PairingCelebrationTiming.partnerNameWait
    /// Rising intensity with shrinking gaps, so the moment before the burst feels
    /// like pressure building.
    var pulses: [Pulse] = [
        Pulse(intensity: 0.16, gap: 0.65),
        Pulse(intensity: 0.22, gap: 0.60),
        Pulse(intensity: 0.28, gap: 0.55),
        Pulse(intensity: 0.35, gap: 0.48),
        Pulse(intensity: 0.43, gap: 0.42),
        Pulse(intensity: 0.52, gap: 0.34),
        Pulse(intensity: 0.62, gap: 0.26),
        Pulse(intensity: 0.72, gap: 0.20)
    ]

    static let standard = PairingCelebrationSchedule()
}

struct PairingCelebrationHaptics {
    var buildUp: @MainActor (CGFloat) -> Void
    var burst: @MainActor () -> Void
    var linked: @MainActor () -> Void
    /// Fired when the intro is skipped over by Reduce Motion for a fresh link.
    var settledWithoutIntro: @MainActor () -> Void

    static let live = PairingCelebrationHaptics(
        buildUp: { PaeoniaHaptics.pairingLinkBuildUp(intensity: $0) },
        burst: {
            PaeoniaHaptics.pairingLinkExplosion()
        },
        linked: { PaeoniaHaptics.streakContinued() },
        settledWithoutIntro: {
            PaeoniaHaptics.pairedSuccessfully()
        }
    )
}
