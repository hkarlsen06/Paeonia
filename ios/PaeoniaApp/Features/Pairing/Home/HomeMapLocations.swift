import CoreLocation

/// The coordinates shared by the map camera and its avatars. Small GPS changes keep
/// the displayed place until that person moves 250 m from it.
nonisolated struct HomeMapLocations {
    let current: CLLocationCoordinate2D
    let partner: CLLocationCoordinate2D

    func retainingNearbyLocations(from latest: Self) -> Self {
        Self(current: retained(current, latest.current), partner: retained(partner, latest.partner))
    }

    private func retained(
        _ displayed: CLLocationCoordinate2D,
        _ latest: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let distance = CLLocation(latitude: displayed.latitude, longitude: displayed.longitude)
            .distance(from: CLLocation(latitude: latest.latitude, longitude: latest.longitude))
        return distance < RoutineLocationThrottle.minimumDistanceMeters ? displayed : latest
    }
}
