import ExyteChat
import SwiftUI

// MARK: - ExyteChat setup

extension ThreadChatView {
    var chatLocalization: ChatLocalization {
        ChatLocalization(
            inputPlaceholder: String(localized: .dailyChatComposerPlaceholder),
            signatureText: String(localized: .dailyChatComposerSignature),
            cancelButtonText: String(localized: .dailyChatComposerCancel),
            recentToggleText: String(localized: .dailyChatComposerRecent),
            waitingForNetwork: String(localized: .dailyChatComposerOffline),
            recordingText: String(localized: .dailyChatComposerRecording),
            replyToText: String(localized: .dailyChatComposerReply)
        )
    }

    var chatTheme: ChatTheme {
        ChatTheme(
            colors: .init(
                mainBG: .paeoniaBackgroundPrimary,
                mainTint: .paeoniaAccentPrimary,
                mainText: .paeoniaTextPrimary,
                mainCaptionText: .paeoniaTextSecondary,
                messageMyBG: .paeoniaAccentSecondary,
                messageReadStatus: .paeoniaAccentPrimary,
                messageMyText: .paeoniaTextPrimary,
                messageMyTimeText: .paeoniaTextPrimary.opacity(0.72),
                messageFriendBG: .paeoniaSurfacePrimary,
                messageFriendText: .paeoniaTextPrimary,
                messageFriendTimeText: .paeoniaTextTertiary,
                messageSystemBG: .paeoniaSurfaceSecondary,
                messageSystemText: .paeoniaTextPrimary,
                messageSystemTimeText: .paeoniaTextTertiary,
                inputBG: .paeoniaBackgroundPrimary,
                inputText: .paeoniaTextPrimary,
                inputPlaceholderText: .paeoniaTextTertiary,
                inputSignatureBG: .paeoniaBackgroundSecondary,
                inputSignatureText: .paeoniaTextPrimary,
                inputSignaturePlaceholderText: .paeoniaTextTertiary,
                menuBG: .paeoniaSurfacePrimary,
                menuText: .paeoniaTextPrimary,
                menuTextDelete: .paeoniaError,
                statusError: .paeoniaError,
                statusGray: .paeoniaTextTertiary,
                sendButtonBackground: .paeoniaAccentPrimary,
                recordDot: .paeoniaError
            )
        )
    }
}
