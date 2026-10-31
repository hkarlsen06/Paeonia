import Foundation

extension ThreadChatViewModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .loadFailed: .dailyChatErrorLoadTitle
        case .sendFailed: .dailyChatErrorSendTitle
        case .deliveryFailed: .dailyChatErrorDeliveryTitle
        case .messageTooLong: .dailyChatErrorTooLongTitle
        case .unavailable: .dailyChatErrorUnavailableTitle
        case .voiceFailed: .dailyChatErrorVoiceTitle
        case .voiceDraftReadFailed: .chatPhotoDraftReadFailedTitle
        case .voiceDraftSaveFailed: .chatPhotoDraftSaveFailedTitle
        case .photoFailed: .dailyChatErrorPhotoTitle
        case .photoDraftReadFailed: .chatPhotoDraftReadFailedTitle
        case .photoDraftSaveFailed: .chatPhotoDraftSaveFailedTitle
        case .editFailed: .dailyChatErrorEditTitle
        case .editWindowClosed: .dailyChatErrorEditClosedTitle
        case .reactionFailed: .reactionsErrorTitle
        case .deleteFailed: .dailyChatErrorDeleteTitle
        case .deleteWaiting: .dailyChatErrorDeleteWaitingTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        // Only a phone without a connection is told to check it.
        case .loadFailed(let failure):
            failure == .offline ? .dailyChatErrorLoadMessage : .commonLoadFailedMessage
        case .sendFailed: .dailyChatErrorSendMessage
        case .deliveryFailed: .dailyChatErrorDeliveryMessage
        case .messageTooLong: .dailyChatErrorTooLongMessage
        case .unavailable: .dailyChatErrorUnavailableMessage
        case .voiceFailed: .dailyChatErrorVoiceMessage
        case .voiceDraftReadFailed: .chatVoiceDraftRestoreFailed
        case .voiceDraftSaveFailed: .chatVoiceDraftSaveFailedMessage
        case .photoFailed: .dailyChatErrorPhotoMessage
        case .photoDraftReadFailed: .chatPhotoDraftReadFailedMessage
        case .photoDraftSaveFailed: .chatPhotoDraftSaveFailedMessage
        case .editFailed(let failure):
            failure == .offline ? .dailyChatErrorEditMessage : .dailyChatErrorEditFailedMessage
        case .editWindowClosed: .dailyChatErrorEditClosedMessage
        case .reactionFailed(let failure):
            failure == .offline ? .reactionsErrorOffline : .reactionsErrorFailed
        case .deleteFailed: .dailyChatErrorDeleteMessage
        case .deleteWaiting: .dailyChatErrorDeleteWaitingMessage
        }
    }
}
