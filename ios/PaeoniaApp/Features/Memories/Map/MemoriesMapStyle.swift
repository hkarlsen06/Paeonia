import MapKit
import SwiftUI

/// The memories map looks like the couple map on Home: dark, muted, flat, with points
/// of interest hidden, so the photo pins carry the color (see `CoupleMapSnapshot+Rendering`).
enum MemoriesMapStyle {
    static let swiftUI: MapStyle = .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)

    static func configuration() -> MKStandardMapConfiguration {
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        return configuration
    }
}

enum MemoriesMapRegion {
    /// The country in the phone's region setting, so a map with nothing on it yet opens
    /// somewhere familiar. Uses no location permission. Nil when the lookup fails.
    static func home() async -> MKCoordinateRegion? {
        guard let code = Locale.current.region?.identifier,
              let country = Locale(identifier: "en").localizedString(forRegionCode: code)
        else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = country
        request.resultTypes = .address
        return try? await MKLocalSearch(request: request).start().boundingRegion
    }
}
