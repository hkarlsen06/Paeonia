import Foundation

/// A problem to tell the person about, shown through the shared top banner.
/// The copy says what happened and what to do next. Errors are logged in debug
/// builds only.
nonisolated enum GamesNotice: Equatable, Sendable {
    case couldNotSaveSettings(PaeoniaFailure)
    case couldNotStartGame(PaeoniaFailure)
    /// The picked word was no longer on offer, so new choices are shown.
    case wordRejected
    /// The same, and the drawing made for that word waits on the canvas of the next round.
    case wordRejectedDrawingKept
    /// A drawing could not be sent and is back on the canvas.
    case drawingRejected
    case drawingUnavailable
    /// The drawing is bigger than the server accepts.
    case drawingTooBig
    /// A guess or give up was refused for good. The round is still open.
    case moveRejected
    /// Queueing a move on the phone failed.
    case couldNotSaveMove
    case couldNotSendInvite(PaeoniaFailure)
    /// An Exquisite corpse part could not be sent and is back on the canvas.
    case exquisiteCorpsePartRejected

    init(_ stored: GameStoredNotice) {
        switch stored {
        case .wordRejected: self = .wordRejected
        case .wordRejectedDrawingKept: self = .wordRejectedDrawingKept
        case .drawingRejected: self = .drawingRejected
        case .moveRejected: self = .moveRejected
        }
    }

    @MainActor
    var banner: PaeoniaBannerContent {
        .error(title: title.map { String(localized: $0) }, message: String(localized: message))
    }

    /// The banner's bold line. A notice whose message says it all has none.
    private var title: LocalizedStringResource? {
        switch self {
        case .couldNotSaveSettings: .gamesNoticeSettingsFailedTitle
        case .couldNotStartGame: .gamesNoticeStartFailedTitle
        case .wordRejected, .wordRejectedDrawingKept: .gamesNoticeWordRejectedTitle
        case .drawingRejected: .gamesNoticeDrawingRejectedTitle
        case .drawingUnavailable: .gamesNoticeDrawingUnavailableTitle
        case .drawingTooBig: .gamesNoticeDrawingTooBigTitle
        case .moveRejected: .gamesNoticeMoveRejectedTitle
        case .couldNotSaveMove: .gamesNoticeMoveFailedTitle
        case .couldNotSendInvite: .gamesNoticeInviteFailedTitle
        case .exquisiteCorpsePartRejected: nil
        }
    }

    /// A call that failed tells the person to check their connection only when the
    /// phone is offline.
    private var message: LocalizedStringResource {
        switch self {
        case .couldNotSaveSettings(.offline): .gamesNoticeSettingsFailedMessage
        case .couldNotStartGame(.offline): .gamesNoticeStartFailedMessage
        case .couldNotSendInvite(.offline): .gamesNoticeInviteFailedMessage
        case .couldNotSaveSettings(.other), .couldNotStartGame(.other), .couldNotSendInvite(.other):
            .commonActionFailedMessage
        case .wordRejected: .gamesNoticeWordRejectedMessage
        case .wordRejectedDrawingKept: .gamesNoticeWordRejectedKeptDrawingMessage
        case .drawingRejected: .gamesNoticeDrawingRejectedMessage
        case .drawingUnavailable: .gamesNoticeDrawingUnavailableMessage
        case .drawingTooBig: .gamesNoticeDrawingTooBigMessage
        case .moveRejected: .gamesNoticeMoveRejectedMessage
        case .couldNotSaveMove: .gamesNoticeMoveFailedMessage
        case .exquisiteCorpsePartRejected: .exquisiteCorpseNoticePartRejected
        }
    }
}
