import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct AppLockModelTests {
    private nonisolated final class FakeStore: AppLockPersisting {
        var isEnabled = false
        var timeout: AppLockTimeout = .default
        func clear() {
            isEnabled = false
            timeout = .default
        }
    }

    private final class FakeAuthenticator: AppLockAuthenticating {
        var canAuthenticate = true
        var result: AppLockAuthResult = .cancelled
        func capability() -> AppLockCapability {
            AppLockCapability(biometry: .faceID, canAuthenticate: canAuthenticate)
        }
        // swiftlint:disable:next async_without_await
        func authenticate(reason: String) async -> AppLockAuthResult { result }
    }

    private final class FakeClock {
        var instant = ContinuousClock.now
    }

    private struct Fixture {
        let store = FakeStore()
        let authenticator = FakeAuthenticator()
        let clock = FakeClock()
        let model: AppLockModel

        init(enabled: Bool, timeout: AppLockTimeout = .afterOneMinute) {
            store.isEnabled = enabled
            store.timeout = timeout
            let clock = clock
            model = AppLockModel(store: store, authenticator: authenticator, now: { clock.instant })
        }

        /// A trip to the background of `seconds`, ending with the app in front.
        func leaveAndReturn(afterSeconds seconds: Int) {
            model.sceneWillResignActive()
            model.sceneDidEnterBackground()
            clock.instant += .seconds(seconds)
            model.sceneDidBecomeActive()
        }
    }

    @Test func coldLaunchIsLockedOnlyWhenEnabled() {
        #expect(Fixture(enabled: true).model.isLocked)
        #expect(!Fixture(enabled: false).model.isLocked)
    }

    @Test func inactiveAloneKeepsAnUnlockedAppUnlocked() async {
        let fixture = Fixture(enabled: true, timeout: .immediately)
        fixture.authenticator.result = .success
        await fixture.model.unlock()
        #expect(!fixture.model.isLocked)

        fixture.model.sceneWillResignActive()
        #expect(fixture.model.isShielding)
        #expect(fixture.model.isCovering)
        fixture.model.sceneDidBecomeActive()

        #expect(!fixture.model.isLocked)
        #expect(!fixture.model.isCovering)
    }

    @Test func returningWithinTheGracePeriodStaysUnlocked() async {
        let fixture = Fixture(enabled: true, timeout: .afterOneMinute)
        fixture.authenticator.result = .success
        await fixture.model.unlock()

        fixture.leaveAndReturn(afterSeconds: 30)

        #expect(!fixture.model.isLocked)
    }

    @Test func returningAfterTheGracePeriodLocks() async {
        let fixture = Fixture(enabled: true, timeout: .afterOneMinute)
        fixture.authenticator.result = .success
        await fixture.model.unlock()
        fixture.authenticator.result = .cancelled

        fixture.leaveAndReturn(afterSeconds: 61)

        #expect(fixture.model.isLocked)
    }

    @Test func immediatelyLocksOnAnyTripToTheBackground() async {
        let fixture = Fixture(enabled: true, timeout: .immediately)
        fixture.authenticator.result = .success
        await fixture.model.unlock()
        fixture.authenticator.result = .cancelled

        fixture.leaveAndReturn(afterSeconds: 0)

        #expect(fixture.model.isLocked)
    }

    @Test func cancellingThePromptKeepsTheAppLocked() async {
        let fixture = Fixture(enabled: true)
        fixture.authenticator.result = .cancelled
        await fixture.model.unlock()
        #expect(fixture.model.isLocked)
        #expect(!fixture.model.lastUnlockFailed)

        fixture.authenticator.result = .failed
        await fixture.model.unlock()
        #expect(fixture.model.isLocked)
        #expect(fixture.model.lastUnlockFailed)
    }

    @Test func aPhoneWithoutAPasscodeNeverShutsThePersonOut() async {
        let fixture = Fixture(enabled: true)
        fixture.authenticator.result = .unavailable

        await fixture.model.unlock()

        #expect(!fixture.model.isLocked)
        #expect(!fixture.model.isEnabled)
        #expect(!fixture.store.isEnabled)
        #expect(fixture.model.notice == .turnedOffNoPasscode)
    }

    @Test func losingThePasscodeWhileAwayUnlocksOnReturn() async {
        let fixture = Fixture(enabled: true)
        fixture.authenticator.result = .success
        await fixture.model.unlock()
        fixture.authenticator.canAuthenticate = false

        fixture.leaveAndReturn(afterSeconds: 3_600)

        #expect(!fixture.model.isLocked)
        #expect(!fixture.model.isEnabled)
        #expect(fixture.model.notice == .turnedOffNoPasscode)
    }

    @Test func turningTheLockOnNeedsASuccessfulAuthentication() async {
        let fixture = Fixture(enabled: false)
        fixture.authenticator.result = .cancelled
        #expect(await fixture.model.setEnabled(true) == false)
        #expect(!fixture.model.isEnabled)
        #expect(!fixture.store.isEnabled)

        fixture.authenticator.result = .success
        #expect(await fixture.model.setEnabled(true))
        #expect(fixture.model.isEnabled)
        #expect(fixture.store.isEnabled)
        #expect(!fixture.model.isLocked)
    }

    @Test func theLockCannotBeTurnedOnWithoutAPasscode() async {
        let fixture = Fixture(enabled: false)
        fixture.authenticator.canAuthenticate = false
        fixture.authenticator.result = .success

        #expect(await fixture.model.setEnabled(true) == false)
        #expect(!fixture.model.isEnabled)
    }

    @Test func turningTheLockOffNeedsASuccessfulAuthentication() async {
        let fixture = Fixture(enabled: true)
        fixture.authenticator.result = .success
        await fixture.model.unlock()

        fixture.authenticator.result = .failed
        #expect(await fixture.model.setEnabled(false) == false)
        #expect(fixture.model.isEnabled)

        fixture.authenticator.result = .success
        #expect(await fixture.model.setEnabled(false))
        #expect(!fixture.store.isEnabled)
    }

    @Test func signingOutClearsTheLock() {
        let fixture = Fixture(enabled: true, timeout: .afterFifteenMinutes)

        fixture.model.reset()

        #expect(!fixture.model.isEnabled)
        #expect(!fixture.model.isLocked)
        #expect(!fixture.store.isEnabled)
        #expect(fixture.store.timeout == .default)
    }

    @Test func coverFollowsLockAndShield() async {
        let fixture = Fixture(enabled: true)
        var covers: [Bool] = []
        fixture.model.onCoverChange = { covers.append($0) }
        fixture.authenticator.result = .success

        await fixture.model.unlock()
        fixture.model.sceneWillResignActive()
        fixture.model.sceneDidBecomeActive()

        #expect(covers == [false, true, false])
    }

    @Test func graceDependsOnlyOnTimeAwayAndTheChosenSetting() {
        #expect(AppLockPolicy.locksAfterBackground(timeout: .immediately, elapsed: .zero))
        #expect(!AppLockPolicy.locksAfterBackground(timeout: .afterOneMinute, elapsed: .seconds(59)))
        #expect(AppLockPolicy.locksAfterBackground(timeout: .afterOneMinute, elapsed: .seconds(60)))
        #expect(!AppLockPolicy.locksAfterBackground(timeout: .afterFifteenMinutes, elapsed: .seconds(14 * 60)))
        #expect(AppLockPolicy.locksAfterBackground(timeout: .afterFifteenMinutes, elapsed: .seconds(15 * 60)))
    }
}
