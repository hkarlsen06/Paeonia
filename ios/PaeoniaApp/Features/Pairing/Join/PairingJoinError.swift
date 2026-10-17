import Foundation

/// Why checking or joining a partner's code did not work.
enum PairingJoinError: Equatable {
    case invalid
    case notFound
    case ownCode
    case checkFailed(PaeoniaFailure)
    case joinFailed(PaeoniaFailure)

    /// Only a phone without a connection is told to check it.
    var message: LocalizedStringResource {
        switch self {
        case .invalid:
            .pairingJoinErrorInvalid
        case .notFound:
            .pairingJoinErrorNotFound
        case .ownCode:
            .pairingJoinErrorOwnCode
        case let .checkFailed(failure):
            failure == .offline ? .pairingJoinErrorCheckFailed : .pairingJoinErrorCheckFailedLater
        case let .joinFailed(failure):
            failure == .offline ? .pairingJoinErrorJoinFailed : .pairingJoinErrorJoinFailedLater
        }
    }

    /// True when trying the same code again cannot help, so a saved copy should go.
    var isFinal: Bool {
        switch self {
        case .invalid, .notFound, .ownCode:
            true
        case .checkFailed, .joinFailed:
            false
        }
    }
}
