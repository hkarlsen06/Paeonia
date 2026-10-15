import Foundation

/// What a failed server call means for the person, so a screen tells them the
/// truth. Only a phone without a connection is told it is offline. Everything
/// else, such as a server error, a refusal or a timeout, may happen on a working
/// connection, so its copy must not blame the person's internet.
nonisolated enum PaeoniaFailure: Equatable, Sendable {
    /// The phone has no internet connection.
    case offline
    /// The call failed for another reason. The connection may be fine.
    case other

    init(_ error: any Error) {
        guard let urlError = error as? URLError else {
            self = .other
            return
        }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed,
             .internationalRoamingOff,
             .callIsActive:
            self = .offline
        default:
            self = .other
        }
    }
}
