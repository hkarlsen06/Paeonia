import Foundation

extension DailyChallengeViewModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .loadFailed:
            .dailyChallengeLoadFailedTitle
        case .startFailed:
            .dailyChallengeStartFailedTitle
        case .submitFailed:
            .dailyChallengeSubmitFailedTitle
        case .emptyAnswer:
            .dailyChallengeEmptyAnswerTitle
        case .shuffleLimitReached:
            .dailyChallengeShuffleLimitTitle
        case .shuffleFailed:
            .dailyChallengeShuffleFailedTitle
        case .editLocked:
            .dailyChallengeEditLockedTitle
        case .editFailed:
            .dailyChallengeEditFailedTitle
        case .photoFailed:
            .dailyChallengePhotoFailedTitle
        case .voiceFailed:
            .dailyChallengeVoiceFailedTitle
        case .dayEnded:
            .dailyChallengeDayEndedTitle
        }
    }

    /// The message takes the partner's name so notices that name the partner (e.g.
    /// "Oda has answered…") read with the real name; other notices ignore it.
    func message(partnerName: String) -> LocalizedStringResource { // swiftlint:disable:this cyclomatic_complexity
        switch self {
        // Only a phone without a connection is told to check it.
        case .loadFailed(let failure):
            failure == .offline ? .dailyChallengeLoadFailedMessage : .commonLoadFailedMessage
        case .startFailed(let failure):
            failure == .offline ? .dailyChallengeStartFailedMessage : .commonActionFailedMessage
        case .submitFailed:
            .dailyChallengeSubmitFailedMessage
        case .emptyAnswer:
            .dailyChallengeEmptyAnswerMessage
        case .shuffleLimitReached:
            .dailyChallengeShuffleLimitMessage
        case .shuffleFailed(let failure):
            failure == .offline ? .dailyChallengeShuffleFailedMessage : .commonActionFailedMessage
        case .editLocked:
            .dailyChallengeEditLockedMessage(partnerName)
        case .editFailed:
            .dailyChallengeEditFailedMessage
        case .photoFailed:
            .dailyChallengePhotoFailedMessage
        case .voiceFailed:
            .dailyChallengeVoiceFailedMessage
        case .dayEnded:
            .dailyChallengeDayEndedMessage
        }
    }
}
