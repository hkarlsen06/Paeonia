import MapKit
import SwiftUI

/// The reveal's camera on the globe, for a guess too far from the spot for any flat
/// view. A flat map on a phone held upright shows at most about 75° of longitude,
/// and a guess across the world can be 150° away. MapKit draws the globe once its
/// camera is far enough out, on a map with realistic elevation, and keeps its north
/// up whatever heading the camera asks for. The flights to and from it move a
/// camera instead of a part of the flat map.
nonisolated enum GuessMySpotGlobe {
    /// MapKit's camera sees 30° from the top of its view to the bottom, measured
    /// with an `MKMapView`: its distance over the height it shows.
    static let focalPerHeight = 1 / (2 * tan(15 * Double.pi / 180))
    /// How far out MapKit takes its camera over the equator, a little under the
    /// 34,000 km the globe's size on screen showed (an `MKMapView` off screen says
    /// 39,800 km). It goes only cos(latitude) as far elsewhere.
    static let farthestAtEquator = 33_000_000.0

    /// How far a spot may sit from the middle of MapKit's view, in points.
    struct Room {
        let up: Double
        let down: Double
        let side: Double
    }

    /// Both spots on the globe, inside `room` of the middle of MapKit's view, which
    /// is `height` points tall. MapKit puts the camera's centre in the middle of its
    /// view, so the spots fit best when the centre sits along the great circle
    /// between them where their rooms are, nearer the spot with less room. And it
    /// backs off farther over the equator, so a centre nearer the equator fits spots
    /// farther apart. This tries both and keeps the camera that fits nearest the
    /// spots' own latitude, so the arc stays in the middle of the globe, or for
    /// spots too far apart, nearly opposite on the earth, the one that leaves the least outside.
    /// `fits` is false then.
    static func framing(
        _ guess: GuessMySpotCoordinate,
        _ spot: GuessMySpotCoordinate,
        height: Double,
        room: Room
    ) -> (camera: MapCamera, fits: Bool) {
        let focal = height * focalPerHeight
        var fitting: (camera: MapCamera, step: Int)?
        var nearest: (camera: MapCamera, over: Double)?
        for along in stride(from: 0.2, through: 0.8, by: 0.05) {
            let middle = GuessMySpotRules.intermediate(from: guess, to: spot, fraction: along)
            for step in 0...20 {
                let centre = GuessMySpotCoordinate(
                    latitude: middle.latitude * (1 - Double(step) / 20), longitude: middle.longitude
                )
                let needed = max(
                    distance(showing: guess, from: centre, focal: focal, room: room),
                    distance(showing: spot, from: centre, focal: focal, room: room)
                )
                let farthest = farthestAtEquator * cos(centre.latitude * .pi / 180)
                // A tenth more where MapKit allows, so the pins don't stand on the room's very edge.
                let camera = MapCamera(
                    centerCoordinate: centre.location,
                    distance: min(farthest, max(1_000, needed * 1.1)),
                    heading: 0,
                    pitch: 0
                )
                if needed <= farthest {
                    if let best = fitting, (best.step, best.camera.distance) <= (step, camera.distance) { continue }
                    fitting = (camera, step)
                } else if needed / farthest < nearest?.over ?? .infinity {
                    nearest = (camera, needed / farthest)
                }
            }
        }
        if let fitting { return (fitting.camera, true) }
        return (nearest?.camera ?? MapCamera(centerCoordinate: spot.location, distance: farthestAtEquator), false)
    }

    /// How far above `centre` the camera must be for `point` to show inside `room`.
    /// A point `angle` radians from the centre shows focal · R · sin(angle) / (D − R · cos(angle))
    /// points from it, the camera D from the earth's centre, in the direction of its bearing.
    private static func distance(
        showing point: GuessMySpotCoordinate,
        from centre: GuessMySpotCoordinate,
        focal: Double,
        room: Room
    ) -> Double {
        let radius = GuessMySpotRules.earthRadiusMeters
        let angle = Double(GuessMySpotRules.distanceMeters(centre, point)) / radius
        guard angle < .pi / 2 * 0.97 else { return .infinity }
        let direction = bearing(from: centre, to: point) * .pi / 180
        let across = abs(sin(direction)), along = cos(direction)
        let reach = min(
            across > 0.001 ? room.side / across : .infinity,
            abs(along) > 0.001 ? (along > 0 ? room.up : room.down) / abs(along) : .infinity
        )
        let fromCentre = radius * cos(angle) + focal * radius * sin(angle) / max(1, reach)
        // In front of the globe's edge as seen from the camera.
        return max(fromCentre, radius / cos(angle) * 1.02) - radius
    }

    /// The camera that shows `rect` over a map `size` points big, looking straight
    /// down. MapKit's view reaches `above` points up past the map and `below` down,
    /// and its camera looks at the middle of all of it.
    static func camera(showing rect: MKMapRect, size: CGSize, above: Double, below: Double) -> MapCamera {
        let perPoint = rect.width / max(1, size.width)
        let middle = MKMapPoint(x: rect.midX, y: rect.midY + (below - above) / 2 * perPoint)
        let coordinate = middle.coordinate
        let metersPerPoint = perPoint / MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        return MapCamera(
            centerCoordinate: coordinate,
            distance: metersPerPoint * (size.height + above + below) * focalPerHeight,
            heading: 0,
            pitch: 0
        )
    }

    /// Where a flight from `start` to `end` is at `fraction`, 0 to 1, before easing.
    /// It zooms at an even pace in zoom levels, and the middle travels along the
    /// great circle at the pace of the distance, so it stays on the near spot while
    /// the camera is close and crosses the world once it is far out.
    static func view(from start: MapCamera, to end: MapCamera, at fraction: Double) -> MapCamera {
        let ratio = end.distance / max(1, start.distance)
        let distance = start.distance * pow(ratio, fraction)
        let travel = abs(ratio - 1) < 0.001 ? fraction : (distance - start.distance) / (end.distance - start.distance)
        let middle = GuessMySpotRules.intermediate(
            from: GuessMySpotCoordinate(start.centerCoordinate),
            to: GuessMySpotCoordinate(end.centerCoordinate),
            fraction: travel
        )
        return MapCamera(centerCoordinate: middle.location, distance: distance, heading: 0, pitch: 0)
    }

    /// The cameras to load ahead of a flight: its start, its end, and one every two
    /// zoom levels between them, as `GuessMySpotFlight.stops`.
    static func stops(from start: MapCamera, to end: MapCamera) -> [MapCamera] {
        let levels = abs(log2(end.distance / max(1, start.distance)))
        let count = max(1, Int((levels / 2).rounded(.up)))
        return (0...count).map { view(from: start, to: end, at: Double($0) / Double(count)) }
    }

    /// The direction from `from` toward `to` along the great circle, in degrees clockwise from north.
    private static func bearing(from: GuessMySpotCoordinate, to: GuessMySpotCoordinate) -> Double {
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let angle = atan2(sin(dLon) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon))
        return angle * 180 / .pi
    }
}
