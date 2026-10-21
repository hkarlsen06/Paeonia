import Foundation
import Testing
@testable import PaeoniaApp

struct ConvexTokenScheduleTests {
    @Test func expiryIsReadFromTheTokenPayload() {
        let token = Self.jwt(payload: #"{"aud":"convex","exp":1792598774,"iat":1792597874}"#)

        #expect(ConvexTokenSchedule.expiry(ofJWT: token) == Date(timeIntervalSince1970: 1_792_598_774))
    }

    @Test func tokenIsRefreshedAMinuteBeforeItExpires() {
        let now = Date(timeIntervalSince1970: 1_792_597_874)
        let token = Self.jwt(payload: #"{"exp":1792598774}"#)

        #expect(ConvexTokenSchedule.refreshDelay(forToken: token, now: now) == 840)
    }

    @Test func expiredTokenWaitsTheShortestDelayInsteadOfLooping() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let token = Self.jwt(payload: #"{"exp":1792598774}"#)

        #expect(ConvexTokenSchedule.refreshDelay(forToken: token, now: now) == ConvexTokenSchedule.minimumDelay)
    }

    @Test func unreadableTokenIsRefreshedAfterAMinute() {
        #expect(ConvexTokenSchedule.expiry(ofJWT: "not-a-jwt") == nil)
        #expect(ConvexTokenSchedule.refreshDelay(forToken: "not-a-jwt", now: .now) == 60)
    }

    /// A JWT with an unsigned, base64url payload whose padding is stripped, like Clerk's.
    private static func jwt(payload: String) -> String {
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(encoded).signature"
    }
}
