import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct ProfilePhotoRetryTests {
    @Test func failedLoadIsTriedAgainUntilItSucceeds() async {
        var attempts = 0
        var failures = 0

        let value = await ProfilePhotoRetry.load(delays: [.zero], onFailure: { failures += 1 }) { () async -> Int? in
            attempts += 1
            return attempts == 3 ? attempts : nil
        }

        #expect(value == 3)
        #expect(failures == 2)
    }

    @Test func cancellingTheTaskEndsTheRetries() async {
        let attempts = AttemptCounter()
        let task = Task { @MainActor in
            await ProfilePhotoRetry.load(delays: [.seconds(60)]) { () async -> Int? in
                attempts.count += 1
                return nil
            }
        }
        while attempts.count < 1 {
            await Task.yield()
        }

        task.cancel()

        #expect(await task.value == nil)
        #expect(attempts.count == 1)
    }
}

@MainActor
private final class AttemptCounter {
    var count = 0
}
