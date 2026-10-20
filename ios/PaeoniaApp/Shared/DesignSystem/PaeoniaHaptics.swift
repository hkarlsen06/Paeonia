import UIKit

@MainActor
enum PaeoniaHaptics {
    static func pairedSuccessfully() {
        notify(.success)
    }

    /// Sign-in finished and the next screen has arrived — the moment the user knows
    /// login worked.
    static func signedIn() {
        notify(.success)
    }

    /// The profile setup Continue button: a light send-off tap while the save and the
    /// next screen take over.
    static func profileSetupSent() {
        impact(.light)
    }

    /// Profile setup: the cropped photo landed in the avatar.
    static func profilePhotoSet() {
        impact(.soft, intensity: 0.8)
    }

    /// The join screen's Join button: a light tap while the join runs. The pairing
    /// celebration that follows has its own success haptics.
    static func partnerJoinSent() {
        impact(.light)
    }

    static func pairingLinkBuildUp(intensity: CGFloat) {
        impact(.soft, intensity: intensity)
    }

    static func pairingLinkExplosion() {
        impact(.heavy, intensity: 1)
        notify(.success)
    }

    /// Tapping the button that leaves a celebration, such as a streak milestone.
    static func celebrationContinued() {
        impact(.medium, intensity: 0.85)
    }

    static func pairingCelebrationDismissed() {
        impact(.medium, intensity: 0.85)
        notify(.success)
    }

    /// The heart burst on the Home tab card the day a relationship milestone lands.
    static func milestoneReached() {
        notify(.success)
    }

    static func answerRevealed() {
        notify(.success)
    }

    /// One of the soft taps that build up while the partner's answer is about to show
    /// in the chat.
    static func revealBuildUp(intensity: CGFloat) {
        impact(.soft, intensity: intensity)
    }

    /// The partner's answer lands in the chat after the build-up: a firm hit and a
    /// success.
    static func partnerAnswerLanded() {
        impact(.heavy, intensity: 1)
        notify(.success)
    }

    /// Both partners picked the same person on a "who is more likely" question.
    /// A small tap that sits next to the reveal's own success haptic.
    static func partnerChoiceMatched() {
        impact(.soft, intensity: 0.8)
    }

    static func memorySaved() {
        notify(.success)
    }

    /// Onboarding found the Paeonia widget on the Home Screen after the person
    /// went to add it.
    static func widgetAdded() {
        impact(.medium, intensity: 0.9)
        notify(.success)
    }

    /// Onboarding saved the time the question reminder comes.
    static func questionTimeSaved() {
        notify(.success)
    }

    /// The seal on the partner's first drawing breaks: a crisp snap, then a soft
    /// give as the envelope opens.
    static func giftUnwrapped() {
        impact(.rigid, intensity: 0.75)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else {
                return
            }

            impact(.soft, intensity: 0.5)
        }
    }

    /// The last stroke of the partner's first drawing lands.
    static func giftReplayFinished() {
        impact(.medium, intensity: 0.8)
        notify(.success)
    }

    /// One of the inviter's first answers was saved and the next page slides in.
    static func firstDayAnswerSaved() {
        impact(.soft, intensity: 0.8)
    }

    static func storyShared() {
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
        impact(.soft, intensity: intensity)
    }

    /// The payoff at the top of the streak count-up: a firm hit plus a success
    /// chime the moment the flame fills and the number lands.
    static func streakCelebrated() {
        impact(.heavy, intensity: 1)
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

    /// A game's main button that moves on without sending anything, such as
    /// "Continue" after a reveal or "Play" on the hub. The same light tap as the
    /// buttons that send a move, so every pink button in a game answers the finger.
    static func gameContinued() {
        impact(.light)
    }

    static func partnerDrawingReceived() {
        impact(.soft)
    }

    /// The partner's hearts start flying across the Home card.
    static func heartsReceived() {
        impact(.soft)
    }

    /// A full word that is not the answer. Two soft taps, because a wrong guess
    /// in a game is not an error.
    static func gameWrongGuess() {
        impact(.soft)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else {
                return
            }

            impact(.soft)
        }
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    // One generator per type, reused so `prepare()` after each fire keeps the
    // Taptic Engine warm for the next one.
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat? = nil) {
        let generator = impactGenerators[style] ?? UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator

        if let intensity {
            generator.impactOccurred(intensity: max(0, min(intensity, 1)))
        } else {
            generator.impactOccurred()
        }
        generator.prepare()
    }
}
