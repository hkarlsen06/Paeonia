import CoreLocation

nonisolated enum PartnerCompassDirection {
    /// Initial great-circle bearing, clockwise from geographic north.
    static func bearing(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> Double? {
        guard CLLocationCoordinate2DIsValid(origin), CLLocationCoordinate2DIsValid(target) else { return nil }
        let latitude = origin.latitude * .pi / 180
        let targetLatitude = target.latitude * .pi / 180
        let longitudeDelta = (target.longitude - origin.longitude) * .pi / 180
        let east = sin(longitudeDelta) * cos(targetLatitude)
        let north = cos(latitude) * sin(targetLatitude) - sin(latitude) * cos(targetLatitude) * cos(longitudeDelta)
        // Coincident and antipodal points have no unique direction.
        guard hypot(east, north) > 1e-12 else { return nil }
        return atan2(east, north) * 180 / .pi
    }

    /// Keep successive turns within half a circle, including when crossing north.
    static func rotation(angle: Double, previous: Double?) -> Double {
        guard let previous else { return angle }
        let delta = (angle - previous).remainder(dividingBy: 360)
        return previous + delta
    }
}
