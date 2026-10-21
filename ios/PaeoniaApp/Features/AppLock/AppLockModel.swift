import Foundation
import Observation

/// The optional lock that asks for Face ID, Touch ID or the phone's passcode
/// before Paeonia shows anything. It is off until the person turns it on.
///
/// The model decides when the app is locked. `AppLockCoverController` shows the
/// cover window while `isCovering` is true, and feeds it the scene events.
///
/// Two states cover the screen:
/// - Locked. Opening the app, or coming back after the chosen time away, needs
///   an unlock first.
/// - Shielded. The app is not in front (the app switcher, Control Center, the
///   Face ID prompt). The cover hides the content for the app switcher's
///   snapshot but asks for nothing, and goes away when the app is active again.
///
/// Whatever the phone can no longer do, the person is never shut out. If it has
/// lost its passcode there is nothing to unlock with, so the lock turns itself
/// off and says so.
@MainActor
@Observable
final class AppLockModel {
    static let shared = AppLockModel()

    enum Notice: Equatable {
        /// The phone lost its passcode while the lock was on.
        case turnedOffNoPasscode
    }

    private(set) var isEnabled: Bool
    private(set) var timeout: AppLockTimeout
    private(set) var isLocked: Bool
    private(set) var isShielding = false
    /// The system prompt is up, for an unlock or for turning the lock on or off.
    private(set) var isAuthenticating = false
    /// The last unlock try failed, so the lock screen says to try again.
    private(set) var lastUnlockFailed = false
    private(set) var capability: AppLockCapability
    var notice: Notice?

    var isCovering: Bool { isLocked || isShielding }

    /// Called whenever `isCovering` may have changed, in the same turn as the
    /// change, so the cover is up before the system takes the app's snapshot.
    @ObservationIgnored var onCoverChange: ((Bool) -> Void)?

    @ObservationIgnored private var store: any AppLockPersisting
    @ObservationIgnored private let authenticator: any AppLockAuthenticating
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    /// When the app went to the background. Nil while it is in front, or when
    /// it only became inactive.
    @ObservationIgnored private var backgroundedAt: ContinuousClock.Instant?
    @ObservationIgnored private var hasBecomeActive = false

    init(
        store: any AppLockPersisting = UserDefaultsAppLockStore(),
        authenticator: any AppLockAuthenticating = LocalAuthenticationAppLockAuthenticator(),
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.store = store
        self.authenticator = authenticator
        self.now = now
        isEnabled = store.isEnabled
        timeout = store.timeout
        // A cold launch always starts locked.
        isLocked = store.isEnabled
        capability = authenticator.capability()
    }

    // MARK: Scene events

    /// The app stopped being the active one. This alone never locks.
    func sceneWillResignActive() {
        guard isEnabled else { return }
        isShielding = true
        publishCover()
    }

    func sceneDidEnterBackground() {
        guard isEnabled else { return }
        if backgroundedAt == nil {
            backgroundedAt = now()
        }
        isShielding = true
        publishCover()
    }

    /// The app is in front again. Locks if it was away long enough. The unlock
    /// prompt opens by itself on launch and after a trip to the background. It
    /// does not reopen after a cancel, even though the prompt can make the app
    /// inactive and active again.
    func sceneDidBecomeActive() {
        isShielding = false
        if isEnabled {
            refreshCapability()
            if !capability.canAuthenticate {
                turnOffBecauseUnavailable()
            }
        }
        let returnedFromBackground = backgroundedAt != nil
        if isEnabled, let backgroundedAt {
            self.backgroundedAt = nil
            if !isLocked,
               AppLockPolicy.locksAfterBackground(timeout: timeout, elapsed: now() - backgroundedAt) {
                isLocked = true
                lastUnlockFailed = false
            }
        }
        let isFirstActivation = !hasBecomeActive
        hasBecomeActive = true
        publishCover()
        if isLocked, returnedFromBackground || isFirstActivation {
            Task { await unlock() }
        }
    }

    // MARK: Unlocking

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        lastUnlockFailed = false
        let result = await authenticator.authenticate(reason: String(localized: .appLockUnlockReason))
        isAuthenticating = false
        guard isLocked else { return }

        switch result {
        case .success:
            isLocked = false
            backgroundedAt = nil
        case .cancelled:
            break
        case .unavailable:
            turnOffBecauseUnavailable()
        case .failed:
            lastUnlockFailed = true
        }
        publishCover()
    }

    // MARK: Settings

    /// Turns the lock on or off after the person proves it is them. Returns
    /// whether the setting changed.
    @discardableResult
    func setEnabled(_ enable: Bool) async -> Bool {
        guard !isAuthenticating, enable != isEnabled else { return false }
        refreshCapability()
        // Nothing to unlock with, so the lock cannot be turned on.
        if enable, !capability.canAuthenticate { return false }

        isAuthenticating = true
        let reason = enable ? String(localized: .appLockTurnOnReason) : String(localized: .appLockTurnOffReason)
        let result = await authenticator.authenticate(reason: reason)
        isAuthenticating = false

        // A phone that can no longer ask must not keep the lock on.
        guard result == .success || (result == .unavailable && !enable) else { return false }
        store.isEnabled = enable
        isEnabled = enable
        isLocked = false
        isShielding = false
        backgroundedAt = nil
        publishCover()
        return true
    }

    func setTimeout(_ timeout: AppLockTimeout) {
        store.timeout = timeout
        self.timeout = timeout
    }

    func refreshCapability() {
        capability = authenticator.capability()
    }

    func dismissNotice() {
        notice = nil
    }

    /// Signing out and deleting the account clear the lock, since the next
    /// person on this phone starts fresh.
    func reset() {
        store.clear()
        isEnabled = false
        timeout = .default
        isLocked = false
        isShielding = false
        lastUnlockFailed = false
        backgroundedAt = nil
        publishCover()
    }

    // MARK: Private

    private func turnOffBecauseUnavailable() {
        store.isEnabled = false
        isEnabled = false
        isLocked = false
        isShielding = false
        backgroundedAt = nil
        notice = .turnedOffNoPasscode
        publishCover()
    }

    private func publishCover() {
        onCoverChange?(isCovering)
    }
}
