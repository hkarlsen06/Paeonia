import Foundation

enum PairingInviteFlowError: Equatable {
    /// The user's own code could not be made or checked. This is the only case that
    /// replaces the screen with the full-screen retry card.
    case createFailed
    /// The other cases are one-off problems that go to the top banner while the
    /// current code stays on screen.
    case replaceFailed
    case joinInvalid
    case joinNotFound
    case joinOwnCode
    case joinCheckFailed
    case joinFailed

    /// Only a phone without a connection is told to check it.
    func message(_ failure: PaeoniaFailure) -> LocalizedStringResource {
        let isOffline = failure == .offline
        return switch self {
        case .createFailed:
            isOffline ? .pairingInviteErrorMessage : .commonActionFailedMessage
        case .replaceFailed:
            isOffline ? .pairingInviteErrorReplaceFailed : .pairingInviteErrorReplaceFailedLater
        case .joinInvalid:
            .pairingJoinErrorInvalid
        case .joinNotFound:
            .pairingJoinErrorNotFound
        case .joinOwnCode:
            .pairingJoinErrorOwnCode
        case .joinCheckFailed:
            isOffline ? .pairingJoinErrorCheckFailed : .pairingJoinErrorCheckFailedLater
        case .joinFailed:
            isOffline ? .pairingJoinErrorJoinFailed : .pairingJoinErrorJoinFailedLater
        }
    }

    /// True when retrying the same code cannot help, so a saved copy should be dropped.
    var isFinalJoinFailure: Bool {
        self == .joinInvalid || self == .joinNotFound || self == .joinOwnCode
    }
}
