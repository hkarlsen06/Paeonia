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
    /// What the app tells Core Location it needs. Since iOS 18, Always access
    /// only works while the app holds a `CLServiceSession` for it.
    let sessionGoal: SessionGoal?

    nonisolated enum SessionGoal: Equatable, Sendable {
        case whenInUse
        case always
    }

    static func resolve(
        isAppActive: Bool,
        sharingEnabled: Bool?,
        hasIdentity: Bool,
        authorization: CLAuthorizationStatus,
        prefersUpdatesWhileClosed: Bool
    ) -> Self {
        let isAuthorized = authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        // `nil` sharing means the app has not loaded the choice yet, as on a
        // launch in the background. The uploader checks it before sending.
        let wantsClosedUpdates = prefersUpdatesWhileClosed && sharingEnabled != false && hasIdentity
        // The Always goal does not wait for the Always grant, so the session can
        // also bring up iOS's question about it.
        let sessionGoal: SessionGoal? = if wantsClosedUpdates {
            .always
        } else if isAppActive, sharingEnabled == true, hasIdentity {
            .whenInUse
        } else {
            nil
        }
        return Self(
            watchesWhileOpen: isAppActive && sharingEnabled == true && hasIdentity && isAuthorized,
            watchesWhileClosed: wantsClosedUpdates && authorization == .authorizedAlways,
            sessionGoal: sessionGoal
        )
    }
}

/// Owns the location feeds that run without a tap. While the app is open, a
/// live feed reports moves of 250 m or more and hands them to the location view
/// model, which sends them through the outbox. When the person turns on updates
/// while closed and allows Always, iOS wakes the app after bigger moves and
/// `BackgroundLocationUploader` sends the position directly.
///
/// A `CLServiceSession` backs each feed. iOS 18 and later only honor Always
/// access while the app holds one, and a session must be taken again at every
/// launch, including a relaunch in the background, because Core Location waits
/// only a few seconds for it. `resumeAfterLaunch` does that through `apply`.
/// The app does not set `NSLocationRequireExplicitServiceSession`, so iOS also
/// keeps its own implicit when-in-use session for the open-app feed.
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
        /// Set after a new sign-in or relationship, until the choice the server
        /// kept arrives or the person sets the switch.
        static let needsServerChoice = "paeonia.location.updatesWhileClosed.needsServerChoice"
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var uploader: BackgroundLocationUploader?
    @ObservationIgnored private let deviceStateReporter = LocationDeviceStateReporter()
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    /// Set by the root view. Positions found while the app is open go here.
    @ObservationIgnored var onLocationWhileOpen: ((LocationPoint) async -> Void)?

    private(set) var authorization: CLAuthorizationStatus
    /// The person's choice on this phone. It only takes effect with Always access.
    private(set) var prefersUpdatesWhileClosed: Bool

    @ObservationIgnored private var sharingEnabled: Bool?
    @ObservationIgnored private var isAppActive = false
    @ObservationIgnored private var appliedPlan: LocationUpdatePlan?
    @ObservationIgnored private var serviceSession: CLServiceSession?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorization = manager.authorizationStatus
        prefersUpdatesWhileClosed = defaults.bool(forKey: Key.prefersUpdatesWhileClosed)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = RoutineLocationThrottle.minimumDistanceMeters
        // People share while walking, driving and riding transit, so no single
        // activity type fits better than the default.
        manager.activityType = .other
        deviceStateReporter.currentState = { [unowned self] in currentDeviceState }
        deviceStateReporter.handleAnswer = { [unowned self] state, kept in
            takeServerAnswer(to: state, kept: kept)
        }
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
            let changedIdentity = stored.map { $0.userID != userID || $0.coupleID != coupleID } ?? false
            let changedAccount = accountID != nil && storedAccountID != nil && accountID != storedAccountID
            if changedIdentity || changedAccount {
                // Another account or relationship never inherits this choice.
                setPrefersUpdatesWhileClosed(false)
            }
            if stored == nil || changedIdentity || changedAccount {
                // A new sign-in takes the choice the server kept for this
                // account and relationship. See `currentDeviceState`.
                defaults.set(true, forKey: Key.needsServerChoice)
            }
            defaults.set(userID.uuidString, forKey: Key.userID)
            defaults.set(coupleID.uuidString, forKey: Key.coupleID)
            if let accountID {
                defaults.set(accountID, forKey: Key.accountID)
            }
        }
        if sharingEnabled == false {
            // Turning sharing off also ends updates while closed. Turning it
            // back on later does not quietly restart them. The server clears
            // its copy of the choice at the same time.
            setPrefersUpdatesWhileClosed(false)
            defaults.set(false, forKey: Key.needsServerChoice)
        }
        apply()
        deviceStateReporter.report()
    }

    /// The switch in Location settings. Turning it on asks iOS for Always
    /// access if Paeonia only has While Using. iOS shows that question once;
    /// after that the settings screen points to the Settings app.
    func setUpdatesWhileClosed(_ enabled: Bool) {
        setPrefersUpdatesWhileClosed(enabled)
        defaults.set(false, forKey: Key.needsServerChoice)
        if enabled, authorization == .authorizedWhenInUse || authorization == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
        apply()
        deviceStateReporter.report()
    }

    /// Called right after someone turns sharing on from the map card or the
    /// primer. While Paeonia has While Using access, iOS asks straight away
    /// whether to change it to Always, so the person decides on the spot.
    func offerUpdatesWhileClosed() {
        guard manager.authorizationStatus == .authorizedWhenInUse else { return }
        setUpdatesWhileClosed(true)
    }

    /// Stops updates while closed and forgets the choice. Used when local
    /// private data is cleared: signing out, account deletion, or the
    /// relationship ending.
    func resetUpdatesWhileClosed() {
        setPrefersUpdatesWhileClosed(false)
        defaults.removeObject(forKey: Key.userID)
        defaults.removeObject(forKey: Key.coupleID)
        defaults.removeObject(forKey: Key.accountID)
        defaults.removeObject(forKey: Key.needsServerChoice)
        deviceStateReporter.forget()
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
        if plan.sessionGoal != appliedPlan?.sessionGoal {
            applySessionGoal(plan.sessionGoal)
        }
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

    /// Takes the new session before letting go of the old one, so authorization
    /// never lapses while the goal changes.
    private func applySessionGoal(_ goal: LocationUpdatePlan.SessionGoal?) {
        let previous = serviceSession
        serviceSession = switch goal {
        case .whenInUse: CLServiceSession(authorization: .whenInUse)
        case .always: CLServiceSession(authorization: .always)
        case nil: nil
        }
        previous?.invalidate()
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
            defaults.set(false, forKey: Key.needsServerChoice)
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
            visibilityStore: SwiftDataLocationVisibilityRepository(container: localStore.container),
            ownLocationStore: SwiftDataOwnLocationSnapshotRepository(container: localStore.container)
        )
        uploader = made
        return made
    }
}

