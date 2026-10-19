import CoreLocation
import Foundation
import MapKit

/// What Apple's maps call a spot: the name the reveal shows, such as "Bergen, Norway",
/// and the city alone and the country code, which the memory map counts.
nonisolated struct GuessMySpotPlace: Codable, Equatable, Sendable {
    var name: String
    var city: String?
    var countryCode: String?
}

/// Names a spot.
nonisolated protocol GuessMySpotPlaceNaming: Sendable {
    /// Nil when the lookup fails or the spot has no named place, such as the open sea.
    func place(for spot: GuessMySpotCoordinate) async -> GuessMySpotPlace?
}

/// Apple's reverse geocoding. It needs a connection, and Apple limits how often
/// one app may ask, so the check screen asks only once the pin settles.
nonisolated struct LiveGuessMySpotPlaceNamer: GuessMySpotPlaceNaming {
    func place(for spot: GuessMySpotCoordinate) async -> GuessMySpotPlace? {
        let location = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first,
              let name = GuessMySpotRules.placeName(item.addressRepresentations?.cityWithContext ?? item.name)
        else { return nil }
        let code = item.addressRepresentations?.region?.identifier.uppercased()
        return GuessMySpotPlace(
            name: name,
            city: GuessMySpotRules.placeName(item.addressRepresentations?.cityName).map { String($0.prefix(80)) },
            countryCode: code.flatMap { $0.count == 2 && $0.allSatisfy { ("A"..."Z").contains($0) } ? $0 : nil }
        )
    }
}

/// For tests and the developer scenarios.
nonisolated struct FixedGuessMySpotPlaceNamer: GuessMySpotPlaceNaming {
    var place: GuessMySpotPlace?

    init(name: String? = nil, city: String? = nil, countryCode: String? = nil) {
        place = name.map { GuessMySpotPlace(name: $0, city: city, countryCode: countryCode) }
    }

    // swiftlint:disable:next async_without_await
    func place(for _: GuessMySpotCoordinate) async -> GuessMySpotPlace? {
        place
    }
}
