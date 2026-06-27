import UIKit

@MainActor
enum PaeoniaHaptics {
    static func pairedSuccessfully() {
        notify(.success)
    }

    static func pairingLinkBuildUp(intensity: CGFloat) {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    static func pairingLinkExplosion() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred(intensity: 1)
        notify(.success)
    }

    static func pairingCelebrationDismissed() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
        notify(.success)
    }

    static func answerRevealed() {
        notify(.success)
    }

    static func memorySaved() {
        notify(.success)
    }

    static func validationError() {
        notify(.error)
    }

    static func destructiveActionConfirmed() {
        notify(.warning)
    }

    static func streakContinued() {
        impact(.light)
    }

    /// One rung of the streak count-up: a soft tap whose strength rises as the
    /// number climbs, so the celebration feels like pressure building.
    static func streakTick(intensity: CGFloat) {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: max(0, min(intensity, 1)))
    }

    /// The payoff at the top of the streak count-up: a firm hit plus a success
    /// chime the moment the flame fills and the number lands.
    static func streakCelebrated() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred(intensity: 1)
        notify(.success)
    }

    static func drawingSent() {
        impact(.light)
    }

    static func partnerDrawingReceived() {
        impact(.soft)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
