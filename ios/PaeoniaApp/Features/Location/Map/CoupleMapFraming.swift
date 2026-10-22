import MapKit

/// Picks the map area that shows both partners with an even margin around them.
/// Plain math, so it can run off the main thread when the map renders.
nonisolated enum CoupleMapFraming {
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

    /// Partners within this many meters count as together. Indoor location fixes are
    /// often 30 to 65 m off, so a tighter limit would miss couples in the same room.
    static let togetherDistanceMeters: CLLocationDistance = 100

    /// True when both partners' last-known locations are in the same place. There is
    /// no rule on how far apart the two fixes are in time: a phone that sits still
    /// sends no updates, so a couple on the same couch often has fixes hours apart.
    /// The map already shows the partner's pin and age from that same fix, so only a
    /// stale one (24 hours) is ruled out.
    static func areTogether(
        current: CLLocationCoordinate2D,
        partner: CLLocationCoordinate2D,
        partnerIsStale: Bool
    ) -> Bool {
        guard !partnerIsStale else {
            return false
        }
        let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
            .distance(from: CLLocation(latitude: partner.latitude, longitude: partner.longitude))
        return distance <= togetherDistanceMeters
    }

    /// Pushes two on-screen pins apart around their midpoint until they are at least
    /// `minimumDistance` apart, so both avatars stay visible when the partners are
    /// closer than the map can show. Pins already far enough apart are returned as-is.
    /// Pins on the exact same spot are spread sideways, with `first` on the left.
    static func separated(
        _ first: CGPoint,
        _ second: CGPoint,
        minimumDistance: CGFloat
    ) -> (CGPoint, CGPoint) {
        var dx = second.x - first.x
        var dy = second.y - first.y
        var distance = hypot(dx, dy)
        guard distance < minimumDistance else {
            return (first, second)
        }
        if distance < 0.5 {
            (dx, dy, distance) = (1, 0, 1)
        }
        let mid = CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        let offsetX = dx / distance * minimumDistance / 2
        let offsetY = dy / distance * minimumDistance / 2
        return (
            CGPoint(x: mid.x - offsetX, y: mid.y - offsetY),
            CGPoint(x: mid.x + offsetX, y: mid.y + offsetY)
        )
    }
}
