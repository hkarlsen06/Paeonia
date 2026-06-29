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

    /// The message takes the partner's name so notices that name the partner (e.g.
    /// "Oda has answered…") read with the real name; other notices ignore it.
    func message(partnerName: String) -> LocalizedStringResource {
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
            .dailyChallengeEditLockedMessage(partnerName)
        case .editFailed:
            .dailyChallengeEditFailedMessage
        }
    }
}
