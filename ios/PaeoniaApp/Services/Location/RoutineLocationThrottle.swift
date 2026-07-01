import CoreLocation
import Foundation

/// Decides whether a *routine* location update (the app coming to the
/// foreground) is worth writing to the backend.
///
/// Without this, every scene activation queued an
/// `update_latest_partner_location` write — which then kicked off a full
/// local-change sync — even when the user hadn't moved. Only foreground-open
/// refreshes are throttled: a manual pull-to-refresh or a settings toggle
/// always writes, because the user explicitly asked for a fresh position.
nonisolated enum RoutineLocationThrottle {
    /// Send a routine update only once the last sent fix is at least this old…
    static let minimumInterval: TimeInterval = 5 * 60
    /// …unless the device has moved at least this far since that fix.
    static let minimumDistanceMeters: CLLocationDistance = 250

    static func shouldSend(
        lastSent: LocationPoint?,
        current: LocationPoint,
        now: Date,
        minimumInterval: TimeInterval = minimumInterval,
        minimumDistanceMeters: CLLocationDistance = minimumDistanceMeters
    ) -> Bool {
        guard let lastSent else {
            return true
        }
        if now.timeIntervalSince(lastSent.capturedAt) >= minimumInterval {
            return true
        }
        return distanceMeters(from: lastSent, to: current) >= minimumDistanceMeters
    }

    static func distanceMeters(from: LocationPoint, to: LocationPoint) -> CLLocationDistance {
        let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let end = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return end.distance(from: start)
    }
}
