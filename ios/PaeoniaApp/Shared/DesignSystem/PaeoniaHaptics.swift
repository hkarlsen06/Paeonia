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

    /// The heart burst on the Us-tab card the day a relationship milestone lands.
    static func milestoneReached() {
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

    static func drawingSaved() {
        impact(.rigid, intensity: 0.78)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else {
                return
            }

            impact(.soft, intensity: 0.55)
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else {
                return
            }

            notify(.success)
        }
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

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat? = nil) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()

        if let intensity {
            generator.impactOccurred(intensity: max(0, min(intensity, 1)))
        } else {
            generator.impactOccurred()
        }
    }
}
