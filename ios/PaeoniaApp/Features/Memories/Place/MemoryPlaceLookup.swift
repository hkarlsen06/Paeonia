import CoreLocation
import MapKit

/// Turns MapKit results into memory places. Every call goes to Apple's map service,
/// which sees the coordinate or the search text, the same as any map search. No
/// location permission is used.
enum MemoryPlaceLookup {
    /// How far around a photo's spot to look for named places.
    static let nearbyRadius: CLLocationDistance = 250

    static func place(from item: MKMapItem) -> MemoryPlace? {
        let address = item.addressRepresentations
        let city = address?.cityName
        guard let name = item.name ?? city else { return nil }
        let coordinate = item.location.coordinate
        return MemoryPlace(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            city: city,
            countryCode: address?.region?.identifier
        )
    }

    /// The city around a coordinate, named after the city, pinned at the coordinate
    /// itself. The photo suggestion and "Choose on the map" use it.
    static func cityPlace(at coordinate: CLLocationCoordinate2D) async throws -> MemoryPlace? {
        try await reverseGeocode(coordinate)?.city
    }

    /// What the place sheet offers for a photo's spot, in this order: the city, the
    /// area or landmark the spot is in when it isn't just a street address, and at most
    /// three nearby places of the kinds couples make memories at. Each spot appears once.
    static func photoSuggestions(around coordinate: CLLocationCoordinate2D) async -> [MemoryPlace] {
        var places: [MemoryPlace] = []
        if let named = try? await reverseGeocode(coordinate) {
            places.append(named.city)
            if let area = named.area, area.name != named.city.name {
                places.append(area)
            }
        }
        let nearby = (try? await nearbyPlaces(around: coordinate, limit: 3)) ?? []
        for place in nearby where !places.contains(where: { $0.isSameSpot(as: place) || $0.name == place.name }) {
            places.append(place)
        }
        return places
    }

    /// Kinds of places a couple makes memories at, best first. Landmarks and nature
    /// come before culture, and culture before food, drink and stays, so a photo taken
    /// at a landmark suggests the landmark before the café next to it. Shops, banks,
    /// parking and the like are left out.
    static let memoryCategoryTiers: [[MKPointOfInterestCategory]] = [
        [.landmark, .nationalMonument, .castle, .fortress, .scenicView, .nationalPark, .park, .beach],
        [.museum, .aquarium, .zoo, .planetarium, .amusementPark, .fairground, .theater, .movieTheater,
         .musicVenue, .stadium, .marina, .skiing, .hiking, .picnicArea, .campground, .kayaking, .surfing,
         .swimming],
        [.restaurant, .cafe, .bakery, .brewery, .winery, .distillery, .nightlife, .hotel, .spa],
    ]

    /// Named places within `nearbyRadius` of a coordinate of the kinds in
    /// `memoryCategoryTiers`, best kind first and nearest first within a kind.
    static func nearbyPlaces(around coordinate: CLLocationCoordinate2D, limit: Int) async throws -> [MemoryPlace] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: nearbyRadius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: memoryCategoryTiers.flatMap(\.self))
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let tier = { (item: MKMapItem) in
            item.pointOfInterestCategory.flatMap { category in
                memoryCategoryTiers.firstIndex { $0.contains(category) }
            } ?? memoryCategoryTiers.count
        }
        return response.mapItems
            .sorted { lhs, rhs in
                let (lhsTier, rhsTier) = (tier(lhs), tier(rhs))
                guard lhsTier == rhsTier else { return lhsTier < rhsTier }
                return lhs.location.distance(from: origin) < rhs.location.distance(from: origin)
            }
            .compactMap(place(from:))
            .prefix(limit)
            .map(\.self)
    }

    /// The city around a coordinate, and the area or landmark name MapKit gives the spot
    /// when that name isn't a street address. Both are pinned at the coordinate.
    private static func reverseGeocode(
        _ coordinate: CLLocationCoordinate2D
    ) async throws -> (city: MemoryPlace, area: MemoryPlace?)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try await request.mapItems.first
        else { return nil }
        let address = item.addressRepresentations
        let cityName = address?.cityName
        guard let name = cityName ?? item.name else { return nil }
        let pin = { (placeName: String) in
            MemoryPlace(
                name: placeName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                city: cityName,
                countryCode: address?.region?.identifier
            )
        }
        let area = item.name.flatMap { itemName -> MemoryPlace? in
            let isStreetAddress = itemName.contains(where: \.isNumber)
                || item.address?.shortAddress?.hasPrefix(itemName) == true
            return isStreetAddress ? nil : pin(itemName)
        }
        return (pin(name), area)
    }

    /// The place a search suggestion points to.
    static func place(for completion: MKLocalSearchCompletion) async throws -> MemoryPlace? {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        return response.mapItems.first.flatMap(place(from:))
    }
}
