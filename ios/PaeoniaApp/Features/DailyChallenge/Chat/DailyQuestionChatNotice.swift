import Foundation

extension DailyQuestionChatViewModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .loadFailed: .dailyChatErrorLoadTitle
        case .sendFailed: .dailyChatErrorSendTitle
        case .deliveryFailed: .dailyChatErrorDeliveryTitle
        case .messageTooLong: .dailyChatErrorTooLongTitle
        case .unavailable: .dailyChatErrorUnavailableTitle
        case .voiceFailed: .dailyChatErrorVoiceTitle
        case .photoFailed: .dailyChatErrorPhotoTitle
        case .editFailed: .dailyChatErrorEditTitle
        case .editWindowClosed: .dailyChatErrorEditClosedTitle
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
        case .photoFailed: .dailyChatErrorPhotoMessage
        case .editFailed(let failure):
            failure == .offline ? .dailyChatErrorEditMessage : .dailyChatErrorEditFailedMessage
        case .editWindowClosed: .dailyChatErrorEditClosedMessage
        }
    }
}
