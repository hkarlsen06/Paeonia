import AppIntents
import Foundation
import UIKit

/// What Siri's intents, entity queries and the Spotlight indexer need from the running app.
/// `PaeoniaApp` connects it to the root view model at launch. Until then, and in unit tests
/// and developer scenarios, nobody is signed in as far as Siri is concerned.
@MainActor
final class SiriAppContext {
    static let shared = SiriAppContext()

    private var accessSource: (@MainActor () async -> SiriAccess)?
    private var syncSource: (@MainActor () async -> Void)?

    func connect(to root: RootViewModel) {
        accessSource = { [weak root] in await root?.siriAccess() ?? .signedOut }
        syncSource = { [weak root] in await root?.syncAfterLocalChange() }
    }

    func access() async -> SiriAccess {
        await accessSource?() ?? .signedOut
    }

    /// Sends the writes an intent queued, the same way an editor does after a save.
    func syncAfterLocalChange() async {
        await syncSource?()
    }

    /// Navigates through the same path as a tapped notification.
    func open(_ deepLink: PaeoniaDeepLink) {
        PaeoniaNotificationRouter.shared.route(deepLink)
    }
}

extension RootViewModel {
    /// Siri's access, from the session, owner and access snapshot saved on this phone. No
    /// network call, so Siri answers the same way offline.
    func siriAccess() async -> SiriAccess {
        let session = await authService.savedSession()
        var resolution: AccessRouteResolution?
        if let session {
            resolution = await syncedAccessResolution(
                for: session,
                hasPendingInvite: inviteStore.loadInvite(for: session.id) != nil
            )
        }
        return SiriAccess.decide(
            session: session,
            deviceOwnerUserID: deviceOwnerStore.ownerUserID,
            resolution: resolution
        )
    }
}

/// A plain sentence Siri says when an action can't finish.
nonisolated struct SiriFailure: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource

    init(_ resource: LocalizedStringResource) {
        localizedStringResource = resource
    }
}

extension AppIntent {
    /// The couple to act for, asked first by every intent that reads or changes their
    /// content. Without access the intent does nothing: it moves to the app, which opens where
    /// Root routes (sign-in, pairing or the paywall). With App Lock on, it moves to the app and
    /// waits until the person unlocks it, so App Lock gates Siri the way it gates a tap.
    func coupleToActFor() async throws -> SiriCouple {
        let access = await SiriAppContext.shared.access()
        guard let couple = access.couple else {
            throw needsToContinueInForegroundError(access.refusal.map { IntentDialog($0) })
        }
        try await waitForAppLock()
        return couple
    }

    /// For open and search intents, which bring the app to the front anyway. Nil means the
    /// intent should not navigate, so the app opens where Root routes. App Lock covers
    /// whatever the intent opens until the person unlocks.
    func coupleToOpenFor() async -> SiriCouple? {
        await SiriAppContext.shared.access().couple
    }

    private func waitForAppLock() async throws {
        let lock = AppLockModel.shared
        guard lock.isEnabled else { return }
        let activations = lock.activationCount
        let wasActive = UIApplication.shared.applicationState == .active
        if !wasActive {
            try await continueInForeground(IntentDialog(.siriAppLockContinue), alwaysConfirm: false)
        }
        // Two minutes to unlock. The lock decides on activation whether the time away locked it.
        for _ in 0..<600 {
            if wasActive || lock.activationCount > activations, !lock.isLocked {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw SiriFailure(.siriAppLockStillLocked)
    }
}
