import AuthenticationServices
import Foundation
import Testing
@testable import PaeoniaApp

/// No sheet is shown. Each test plays the system's part through the delegate.
@MainActor
struct AppleSignInServiceTests {
    @MainActor
    private final class SheetLog {
        var controllers: [ASAuthorizationController] = []

        var count: Int {
            controllers.count
        }
    }

    private enum SheetFailure: Error {
        case first
        case second
    }

    private func makeService() -> (AppleSignInService, SheetLog) {
        let log = SheetLog()
        return (AppleSignInService { log.controllers.append($0) }, log)
    }

    @Test(.timeLimit(.minutes(1)))
    func aNewAttemptStartsWhenAnEarlierSheetNeverReportedBack() async throws {
        let (service, log) = makeService()
        let stuck = Task { try await service.signIn() }
        #expect(await waitUntil { await log.count == 1 })

        let retry = Task { try await service.signIn() }
        #expect(await waitUntil { await log.count == 2 })

        await expectCancelled(stuck)
        service.authorizationController(controller: log.controllers[1], didCompleteWithError: SheetFailure.first)
        await #expect(throws: SheetFailure.first) { _ = try await retry.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func aLateCallbackFromAnOldSheetDoesNotEndTheNewAttempt() async throws {
        let (service, log) = makeService()
        let old = Task { try await service.signIn() }
        #expect(await waitUntil { await log.count == 1 })
        let current = Task { try await service.signIn() }
        #expect(await waitUntil { await log.count == 2 })
        await expectCancelled(old)

        service.authorizationController(controller: log.controllers[0], didCompleteWithError: SheetFailure.first)
        service.authorizationController(controller: log.controllers[1], didCompleteWithError: SheetFailure.second)

        await #expect(throws: SheetFailure.second) { _ = try await current.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheCallerEndsTheAttemptAndTheNextOneWorks() async throws {
        let (service, log) = makeService()
        let abandoned = Task { try await service.signIn() }
        #expect(await waitUntil { await log.count == 1 })

        abandoned.cancel()
        await expectCancelled(abandoned)

        let next = Task { try await service.signIn() }
        #expect(await waitUntil { await log.count == 2 })
        service.authorizationController(controller: log.controllers[1], didCompleteWithError: SheetFailure.first)
        await #expect(throws: SheetFailure.first) { _ = try await next.value }
    }

    /// Root shows no banner for this error, like when the person closes the sheet.
    private func expectCancelled(_ attempt: Task<AppleSignInCredential, any Error>) async {
        do {
            _ = try await attempt.value
            Issue.record("Expected the attempt to end as cancelled")
        } catch let error as ASAuthorizationError {
            #expect(error.code == .canceled)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}
