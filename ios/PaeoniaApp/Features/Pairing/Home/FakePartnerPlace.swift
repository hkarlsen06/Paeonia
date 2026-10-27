import CoreLocation

/// PROTOTYPE. Moves the partner's pin, to see how the map looks when the couple is apart.
enum FakePartnerPlace: String, CaseIterable {
    case real, nearby, acrossTown, drammen, bergen, trondheim, tromso, copenhagen, newYork, sydney

    var label: String {
        switch self {
        case .real: "Real location"
        case .nearby: "Across town (1.5 km)"
        case .acrossTown: "Across town (3 km)"
        case .drammen: "Drammen (40 km)"
        case .bergen: "Bergen"
        case .trondheim: "Trondheim"
        case .tromso: "Tromsø"
        case .copenhagen: "Copenhagen"
        case .newYork: "New York"
        case .sydney: "Sydney"
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .real: nil
        case .nearby: CLLocationCoordinate2D(latitude: 59.9270, longitude: 10.7600)
        case .acrossTown: CLLocationCoordinate2D(latitude: 59.9380, longitude: 10.7800)
        case .drammen: CLLocationCoordinate2D(latitude: 59.7439, longitude: 10.2045)
        case .bergen: CLLocationCoordinate2D(latitude: 60.3913, longitude: 5.3221)
        case .trondheim: CLLocationCoordinate2D(latitude: 63.4305, longitude: 10.3951)
        case .tromso: CLLocationCoordinate2D(latitude: 69.6492, longitude: 18.9553)
        case .copenhagen: CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683)
        case .newYork: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        case .sydney: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        }
    }
}
