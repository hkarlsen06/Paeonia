import CoreLocation
import Foundation
import MapKit

/// Where the check map opens for a photo with no location of its own.
nonisolated struct GuessMySpotArea: Equatable, Sendable {
    let center: GuessMySpotCoordinate
    /// How much the map shows across.
    let meters: Double
}

nonisolated protocol GuessMySpotHomeAreaProviding: Sendable {
    /// This person's own area, or nil to open on the whole world.
    func homeArea(ownerUserID: UUID, coupleID: UUID?) async -> GuessMySpotArea?
}

/// The position this person last shared on the Home map, about a city across, or
/// else the country their phone is set to. It never asks for location access: a
/// person who doesn't share their location gets their country.
nonisolated struct LiveGuessMySpotHomeArea: GuessMySpotHomeAreaProviding {
    static let ownAreaMeters = 40_000.0
    static let countryMeters = 1_500_000.0

    func homeArea(ownerUserID: UUID, coupleID: UUID?) async -> GuessMySpotArea? {
        if let coupleID, let store = PaeoniaLocalStore.shared,
           let own = try? await SwiftDataOwnLocationSnapshotRepository(container: store.container)
               .load(ownerUserID: ownerUserID, coupleID: coupleID) {
            let center = GuessMySpotCoordinate(latitude: own.location.latitude, longitude: own.location.longitude)
            return GuessMySpotArea(center: center, meters: Self.ownAreaMeters)
        }
        return await countryArea()
    }

    /// The middle of the phone's country, looked up by name.
    private func countryArea() async -> GuessMySpotArea? {
        guard let code = Locale.current.region?.identifier,
              let name = Locale(identifier: "en_US").localizedString(forRegionCode: code),
              let request = MKGeocodingRequest(addressString: name),
              let item = try? await request.mapItems.first
        else { return nil }
        let coordinate = item.location.coordinate
        return GuessMySpotArea(center: GuessMySpotCoordinate(coordinate), meters: Self.countryMeters)
    }
}

/// For tests and the developer scenarios.
nonisolated struct FixedGuessMySpotHomeArea: GuessMySpotHomeAreaProviding {
    var area: GuessMySpotArea?

    // swiftlint:disable:next async_without_await
    func homeArea(ownerUserID _: UUID, coupleID _: UUID?) async -> GuessMySpotArea? {
        area
    }
}
