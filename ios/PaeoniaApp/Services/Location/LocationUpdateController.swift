import CoreLocation
import Foundation
import Observation
import UIKit

/// Which location feeds should run right now. Kept pure so the rules are testable.
nonisolated struct LocationUpdatePlan: Equatable, Sendable {
    /// A live feed while the app is on screen.
    let watchesWhileOpen: Bool
    /// iOS's significant-change service, which wakes Paeonia after the phone
    /// moves a good distance (roughly 500 m or more), even when it is closed.
    let watchesWhileClosed: Bool

    static func resolve(
        isAppActive: Bool,
        sharingEnabled: Bool?,
        hasIdentity: Bool,
        authorization: CLAuthorizationStatus,
        prefersUpdatesWhileClosed: Bool
    ) -> Self {
        let isAuthorized = authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        return Self(
            watchesWhileOpen: isAppActive && sharingEnabled == true && hasIdentity && isAuthorized,
            // `nil` sharing means the app has not loaded the choice yet, as on a
            // launch in the background. The uploader checks it before sending.
            watchesWhileClosed: prefersUpdatesWhileClosed
                && sharingEnabled != false
                && hasIdentity
                && authorization == .authorizedAlways
        )
    }
}

/// Owns the location feeds that run without a tap. While the app is open, a
/// live feed reports moves of 250 m or more and hands them to the location view
/// model, which sends them through the outbox. When the person turns on updates
/// while closed and allows Always, iOS wakes the app after bigger moves and
/// `BackgroundLocationUploader` sends the position directly.
///
/// No `location` background mode is used. The significant-change service does
/// not need one, and it is far lighter on battery than continuous updates.
@MainActor
@Observable
final class LocationUpdateController: NSObject {
    static let shared = LocationUpdateController()

    private enum Key {
        static let prefersUpdatesWhileClosed = "paeonia.location.updatesWhileClosed"
        static let userID = "paeonia.location.updatesWhileClosed.userID"
        static let coupleID = "paeonia.location.updatesWhileClosed.coupleID"
        /// The Clerk account that made the choice. A send needs the same account
        /// signed in, so an expired session followed by a different sign-in never
        /// sends under the wrong person.
        static let accountID = "paeonia.location.updatesWhileClosed.accountID"
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var uploader: BackgroundLocationUploader?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    /// Set by the root view. Positions found while the app is open go here.
    @ObservationIgnored var onLocationWhileOpen: ((LocationPoint) async -> Void)?

    private(set) var authorization: CLAuthorizationStatus
    /// The person's choice on this phone. It only takes effect with Always access.
    private(set) var prefersUpdatesWhileClosed: Bool

    @ObservationIgnored private var sharingEnabled: Bool?
    @ObservationIgnored private var isAppActive = false
    @ObservationIgnored private var appliedPlan: LocationUpdatePlan?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorization = manager.authorizationStatus
        prefersUpdatesWhileClosed = defaults.bool(forKey: Key.prefersUpdatesWhileClosed)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = RoutineLocationThrottle.minimumDistanceMeters
    }

    /// Whether updates while closed are actually running: chosen and allowed.
    var updatesWhileClosedActive: Bool {
        prefersUpdatesWhileClosed && authorization == .authorizedAlways
    }

    /// Call at every app launch, including launches in the background. iOS
    /// relaunches a closed app for a significant move and delivers the position
    /// to the location manager that is set up here.
    func resumeAfterLaunch() {
        apply()
    }

    /// Called by the root view when the signed-in couple, the sharing choice,
    /// or the app's foreground state changes. `sharingEnabled` is `nil` until
    /// the choice has loaded.
    func update(identity: LocationIdentity, sharingEnabled: Bool?, isAppActive: Bool) {
        self.isAppActive = isAppActive
        self.sharingEnabled = sharingEnabled
        if let userID = identity.currentUserID, let coupleID = identity.coupleID {
            let stored = storedIdentity
            let accountID = PaeoniaClerk.currentAccountID()
            let storedAccountID = defaults.string(forKey: Key.accountID)
            if stored != nil, stored?.userID != userID || stored?.coupleID != coupleID {
                // Another account or relationship never inherits this choice.
                setPrefersUpdatesWhileClosed(false)
            } else if let accountID, let storedAccountID, accountID != storedAccountID {
                setPrefersUpdatesWhileClosed(false)
            }
            defaults.set(userID.uuidString, forKey: Key.userID)
            defaults.set(coupleID.uuidString, forKey: Key.coupleID)
            if let accountID {
                defaults.set(accountID, forKey: Key.accountID)
            }
        }
        if sharingEnabled == false {
            // Turning sharing off also ends updates while closed. Turning it
            // back on later does not quietly restart them.
            setPrefersUpdatesWhileClosed(false)
        }
        apply()
    }

