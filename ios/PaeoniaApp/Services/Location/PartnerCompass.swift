import CoreLocation
import Observation

/// Foreground readings for the Home arrow. These positions never enter the sharing outbox.
@MainActor
@Observable
final class PartnerCompass: NSObject {
    private(set) var heading: Double?
    private(set) var coordinate: CLLocationCoordinate2D?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private weak var referenceBody: (any CLBodyIdentifiable)?
    @ObservationIgnored private var isRequested = false
    @ObservationIgnored private var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 10
        manager.headingFilter = 1
    }

    /// Reuse the map's existing native view to align north with the top of the interface.
    func setReferenceBody(_ body: any CLBodyIdentifiable) {
        referenceBody = body
        if isRunning { manager.headingBody = body }
    }

    func start() {
        isRequested = true
        guard !isRunning, CLLocationManager.headingAvailable(),
              manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        else { return }
        isRunning = true
        manager.headingBody = referenceBody
        // True north needs location updates as well as compass readings.
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        isRequested = false
        isRunning = false
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
        manager.headingBody = nil
        heading = nil
        coordinate = nil
    }
}

extension PartnerCompass: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor in
            guard isRequested else { return }
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                start()
            } else {
                stop()
            }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            guard isRunning else { return }
            heading = value.isFinite && value >= 0 && accuracy >= 0 && accuracy <= 30 ? value : nil
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        let value = location.coordinate
        Task { @MainActor in
            guard isRunning else { return }
            coordinate = value
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: any Error) {
        Task { @MainActor in
            guard isRunning else { return }
            heading = nil
            coordinate = nil
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_: CLLocationManager) -> Bool { false }
}
