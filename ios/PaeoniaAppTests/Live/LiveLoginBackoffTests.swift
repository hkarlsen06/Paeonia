import Testing
@testable import PaeoniaApp

struct LiveLoginBackoffTests {
    @Test func delayDoublesFromOneSecondAndCapsAtThirty() {
        var backoff = LiveLoginBackoff()
        let delays = (0..<8).map { _ in backoff.nextDelay() }

        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30].map { Duration.seconds($0) })
    }

    @Test func aSocketStillLoggedInAsThePreviousAccountIsNotUsed() {
        let isLoggedIn = LiveConvexConnection.isLoggedIn(as:isAuthenticated:authenticatedAccountID:)
        // Sign-out of A did not clear the socket, and B is signed in now.
        #expect(!isLoggedIn("user_b", true, "user_a"))
        // Nobody is signed in to Clerk.
        #expect(!isLoggedIn(nil, true, "user_a"))
        #expect(isLoggedIn("user_b", true, "user_b"))
        #expect(!isLoggedIn("user_b", false, "user_b"))
    }
}
