import Foundation

enum PairingInviteFlowError: Equatable {
    /// The user's own code could not be made or checked. This is the only case that
    /// replaces the screen with the full-screen retry card.
    case createFailed
    /// A new code could not be made. This goes to the top banner while the current
    /// code stays on screen.
    case replaceFailed

    /// Only a phone without a connection is told to check it.
    func message(_ failure: PaeoniaFailure) -> LocalizedStringResource {
        let isOffline = failure == .offline
        return switch self {
        case .createFailed:
            isOffline ? .pairingInviteErrorMessage : .commonActionFailedMessage
        case .replaceFailed:
            isOffline ? .pairingInviteErrorReplaceFailed : .pairingInviteErrorReplaceFailedLater
        }
    }
}