extension LocationUpdateController {
    /// Tells the server this phone's choice and iOS access while the app is
    /// open: once per launch and after either changes. After a new sign-in it
    /// sends no choice, and takes the one the server kept. If iOS has never
    /// asked about Always on this phone, it asks then, as it does after the
    /// switch is turned on. Otherwise Location settings says how to allow it.
    private var currentDeviceState: LocationDeviceState? {
        guard isAppActive,
              let identity = storedIdentity,
              let permission = LocationPermission(authorization)
        else {
            return nil
        }
        return LocationDeviceState(
            userID: identity.userID,
            coupleID: identity.coupleID,
            updatesWhileClosed: defaults.bool(forKey: Key.needsServerChoice) ? nil : prefersUpdatesWhileClosed,
            permission: permission
        )
    }

    /// Returns the state the server now holds, or `nil` to report again.
    private func takeServerAnswer(to state: LocationDeviceState, kept: Bool) -> LocationDeviceState? {
        guard let identity = storedIdentity,
              identity.userID == state.userID,
              identity.coupleID == state.coupleID
        else {
            return nil
        }
        guard state.updatesWhileClosed == nil else {
            // The server turns the choice off while it does not know sharing
            // is on yet. Report again at the next change, once it does.
            return kept == state.updatesWhileClosed ? state : nil
        }
        // A switch set while the report ran wins over the kept choice.
        guard defaults.bool(forKey: Key.needsServerChoice) else {
            return nil
        }
        defaults.set(false, forKey: Key.needsServerChoice)
        setPrefersUpdatesWhileClosed(kept)
        apply()
        return LocationDeviceState(
            userID: state.userID,
            coupleID: state.coupleID,
            updatesWhileClosed: kept,
            permission: state.permission
        )
    }
}

extension LocationUpdateController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            apply()
            deviceStateReporter.report()
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
final class BackgroundTaskToken {
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
