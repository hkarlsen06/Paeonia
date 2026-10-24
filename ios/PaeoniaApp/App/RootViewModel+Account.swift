import AuthenticationServices
import Foundation
#if DEBUG
import OSLog
#endif

/// Account lifecycle: sign-in, profile setup, profile edits, sign-out, and
/// account deletion. Each runs as one guarded action so a second tap cannot
/// start an overlapping one.
extension RootViewModel {
    func signInWithApple(using appleSignInProvider: any AppleSignInProviding) async {
        await performSignIn(with: .apple) {
            let credential = try await appleSignInProvider.signIn()
            return try await authService.signInWithApple(credential)
        }
    }

    func signInWithGoogle() async {
        await performSignIn(with: .google) {
            try await authService.signInWithGoogle()
        }
    }

    /// Runs one sign-in. The sign-in screen stays up with a spinner on the
    /// tapped button until the next screen is ready (see `RootRoute.resolvingAccess`).
    private func performSignIn(
        with provider: AuthProvider,
        signIn: () async throws -> AuthSession
    ) async {
        guard !isWorking else {
            return
        }

        signingInWith = provider
        defer { signingInWith = nil }
        await performAuthAction(failureNotice: .signInFailed) {
            let session = try await signIn()
            PaeoniaHaptics.signedIn()
            welcomeFlow.signedIn()
            await apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signInForDevelopment() async {
        await performAuthAction(failureNotice: .signInFailed) {
            let session = try await authService.signInForDevelopment()
            await apply(AuthRoute(session: session))
        }
    }

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async {
        await performAuthAction(failureNotice: .onboardingFailed) {
            let session = try await authService.completeOnboarding(
                displayName: displayName,
                timeZoneID: timeZoneID,
                profilePhotoData: profilePhotoData
            )
            await apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signOut() async {
        await performAuthAction(failureNotice: .signOutFailed) {
            // Send what still can go while requests carry the account's token.
            // The purge below removes whatever is left, as the log-out alert says.
            await syncService.flushPendingWrites(timeout: .seconds(4))
            try await authService.signOut()
            await endSession(purgingLocalData: true)
        }
    }

    /// The sign-in ended while the app ran: it expired, or was ended on another
    /// device. Writes would now fail, so the person goes back to sign-in with a
    /// banner. Data saved on this phone stays, including writes waiting to be
    /// sent, so signing in again picks up where they left off. If someone else
    /// signs in instead, `apply` clears it first.
    func authSessionEnded() async {
        guard !isWorking, currentSession != nil else {
            return
        }

        // Set before `endSession`, which switches to sign-in before its first
        // await, so the banner and the sign-in screen appear together.
        notice = .sessionEnded
        await endSession(purgingLocalData: false)
    }

    /// Deletes the account after the user confirmed it. Accounts with Apple linked
    /// sign in to Apple once more so the server can revoke Sign in with Apple. Cancelling
    /// that Apple sheet keeps the account; if Apple fails for another reason,
    /// deletion continues and the user gets the manual Apple step afterwards.
    func deleteAccount(reauthenticatingWith appleSignInProvider: any AppleSignInProviding) async {
        guard !isWorking else {
            return
        }

        // Block a second delete while the Apple sheet is up.
        isWorking = true
        var hasApple = currentSession?.provider == .apple
        if !hasApple, let appleIsLinked {
            hasApple = await appleIsLinked()
        }

        var authorizationCode: String?
        if hasApple {
            do {
                authorizationCode = try await appleSignInProvider.signIn().authorizationCode
            } catch where Self.isUserCancelledAuthError(error) {
                isWorking = false
                return
            } catch {
                authorizationCode = nil
            }
        }
        isWorking = false

        await deleteAccount(appleAuthorizationCode: authorizationCode)
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async {
        guard !isWorking else {
            return
        }

        let previousRoute = route
        isWorking = true
        notice = nil
        requiresManualAppleRevocation = false
        invalidateAccessResolution()
        leaveRelationshipSurfaces()
        route = .deletingAccount(previousRoute.session)
        // Right away, because RootView sees the new route only after this
        // request has gone out.
        PaeoniaAnalytics.stopSharingAndDeleteQueued()

        do {
            let outcome = try await authService.requestAccountDeletion(
                appleAuthorizationCode: appleAuthorizationCode
            )
            requiresManualAppleRevocation = outcome == .manualAppleRevocationRequired
            // The account is gone, so the next person starts at welcome.
            welcomeFlow.accountDeleted()
            await endSession(purgingLocalData: true)
        } catch {
            route = previousRoute
            notice = .deleteAccountFailed
        }

        isWorking = false
    }

    /// Shared tail of sign-out, account deletion, and a session that ended on
    /// its own. The route changes first so the welcome screen shows while sync
    /// shuts down. `purgingLocalData` removes everything this person had on the
    /// phone; without it their data and queued writes stay for their return.
    func endSession(purgingLocalData: Bool) async {
        sessionEpoch &+= 1
        // Usage statistics and crash reports queued for this account must not
        // go out under whoever uses the phone next.
        PaeoniaAnalytics.stopSharingAndDeleteQueued()
        stopObservingAccessChanges()
        invalidateAccessResolution()
        leaveRelationshipSurfaces()
        welcomeFlow.sessionEnded()
        route = .signedOut
        await liveSync?.stop()
        if purgingLocalData {
            await syncService.resetForUserChange()
            deviceOwnerStore.ownerUserID = nil
        } else {
            await syncService.stop()
        }
        systemSideEffects.resetPushRegistrationState()
        hasStartedSync = false
        configuredSyncSession = nil
    }

    /// Before a session is used, clears what another account left on this
    /// phone (its widget drawing, partner photo, caches, and rows), exactly as
    /// signing out would have. The same person signing back in keeps it all.
    func clearDataFromAnotherAccount(before session: AuthSession) async {
        defer { deviceOwnerStore.ownerUserID = session.id }
        guard let previousOwner = deviceOwnerStore.ownerUserID,
              !AuthUserIdentity.matches(previousOwner, session.id),
              let previousOwnerUserID = UUID(uuidString: previousOwner)
        else {
            return
        }

        sessionEpoch &+= 1
        // The previous owner's usage statistics and crash reports must not go
        // out once PostHog starts for this account.
        PaeoniaAnalytics.stopSharingAndDeleteQueued()
        await liveSync?.stop()
        // The purge runs for the sync service's configured user, so point it at
        // the previous owner first. Nothing starts syncing for them.
        await syncService.configure(
            session: SyncSession(userID: previousOwnerUserID, activeCoupleID: nil, relationshipCoupleID: nil)
        )
        await syncService.resetForUserChange()
        systemSideEffects.resetPushRegistrationState()
        hasStartedSync = false
        configuredSyncSession = nil
    }

    func dismissManualAppleRevocation() {
        requiresManualAppleRevocation = false
    }

    /// Saves the paired user's canonical profile. It reports success as soon as
    /// the profile itself is saved; sending other local changes and checking
    /// access again run afterwards without holding up the editor. It does not
    /// wait for, or refuse because of, other account work that is running.
    func updateCurrentProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async -> Bool {
        guard !isSavingProfile, state == .paired, route.isAccessSettled else {
            return false
        }

        isSavingProfile = true
        defer { isSavingProfile = false }

        let session: AuthSession
        do {
            session = try await authService.updateProfile(
                displayName: displayName,
                profilePhotoUpdate: profilePhotoUpdate
            )
        } catch {
            logAuthError(error, notice: nil)
            return false
        }

        // The save suspended. A live access change may have moved the route on,
        // and the user may have signed out. Only refresh the session on whatever
        // route is current now; never restore the old one.
        guard let currentSession, AuthUserIdentity.matches(currentSession.id, session.id) else {
            return true
        }

        route = route.replacingSession(session)
        let epoch = sessionEpoch
        Task { [weak self] in
            guard let self else { return }
            await self.startSyncIfNeeded()
            _ = await self.syncService.runOnce(reason: .localChange)
            // Never resolve access for a session that ended in the meantime.
            guard epoch == self.sessionEpoch else { return }
            await self.resolveAccessRoute(for: session)
        }
        return true
    }

    private func performAuthAction(
        failureNotice: RootNotice,
        action: () async throws -> Void
    ) async {
        guard !isWorking else {
            return
        }

        isWorking = true
        notice = nil

        do {
            try await action()
        } catch where Self.isUserCancelledAuthError(error) {
            logAuthError(error, notice: nil)
        } catch {
            logAuthError(error, notice: failureNotice)
            notice = failureNotice
        }

        isWorking = false
    }

    private static func isUserCancelledAuthError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Apple's sheet and the Google web sheet (Clerk) report a dismissal differently.
        return (nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue)
            || (nsError.domain == ASWebAuthenticationSessionError.errorDomain
                && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue)
    }

    func logAuthError(_ error: Error, notice: RootNotice?) {
        #if DEBUG
        let noticeDescription = notice.map { String(describing: $0) } ?? "none"
        let errorDescription = String(describing: error)
        logger.error(
            """
            Auth action failed; notice=\(noticeDescription, privacy: .public); \
            error=\(errorDescription, privacy: .public)
            """
        )
        #endif
    }
}
