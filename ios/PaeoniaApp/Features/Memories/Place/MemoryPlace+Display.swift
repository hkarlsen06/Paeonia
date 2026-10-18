import CoreLocation
import Foundation

nonisolated extension MemoryPlace {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "Bryggen, Bergen", or just "Bergen" when the place is the city itself. The
    /// memory's detail screen and the map's card show this.
    var nameAndCity: String {
        guard let city, city != name else { return name }
        return "\(name), \(city)"
    }

    /// "Bergen" for the timeline card, which has room for one short word.
    var shortName: String {
        city ?? name
    }

    /// "Bergen, Norway" under the place's name. Nil when neither is known.
    var cityAndCountry: String? {
        let country = countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
        let parts = [city == name ? nil : city, country].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Whether two places are the same spot for "Places you've used": the same name
    /// within about 100 meters.
    func isSameSpot(as other: MemoryPlace) -> Bool {
        name == other.name
            && abs(latitude - other.latitude) < 0.001
            && abs(longitude - other.longitude) < 0.001
    }
}
