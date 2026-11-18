import CoreHaptics
import OSLog

/// Plays a Core Haptics pattern: taps and buzzes at set times, with curves, for a haptic that
/// must follow an animation or a sound to the millisecond. `PaeoniaHaptics` plays single taps
/// with UIKit's feedback generators.
enum PaeoniaHapticPattern {
    private static var engine: CHHapticEngine?
    private static let logger = Logger(subsystem: "no.paeonia.app", category: "Haptics")

    /// Returns the player, so a pattern can stop early when its animation does.
    @discardableResult
    static func play(
        _ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []
    ) -> (any CHHapticPatternPlayer)? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        do {
            let engine = try engine ?? makeEngine()
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return player
        } catch {
            logger.error("haptic pattern did not play: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        self.engine = engine
        return engine
    }
}

extension CHHapticEvent {
    /// A tap `time` seconds into the pattern.
    static func tap(at time: TimeInterval, intensity: Float = 1, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    /// A buzz from `time` seconds into the pattern, for `duration` seconds.
    static func buzz(
        at time: TimeInterval, duration: TimeInterval, intensity: Float = 1, sharpness: Float
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }
}
