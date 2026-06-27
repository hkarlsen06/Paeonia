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
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .loadFailed:
            .dailyChallengeLoadFailedMessage
        case .startFailed:
            .dailyChallengeStartFailedMessage
        case .submitFailed:
            .dailyChallengeSubmitFailedMessage
        case .emptyAnswer:
            .dailyChallengeEmptyAnswerMessage
        case .shuffleLimitReached:
            .dailyChallengeShuffleLimitMessage
        case .shuffleFailed:
            .dailyChallengeShuffleFailedMessage
        case .editLocked:
            .dailyChallengeEditLockedMessage
        case .editFailed:
            .dailyChallengeEditFailedMessage
        }
    }
}
