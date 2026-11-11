import Foundation

/// What went wrong in Mail, in words the person can act on. Only a phone without a connection
/// is told it is offline.
nonisolated enum MailError: Equatable, Sendable {
    case sendOffline
    case sendFailed
    case letterTooLong
    case timePassed
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

    init(sending error: any Error) {
        if PaeoniaFailure(error) == .offline {
            self = .sendOffline
        } else if case .server(code: "22001", _)? = error as? PaeoniaConvexError {
            self = .letterTooLong
        } else {
            self = .sendFailed
        }
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
        }
    }
}
