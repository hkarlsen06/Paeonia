import Foundation

extension PartnerNicknameEditorModel.Event {
    /// The banner the Us tab shows for the result of a save.
    var banner: PaeoniaBannerContent {
        switch self {
        case let .saved(nickname?):
            .info(
                title: String(localized: .settingsPartnerNicknameSavedTitle),
                message: String(localized: .settingsPartnerNicknameSavedMessage(nickname))
            )
        case .saved(nil):
            .info(
                title: String(localized: .settingsPartnerNicknameRemovedTitle),
                message: String(localized: .settingsPartnerNicknameRemovedMessage)
            )
        case let .saveFailed(failure):
            .error(
                title: String(localized: .settingsPartnerNicknameSaveFailedTitle),
                message: String(
                    localized: failure == .offline
                        ? .settingsPartnerNicknameSaveFailedOffline
                        : .settingsPartnerNicknameSaveFailedOther
                )
            )
        }
    }
}
