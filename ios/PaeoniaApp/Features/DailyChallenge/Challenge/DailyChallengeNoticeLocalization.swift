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
        case .photoFailed:
            .dailyChallengePhotoFailedTitle
        case .voiceFailed:
            .dailyChallengeVoiceFailedTitle
        case .dayEnded:
            .dailyChallengeDayEndedTitle
        }
    }

    var message: LocalizedStringResource {
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
        case .photoFailed:
            .dailyChallengePhotoFailedMessage
        case .voiceFailed:
            .dailyChallengeVoiceFailedMessage
        case .dayEnded:
            .dailyChallengeDayEndedMessage
        }
    }
}
