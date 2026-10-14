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
    case other

    init(_ error: any Error) {
        if error is CancellationError {
            self = .cancelled
            return
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
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
        } else {
            self = .other
        }
    }
}

/// A message for the shared top banner.
nonisolated enum AdminNotice: Equatable, Sendable {
    case loadFailed
    case notAdmin
    case banFailed
    case unbanFailed
    case cannotBan
    case reasonInvalid
    case userNotFound
    case banned
    case unbanned

    /// The notice for a failed read. Nil when the screen just went away.
    init?(loadError error: any Error) {
        switch AdminFailure(error) {
        case .cancelled: return nil
        case .notAdmin: self = .notAdmin
        case .userNotFound: self = .userNotFound
        case .cannotBan, .reasonInvalid, .other: self = .loadFailed
        }
    }

    init?(banError error: any Error) {
        switch AdminFailure(error) {
        case .cancelled: return nil
        case .notAdmin: self = .notAdmin
        case .cannotBan: self = .cannotBan
        case .reasonInvalid: self = .reasonInvalid
        case .userNotFound: self = .userNotFound
        case .other: self = .banFailed
        }
    }

    init?(unbanError error: any Error) {
        switch AdminFailure(error) {
        case .cancelled: return nil
        case .notAdmin: self = .notAdmin
        case .userNotFound: self = .userNotFound
        case .cannotBan, .reasonInvalid, .other: self = .unbanFailed
        }
    }
}

extension AdminNotice {
    var banner: PaeoniaBannerContent {
        switch self {
        case .loadFailed: .error(message: String(localized: .adminErrorLoadFailed))
        case .notAdmin: .error(message: String(localized: .adminErrorNotAdmin))
        case .banFailed: .error(message: String(localized: .adminErrorBanFailed))
        case .unbanFailed: .error(message: String(localized: .adminErrorUnbanFailed))
        case .cannotBan: .error(message: String(localized: .adminErrorCannotBan))
        case .reasonInvalid: .error(message: String(localized: .adminErrorReasonInvalid))
        case .userNotFound: .error(message: String(localized: .adminErrorUserNotFound))
        case .banned: .info(message: String(localized: .adminNoticeBanned))
        case .unbanned: .info(message: String(localized: .adminNoticeUnbanned))
        }
    }
}
