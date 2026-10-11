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

    var message: LocalizedStringResource {
        switch self {
        case .createFailed:
            .pairingInviteErrorMessage
        case .replaceFailed:
            .pairingInviteErrorReplaceFailed
        case .joinInvalid:
            .pairingJoinErrorInvalid
        case .joinNotFound:
            .pairingJoinErrorNotFound
        case .joinOwnCode:
            .pairingJoinErrorOwnCode
        case .joinCheckFailed:
            .pairingJoinErrorCheckFailed
        case .joinFailed:
            .pairingJoinErrorJoinFailed
        }
    }

    /// True when retrying the same code cannot help, so a saved copy should be dropped.
    var isFinalJoinFailure: Bool {
        self == .joinInvalid || self == .joinNotFound || self == .joinOwnCode
    }
}
