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
