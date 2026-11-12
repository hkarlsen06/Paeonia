import Foundation

/// What went wrong in Mail, in words the person can act on. Only a phone without a connection
/// is told it is offline.
nonisolated enum MailError: Equatable, Sendable {
    case sendOffline
    case sendFailed
    case letterTooLong
    case timePassed
    /// The birthday morning a birthday card was set for passed before it was sent, so it now
    /// goes at once.
    case birthdayPassed
    /// The server would not take a letter for the next meeting, as when the visit was deleted.
    case meetingUnavailable
    /// The letter had already reached the server when the author changed it and sent again.
    /// The changes stay as a new letter.
    case changesNotAdded
    case photoUnreadable
    case photoMissing
    case openOffline
    case openFailed
    case letterGone
    case deleteOffline
    case deleteFailed
    case loadOffline
    case loadFailed
    /// The letter being changed arrived first, so the changes stay as a new letter.
    case changeTooLate
    /// The same, and a photo the letter kept stays with the letter that arrived.
    case changeTooLatePhotoStays
    /// The letter being changed was unsent first, so the changes stay as a new letter.
    case changeLetterGone
    /// The same, and a photo the letter kept went with it.
    case changeLetterGonePhotoStays
    /// The save may have reached the server, but no answer said so.
    case changeUnconfirmed
    /// The connection dropped during the save, which may have reached the server.
    case changeUnconfirmedOffline
    /// The change kept a photo that another phone replaced or removed since.
    case changePhotoChanged
    case changeOffline
    /// The server would not move the letter being changed to the next meeting.
    case changeMeetingUnavailable
    case changeFailed
    case finishOtherLetterFirst

    init(sending error: any Error) {
        if PaeoniaFailure(error) == .offline {
            self = .sendOffline
        } else if case .server(code: "22001", _)? = error as? PaeoniaConvexError {
            self = .letterTooLong
        } else if case .server(code: "55000", _)? = error as? PaeoniaConvexError {
            self = .meetingUnavailable
        } else {
            self = .sendFailed
        }
    }

    /// A server refusal rolls the whole save back, and a phone without a connection never sent
    /// it. Any other failure, such as a timeout or a dropped connection, may come after the
    /// server saved the change, so the change is not called unsaved.
    init(changing error: any Error) {
        if let error = error as? PaeoniaConvexError {
            self = Self(refusing: error)
        } else if let error = error as? URLError, Self.neverSent.contains(error.code) {
            self = .changeOffline
        } else {
            self = PaeoniaFailure(error) == .offline ? .changeUnconfirmedOffline : .changeUnconfirmed
        }
    }

    private init(refusing error: PaeoniaConvexError) {
        switch error {
        case .server(code: "40001", _): self = .changeTooLate
        case .server(code: "55000", _): self = .changeMeetingUnavailable
        case .server(code: "P0002", _): self = .changeLetterGone
        case .server(code: "22001", _): self = .letterTooLong
        case .server(code: "23514", _): self = .changePhotoChanged
        case .server, .notAuthenticated: self = .changeFailed
        case .http: self = .changeUnconfirmed
        }
    }

    /// Connection errors that stop a request before it leaves the phone.
    private static let neverSent: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]

    /// `.changeTooLate` or `.changeLetterGone` for a change whose kept photo stayed behind.
    var withPhotoLeftBehind: MailError {
        switch self {
        case .changeTooLate: .changeTooLatePhotoStays
        case .changeLetterGone: .changeLetterGonePhotoStays
        default: self
        }
    }

    /// Something that happened rather than went wrong, so it stays until the person dismisses it.
    var isNews: Bool {
        [
            .changesNotAdded, .changeTooLate, .changeTooLatePhotoStays, .changeLetterGone,
            .changeLetterGonePhotoStays, .changePhotoChanged,
        ].contains(self)
    }

    init(opening error: any Error) {
        if PaeoniaFailure(error) == .offline {
            self = .openOffline
        } else if case .server(code: "P0002", _)? = error as? PaeoniaConvexError {
            self = .letterGone
        } else {
            self = .openFailed
        }
    }

    var message: String {
        switch self {
        case .sendOffline: String(localized: .mailErrorSendOffline)
        case .sendFailed: String(localized: .mailErrorSendFailed)
        case .letterTooLong: String(localized: .mailErrorTooLong)
        case .timePassed: String(localized: .mailErrorTimePassed)
        case .birthdayPassed: String(localized: .mailErrorBirthdayPassed)
        case .meetingUnavailable: String(localized: .mailErrorMeetingUnavailable)
        case .changesNotAdded: String(localized: .mailErrorChangesNotAdded)
        case .photoUnreadable: String(localized: .mailErrorPhotoUnreadable)
        case .photoMissing: String(localized: .mailErrorPhotoMissing)
        case .openOffline: String(localized: .mailErrorOpenOffline)
        case .openFailed: String(localized: .mailErrorOpenFailed)
        case .letterGone: String(localized: .mailErrorLetterGone)
        case .deleteOffline: String(localized: .mailErrorDeleteOffline)
        case .deleteFailed: String(localized: .mailErrorDeleteFailed)
        case .loadOffline: String(localized: .mailErrorLoadOffline)
        case .loadFailed: String(localized: .mailErrorLoadFailed)
        case .changeTooLate: String(localized: .mailErrorChangeTooLate)
        case .changeTooLatePhotoStays: String(localized: .mailErrorChangeTooLatePhotoStays)
        case .changeLetterGone: String(localized: .mailErrorChangeLetterGone)
        case .changeLetterGonePhotoStays: String(localized: .mailErrorChangeLetterGonePhotoStays)
        case .changeUnconfirmed: String(localized: .mailErrorChangeUnconfirmed)
        case .changeUnconfirmedOffline: String(localized: .mailErrorChangeUnconfirmedOffline)
        case .changePhotoChanged: String(localized: .mailErrorChangePhotoChanged)
        case .changeOffline: String(localized: .mailErrorChangeOffline)
        case .changeMeetingUnavailable: String(localized: .mailErrorChangeMeetingUnavailable)
        case .changeFailed: String(localized: .mailErrorChangeFailed)
        case .finishOtherLetterFirst: String(localized: .mailErrorFinishOtherLetter)
        }
    }
}
