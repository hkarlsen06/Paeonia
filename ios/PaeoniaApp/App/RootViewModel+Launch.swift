import Foundation

/// The launch path: the session restore that starts before the scene exists,
/// and the route it produces. The saved Home preview that covers the wait is in
/// `RootViewModel+AccessResolution.swift`.
extension RootViewModel {
    /// Starts the session restore, which is the one server call a signed-in
    /// launch needs, before the scene and `RootView` exist. `start` then awaits
    /// it. Also reads the state saved on this phone, so Home can open the moment
    /// `start` runs. Call once, as early as the app can.
    func beginLaunch() {
        guard launchRestore == nil else {
            return
        }

        launchRestore = startRestore()
        savedLaunchState = Task { await loadSavedLaunchState() }
    }

    private func startRestore() -> Task<Result<RestoredSession?, any Error>, Never> {
        let authService = authService
        return Task {
            do {
                return .success(try await authService.restoreSession())
            } catch {
                return .failure(error)
            }
        }
    }

    /// Restores the session at launch, or when no session is on screen.
    func refreshAuthRoute() async {
        let restore = launchRestore ?? startRestore()
        launchRestore = nil
        do {
            let restored = try await restore.value.get()
            await apply(AuthRoute(session: restored?.session), launchAccess: restored?.access)
        } catch {
            // A saved preview of Home counts as no session here. The restore
            // that should have confirmed it failed, so it must not stay up.
            guard currentSession == nil || route.isResolvingAccess else {
                // Never sign someone out because a check failed. The live
                // session watch notices a session that really ended.
                logAuthError(error, notice: nil)
                return
            }
            stopObservingAccessChanges()
            invalidateAccessResolution()
            leaveRelationshipSurfaces()
            route = .signedOut
            notice = .sessionLoadFailed
        }
    }
}
