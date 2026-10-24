import Foundation
import StoreKit

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
        // StoreKit keeps the network error in its own case, out of `userInfo`.
        if case let .networkError(urlError)? = error as? StoreKitError {
            self.init(urlError)
            return
        }
        guard let urlError = error as? URLError else {
            // Frameworks such as MapKit wrap the network error in their own.
            if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error {
                self.init(underlying)
            } else {
                self = .other
            }
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
