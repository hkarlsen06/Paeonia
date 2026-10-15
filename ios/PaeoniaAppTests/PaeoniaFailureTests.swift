import Foundation
import Testing
@testable import PaeoniaApp

/// Only a phone without a connection may be told it is offline.
struct PaeoniaFailureTests {
    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .internationalRoamingOff,
        .callIsActive,
    ])
    func aMissingConnectionIsOffline(_ code: URLError.Code) {
        #expect(PaeoniaFailure(URLError(code)) == .offline)
    }

    @Test func everythingElseIsNotBlamedOnTheConnection() {
        #expect(PaeoniaFailure(URLError(.timedOut)) == .other)
        #expect(PaeoniaFailure(URLError(.badServerResponse)) == .other)
        // A function the server doesn't have, as before a backend deploy.
        let missingFunction = PaeoniaConvexError.server(code: nil, message: "Could not find public function")
        #expect(PaeoniaFailure(missingFunction) == .other)
        #expect(PaeoniaFailure(PaeoniaConvexError.http(status: 503, body: "")) == .other)
        #expect(PaeoniaFailure(CocoaError(.coderReadCorrupt)) == .other)
    }
}
