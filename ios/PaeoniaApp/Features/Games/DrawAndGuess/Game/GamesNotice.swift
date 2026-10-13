import Foundation

/// A problem to tell the person about, shown through the shared top banner.
/// The copy says what happened and what to do next. Errors are logged in debug
/// builds only.
nonisolated enum GamesNotice: Equatable, Sendable {
    case couldNotSaveSettings
    case couldNotStartGame
    /// The picked word was no longer on offer, so new choices are shown.
    case wordRejected
    /// The same, and the drawing made for that word waits on the canvas of the next round.
    case wordRejectedDrawingKept
    /// A drawing could not be sent and is back on the canvas.
    case drawingRejected
    case drawingUnavailable
    /// The drawing is bigger than the server accepts.
    case drawingTooBig
    /// Saving to Memories failed for good.
    case saveRejected
    /// A guess or give up was refused for good. The round is still open.
    case moveRejected
    /// Queueing a move on the phone failed.
    case couldNotSaveMove
    case couldNotSendInvite

    init(_ stored: GameStoredNotice) {
        switch stored {
        case .wordRejected: self = .wordRejected
        case .wordRejectedDrawingKept: self = .wordRejectedDrawingKept
        case .drawingRejected: self = .drawingRejected
        case .saveRejected: self = .saveRejected
        case .moveRejected: self = .moveRejected
        }
    }

    @MainActor
    var banner: PaeoniaBannerContent {
        .error(title: String(localized: title), message: String(localized: message))
    }

    private var title: LocalizedStringResource {
        switch self {
        case .couldNotSaveSettings: .gamesNoticeSettingsFailedTitle
        case .couldNotStartGame: .gamesNoticeStartFailedTitle
        case .wordRejected, .wordRejectedDrawingKept: .gamesNoticeWordRejectedTitle
        case .drawingRejected: .gamesNoticeDrawingRejectedTitle
        case .drawingUnavailable: .gamesNoticeDrawingUnavailableTitle
        case .drawingTooBig: .gamesNoticeDrawingTooBigTitle
        case .saveRejected: .gamesNoticeSaveRejectedTitle
        case .moveRejected: .gamesNoticeMoveRejectedTitle
        case .couldNotSaveMove: .gamesNoticeMoveFailedTitle
        case .couldNotSendInvite: .gamesNoticeInviteFailedTitle
        }
    }

    private var message: LocalizedStringResource {
        switch self {
        case .couldNotSaveSettings: .gamesNoticeSettingsFailedMessage
        case .couldNotStartGame: .gamesNoticeStartFailedMessage
        case .wordRejected: .gamesNoticeWordRejectedMessage
        case .wordRejectedDrawingKept: .gamesNoticeWordRejectedKeptDrawingMessage
        case .drawingRejected: .gamesNoticeDrawingRejectedMessage
        case .drawingUnavailable: .gamesNoticeDrawingUnavailableMessage
        case .drawingTooBig: .gamesNoticeDrawingTooBigMessage
        case .saveRejected: .gamesNoticeSaveRejectedMessage
        case .moveRejected: .gamesNoticeMoveRejectedMessage
        case .couldNotSaveMove: .gamesNoticeMoveFailedMessage
        case .couldNotSendInvite: .gamesNoticeInviteFailedMessage
        }
    }
}