    /// The switch in Location settings. Turning it on asks iOS for Always
    /// access if Paeonia only has While Using. iOS shows that question once;
    /// after that the settings screen points to the Settings app.
    func setUpdatesWhileClosed(_ enabled: Bool) {
        setPrefersUpdatesWhileClosed(enabled)
        if enabled, authorization == .authorizedWhenInUse || authorization == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
        apply()
    }

    /// Stops updates while closed and forgets the choice. Used when local
    /// private data is cleared: signing out, account deletion, or the
    /// relationship ending.
    func resetUpdatesWhileClosed() {
        setPrefersUpdatesWhileClosed(false)
        defaults.removeObject(forKey: Key.userID)
        defaults.removeObject(forKey: Key.coupleID)
        defaults.removeObject(forKey: Key.accountID)
        apply()
    }

    private var storedIdentity: (userID: UUID, coupleID: UUID)? {
        guard let userID = defaults.string(forKey: Key.userID).flatMap(UUID.init(uuidString:)),
              let coupleID = defaults.string(forKey: Key.coupleID).flatMap(UUID.init(uuidString:))
        else {
            return nil
        }
        return (userID, coupleID)
    }

    private func setPrefersUpdatesWhileClosed(_ enabled: Bool) {
        if !enabled {
            // An upload that has not finished must not send or save after this.
            deliveryTask?.cancel()
        }
        guard prefersUpdatesWhileClosed != enabled else { return }
        prefersUpdatesWhileClosed = enabled
        defaults.set(enabled, forKey: Key.prefersUpdatesWhileClosed)
    }

    private func apply() {
        let plan = LocationUpdatePlan.resolve(
            isAppActive: isAppActive,
            sharingEnabled: sharingEnabled,
            hasIdentity: storedIdentity != nil,
            authorization: authorization,
            prefersUpdatesWhileClosed: prefersUpdatesWhileClosed
        )
        guard plan != appliedPlan else { return }
        if plan.watchesWhileOpen != appliedPlan?.watchesWhileOpen {
            if plan.watchesWhileOpen {
                manager.startUpdatingLocation()
            } else {
                manager.stopUpdatingLocation()
            }
        }
        if plan.watchesWhileClosed != appliedPlan?.watchesWhileClosed {
            if plan.watchesWhileClosed {
                manager.startMonitoringSignificantLocationChanges()
            } else {
                manager.stopMonitoringSignificantLocationChanges()
            }
        }
        appliedPlan = plan
    }

    private func deliver(_ location: LocationPoint) async {
        if UIApplication.shared.applicationState == .active {
            await onLocationWhileOpen?(location)
            return
        }
        guard appliedPlan?.watchesWhileClosed == true else {
            return
        }

        // One delivery at a time. A newer position replaces one still running,
        // and clearing the choice cancels whichever is running, including its
        // wait for Clerk.
        deliveryTask?.cancel()
        let delivery = Task { await sendWhileClosed(location) }
        deliveryTask = delivery
        await delivery.value
        if deliveryTask == delivery {
            deliveryTask = nil
        }
    }

    private func sendWhileClosed(_ location: LocationPoint) async {
        // iOS gives a woken app only a few seconds. Ask for enough time to
        // finish one small request.
        let backgroundTask = BackgroundTaskToken(name: "Location update")
        defer { backgroundTask.end() }
        let accountID = await PaeoniaClerk.loadedAccountID()

        // Check everything again after the wait. The choice, the couple, or
        // the account may have changed meanwhile.
        guard !Task.isCancelled,
              appliedPlan?.watchesWhileClosed == true,
              let identity = storedIdentity,
              let accountID,
              accountID == defaults.string(forKey: Key.accountID),
              let uploader = makeUploader()
        else {
            return
        }

        let outcome = await uploader.upload(location, ownerUserID: identity.userID, coupleID: identity.coupleID)
        if outcome == .sharingOff {
            setPrefersUpdatesWhileClosed(false)
            apply()
        }
    }

    /// `nil` while the local store cannot open. Without it there is no way to
    /// check the sharing choice, so nothing is sent.
    private func makeUploader() -> BackgroundLocationUploader? {
        if let uploader {
            return uploader
        }
        guard let localStore = PaeoniaLocalStore.shared else {
            return nil
        }
        let made = BackgroundLocationUploader(
            gateway: (try? PaeoniaConvexClientProvider.shared.client()).map { LiveLocationGateway(client: $0) },
            visibilityStore: SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container),
            ownLocationStore: SwiftDataOwnLocationSnapshotRepository(container: localStore.container)
        )
        uploader = made
        return made
    }
}

extension LocationUpdateController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            apply()
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let point = LocationPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            capturedAt: location.timestamp,
            updatedAt: nil
        )
        Task { @MainActor in
            await deliver(point)
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: any Error) {
        // A missed position is fine. The feeds keep running and report the next move.
    }
}

/// Extra background time for one short piece of work, ended exactly once
/// either when the work finishes or when iOS says time is up.
@MainActor
private final class BackgroundTaskToken {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
