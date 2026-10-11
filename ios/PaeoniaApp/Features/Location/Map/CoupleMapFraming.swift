import MapKit

/// Picks the map area that shows both partners with an even margin around them.
enum CoupleMapFraming {
    /// How much larger than the pins' own span the framed area is, leaving an even
    /// margin around the avatars.
    static let paddingFactor = 1.7
    /// Smallest framed span (meters) so same-city couples still get a sensible zoom
    /// instead of diving to street level.
    static let minimumSpanMeters: CLLocationDegrees = 4_000

    /// A map rect that contains both pins, built to the card's aspect ratio so MapKit
    /// renders it as-is. (A square rect was being re-expanded by MapKit to fill the
    /// wide card, which undid the framing and made tuning feel like it did nothing.)
    /// Working in projected map points keeps the math uniform; intersecting `.world`
    /// keeps the region inside valid Mercator bounds.
    static func region(
        current: CLLocationCoordinate2D,
        partner: CLLocationCoordinate2D,
        aspectRatio: Double
    ) -> MKCoordinateRegion {
        let currentPoint = MKMapPoint(current)
        let partnerPoint = MKMapPoint(partner)

        let midLatitude = (current.latitude + partner.latitude) / 2
        let minimumHalf = minimumSpanMeters / 2 * MKMapPointsPerMeterAtLatitude(midLatitude)

        var halfWidth = max(abs(currentPoint.x - partnerPoint.x) / 2, minimumHalf) * paddingFactor
        var halfHeight = max(abs(currentPoint.y - partnerPoint.y) / 2, minimumHalf) * paddingFactor

        // Grow the short side to the card's shape so the framed rect matches the
        // image; otherwise MapKit expands it and re-centers the pins.
        if halfWidth / halfHeight < aspectRatio {
            halfWidth = halfHeight * aspectRatio
        } else {
            halfHeight = halfWidth / aspectRatio
        }

        // Center on both pins so each avatar sits the same distance from its edge.
        // The timestamp badge keeps clear of the edges by flipping to the map-facing
        // side of its avatar (see MapAvatarPin), so the framing needs no bias.
        let rect = MKMapRect(
            x: (currentPoint.x + partnerPoint.x) / 2 - halfWidth,
            y: (currentPoint.y + partnerPoint.y) / 2 - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
        return MKCoordinateRegion(rect.intersection(.world))
    }
}
