import Foundation

/// What went wrong in an admin call, read from the server's error. The server
/// errors are `ConvexError { code, message }` (see `PaeoniaConvexError.server`).
nonisolated enum AdminFailure: Equatable, Sendable {
    /// The screen went away. Not a failure to show.
    case cancelled
    case notAdmin
    /// The server refuses to ban yourself or an admin.
    case cannotBan
    case reasonInvalid
    case userNotFound
    /// The report or correction request is gone, for example after its three years.
    case caseNotFound
    case other

    init(_ error: any Error) {
        if error.isCancellation {
            self = .cancelled
            return
        }
        guard case let .server(_, message)? = error as? PaeoniaConvexError else {
            self = .other
            return
        }
        if message.contains("admin access required") {
            self = .notAdmin
        } else if message.contains("can't ban") || message.contains("can't be banned") {
            self = .cannotBan
        } else if message.contains("ban reason must be") {
            self = .reasonInvalid
        } else if message.contains("user not found") {
            self = .userNotFound
        } else if message.contains("report not found") || message.contains("correction request not found") {
            self = .caseNotFound
        } else {
            self = .other
        }
    }
}

/// A message for the shared banner.
nonisolated enum AdminNotice: Equatable, Sendable {
    case loadFailed
    case notAdmin
    case banFailed(PaeoniaFailure)
    case unbanFailed(PaeoniaFailure)
    case cannotBan
    case reasonInvalid
    case userNotFound
    case closeFailed(PaeoniaFailure)
    case caseNotFound
    case banned
    case unbanned
    case caseHandled

    /// The notice for a failed read. Nil when the screen just went away.
    init?(loadError error: any Error) {
        switch AdminFailure(error) {
        case .cancelled: return nil
        case .notAdmin: self = .notAdmin
        case .userNotFound: self = .userNotFound
        case .cannotBan, .reasonInvalid, .caseNotFound, .other: self = .loadFailed
        }
    }

    /// The notice for a report or correction request that could not be marked as handled.
    init?(closeError error: any Error) {
        switch AdminFailure(error) {
        case .cancelled: return nil
        case .notAdmin: self = .notAdmin
        case .caseNotFound: self = .caseNotFound
        case .cannotBan, .reasonInvalid, .userNotFound, .other: self = .closeFailed(PaeoniaFailure(error))
        }
    }

    init?(banError error: any Error) {
        switch AdminFailure(error) {
        case .cancelled: return nil
        case .notAdmin: self = .notAdmin
        case .cannotBan: self = .cannotBan
        case .reasonInvalid: self = .reasonInvalid
        case .userNotFound: self = .userNotFound
        case .caseNotFound, .other: self = .banFailed(PaeoniaFailure(error))
        }
    }

    init?(unbanError error: any Error) {
        switch AdminFailure(error) {
        case .cancelled: return nil
        case .notAdmin: self = .notAdmin
        case .userNotFound: self = .userNotFound
        case .cannotBan, .reasonInvalid, .caseNotFound, .other: self = .unbanFailed(PaeoniaFailure(error))
        }
    }
}

extension AdminNotice {
    var banner: PaeoniaBannerContent {
        switch self {
        case .loadFailed: .error(message: String(localized: .adminErrorLoadFailed))
        case .notAdmin: .error(message: String(localized: .adminErrorNotAdmin))
        // Only a phone without a connection is told to check it.
        case .banFailed(.offline): .error(message: String(localized: .adminErrorBanFailed))
        case .unbanFailed(.offline): .error(message: String(localized: .adminErrorUnbanFailed))
        case .closeFailed(.offline): .error(message: String(localized: .adminErrorMarkHandledFailed))
        case .banFailed(.other), .unbanFailed(.other), .closeFailed(.other):
            .error(message: String(localized: .commonActionFailedMessage))
        case .caseNotFound: .error(message: String(localized: .adminErrorCaseNotFound))
        case .cannotBan: .error(message: String(localized: .adminErrorCannotBan))
        case .reasonInvalid: .error(message: String(localized: .adminErrorReasonInvalid))
        case .userNotFound: .error(message: String(localized: .adminErrorUserNotFound))
        case .banned: .info(message: String(localized: .adminNoticeBanned))
        case .unbanned: .info(message: String(localized: .adminNoticeUnbanned))
        case .caseHandled: .info(message: String(localized: .adminNoticeCaseHandled))
        }
    }
}
