import MapLibre
import SwiftUI
import UIKit

/// PROTOTYPE. A still MapLibre map of OpenStreetMap data from OpenFreeMap, recolored to
/// Paeonia's plum. Its camera fits both partners inside `framedBox`. The coordinator reports
/// their projected positions as the camera moves, so SwiftUI's avatars follow the map.
/// The data credit lives off the map.
struct HomeMapLibreView: UIViewRepresentable {
    let current: CLLocationCoordinate2D
    let partner: CLLocationCoordinate2D
    let isNear: Bool
    /// Where the couple should sit, in the map view's own coordinates.
    let framedBox: CGRect
    let avatarSize: CGFloat
    var compass: PartnerCompass?
    /// Where the avatars wait before the map shows. The map then fades in and flies them
    /// from there to their places (`HomeMapLibreView+Intro`). Nil skips the intro.
    var introStart: HomeMapAvatarPoints?
    /// The intro waits for this, so it plays where the person can see it.
    var canStartIntro = true
    /// Takes the map's drags and pinches once the intro has played.
    var explorer: HomeMapExplorer?
    var onProjection: (HomeMapProjection) -> Void

    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/dark")!
    /// Shown wherever the app credits its map data.
    static let credit = "Kartdata © OpenStreetMap-bidragsytere · OpenFreeMap · OpenMapTiles"
    /// About 10 km across a phone screen: the city, not its streets.
    private static let nearZoom: Double = 11
    /// How far apart the two avatars' centers sit when the couple is apart, in points. Close
    /// enough that the map shows the places around them, not the empty land between. Only
    /// when the world is too small to bring them this close do they sit further apart.
    private static let apartSpacing: Double = 160

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FramingMapView {
        let map = FramingMapView(frame: .zero, styleURL: Self.styleURL)
        map.delegate = context.coordinator
        // SwiftUI can hand over a new box before the view has its new size. Framing again
        // once the size really changes keeps the fit from using the old size.
        let coordinator = context.coordinator
        map.onResize = { [weak map, weak coordinator] in
            guard let map, let coordinator else { return }
            coordinator.frameIfNeeded(map)
        }
        map.isUserInteractionEnabled = false
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.compassView.isHidden = true
        map.showsScale = false
        map.backgroundColor = UIColor(Color.paeoniaBackgroundPrimary)
        compass?.setReferenceBody(map)
        return map
    }

    func updateUIView(_ map: FramingMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.frameIfNeeded(map)
        context.coordinator.startIntroIfReady()
    }

    /// The framing for a map view of `size`.
    func framing(in size: CGSize) -> Framing {
        Self.camera(current: current, partner: partner, isNear: isNear, area: framedBox, viewSize: size)
    }

    /// Zoomed far out, the tiles for that zoom carry only very simplified coastlines.
    /// Loading tiles up to three levels more detailed keeps them sharp. A city needs none.
    static func tileDetailShift(zoom: Double) -> Double {
        min(max(6 - zoom, 0), 3)
    }

    /// `animated` pans on Paeonia's standard curve and timing, so the map moves with the
    /// cards when the box changes.
    func frame(_ map: MLNMapView, animated: Bool, isCurrent: @escaping () -> Bool) {
        let camera = framing(in: map.bounds.size)
        map.contentInset = .zero
        let heading = Self.heading(camera.direction)
        map.tileLodZoomShift = Self.tileDetailShift(zoom: camera.zoom)
        guard animated else {
            map.setCenter(camera.center, zoomLevel: camera.zoom, direction: heading, animated: false)
            return
        }
        // A timed camera move takes an altitude, not a zoom. At the same view size and no
        // tilt, the altitude halves with each zoom level and follows the ground's scale at
        // the latitude.
        let now = map.camera
        let altitude = now.altitude * pow(2, map.zoomLevel - camera.zoom)
            * cos(camera.center.latitude * .pi / 180) / cos(now.centerCoordinate.latitude * .pi / 180)
        map.setCamera(
            MLNMapCamera(lookingAtCenter: camera.center, altitude: altitude, pitch: 0, heading: heading),
            withDuration: PaeoniaMotion.homeLayoutDuration,
            animationTimingFunction: HomeMapLibreTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
        ) { [weak map] in
            // A newer framing may have cut this move short, and then it lands instead.
            guard let map, isCurrent() else { return }
            // Lands exactly on the worked-out zoom.
            map.setCenter(camera.center, zoomLevel: camera.zoom, direction: heading, animated: false)
        }
    }

    /// Where the camera looks, how close, how far it turns, and where each partner lands.
    struct Framing {
        let center: CLLocationCoordinate2D
        let zoom: Double
        let direction: Double
        /// In the view's points.
        let own: CGPoint
        let partner: CGPoint
    }

    /// The framing, worked out on the Web Mercator map MapLibre draws (512 point tiles).
    /// `area` is where the two avatars' centers may go, in the view's points. Apart, the zoom
    /// puts them `apartSpacing` apart, never closer in than together, and north up. When the
    /// world is too small for that, they spread further, and the map turns only as far as it
    /// must to fit them in `area`. The midpoint between them lands in the middle of `area`.
    static func camera(
        current: CLLocationCoordinate2D,
        partner: CLLocationCoordinate2D,
        isNear: Bool,
        area: CGRect,
        viewSize: CGSize
    ) -> Framing {
        let (ownPoint, partnerPoint) = mercatorPair(current, partner)
        let (zoom, direction) = isNear
            ? (nearZoom, 0.0)
            : apartZoomAndDirection(
                dx: Double(partnerPoint.x - ownPoint.x),
                dy: Double(partnerPoint.y - ownPoint.y),
                area: area,
                viewSize: viewSize
            )
        let worldSize = 512 * pow(2, zoom)
        let turn = direction * .pi / 180
        var center = mapCenter(
            putting: midpoint(ownPoint, partnerPoint),
            at: CGPoint(x: area.midX, y: area.midY),
            worldSize: worldSize,
            turn: turn,
            viewSize: viewSize
        )
        // MapLibre keeps the poles out of sight, measured on the view's height, and moves
        // the camera to do so. The same limit here keeps the avatars on their places.
        let reach = max(0, (worldSize - Double(viewSize.height)) / 2) / worldSize
        center.y = min(max(center.y, 0.5 - reach), 0.5 + reach)
        // Back from the map to the view: the same turn, the other way.
        func point(_ mapPoint: CGPoint) -> CGPoint {
            let x = (mapPoint.x - center.x) * worldSize
            let y = (mapPoint.y - center.y) * worldSize
            return CGPoint(
                x: Double(viewSize.width) / 2 + x * cos(turn) + y * sin(turn),
                y: Double(viewSize.height) / 2 - x * sin(turn) + y * cos(turn)
            )
        }
        return Framing(
            center: coordinate(center),
            zoom: zoom,
            direction: direction,
            own: point(ownPoint),
            partner: point(partnerPoint)
        )
    }

    /// Apart, the zoom and the turn that put the two places `apartSpacing` apart inside
    /// `area`, or as close as the world allows. `dx` and `dy` run from one place to the
    /// other on the Web Mercator square.
    private static func apartZoomAndDirection(
        dx: Double,
        dy: Double,
        area: CGRect,
        viewSize: CGSize
    ) -> (zoom: Double, direction: Double) {
        func worldSize(turnedBy degrees: Double) -> Double {
            let turn = degrees * .pi / 180
            let across = abs(dx * cos(turn) + dy * sin(turn))
            let down = abs(-dx * sin(turn) + dy * cos(turn))
            return min(Double(area.width) / max(across, 1e-12), Double(area.height) / max(down, 1e-12))
        }
        var direction = 0.0
        // MapLibre never shows past the poles, so the world is at least as tall as the view.
        let widest = max(512, Double(viewSize.height))
        // `apartSpacing` apart, never closer in than together and never wider than the world.
        var zoom = max(min(log2(apartSpacing / hypot(dx, dy) / 512), nearZoom), log2(widest / 512))
        if log2(worldSize(turnedBy: 0) / 512) < zoom {
            // They don't fit north up, mostly because the world can't get any smaller, so
            // the map turns only as far as it must. How far the line between them leans
            // from level, north up, from -90 to 90.
            var lean = atan2(dx, -dy) * 180 / .pi - 90
            while lean > 90 { lean -= 180 }
            while lean <= -90 { lean += 180 }
            // The most lean that still fits the area's height at the level zoom.
            let mostLean = asin(min(1, Double(area.height) / max(Double(area.width), 1))) * 180 / .pi
            if abs(lean) > mostLean {
                direction = lean - (lean > 0 ? mostLean : -mostLean)
            }
            // Very far apart, the small turn can need a wider zoom than the world allows.
            // Lying level uses the full width, so turn all the way instead.
            if worldSize(turnedBy: direction) < widest {
                direction = lean
            }
            zoom = min(zoom, max(log2(worldSize(turnedBy: direction) / 512), log2(widest / 512)))
        }
        return (zoom, direction)
    }

    /// The two places on the Web Mercator square, the short way round, across the date
    /// line if need be.
    static func mercatorPair(
        _ current: CLLocationCoordinate2D,
        _ partner: CLLocationCoordinate2D
    ) -> (own: CGPoint, partner: CGPoint) {
        var ownPoint = mercator(current)
        var partnerPoint = mercator(partner)
        if partnerPoint.x - ownPoint.x > 0.5 {
            partnerPoint.x -= 1
        } else if ownPoint.x - partnerPoint.x > 0.5 {
            ownPoint.x -= 1
        }
        return (ownPoint, partnerPoint)
    }

    /// The camera's center, on the Web Mercator square, that lands `mapPoint` on
    /// `screenPoint`: from that point to the view's middle, turned into the map's own directions.
    static func mapCenter(
        putting mapPoint: CGPoint,
        at screenPoint: CGPoint,
        worldSize: Double,
        turn: Double,
        viewSize: CGSize
    ) -> CGPoint {
        let right = (Double(viewSize.width) / 2 - Double(screenPoint.x)) / worldSize
        let below = (Double(viewSize.height) / 2 - Double(screenPoint.y)) / worldSize
        return CGPoint(
            x: mapPoint.x + right * cos(turn) - below * sin(turn),
            y: mapPoint.y + right * sin(turn) + below * cos(turn)
        )
    }

    /// MapLibre reads a negative direction as "keep the current one", so a turn goes in as
    /// 0 to 360 degrees.
    static func heading(_ direction: Double) -> Double {
        let heading = direction.truncatingRemainder(dividingBy: 360)
        return heading < 0 ? heading + 360 : heading
    }

    static func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }

    /// From latitude and longitude to the Web Mercator square, 0 to 1 across and down.
    static func mercator(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        let latitude = min(max(coordinate.latitude, -85.05), 85.05) * .pi / 180
        return CGPoint(
            x: (coordinate.longitude + 180) / 360,
            y: (1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2
        )
    }

    static func coordinate(_ point: CGPoint) -> CLLocationCoordinate2D {
        var x = point.x.truncatingRemainder(dividingBy: 1)
        if x < 0 { x += 1 }
        let latitude = atan(sinh(.pi * (1 - 2 * Double(point.y)))) * 180 / .pi
        return CLLocationCoordinate2D(latitude: latitude, longitude: Double(x) * 360 - 180)
    }

    /// Tells its owner when its size changes, after layout.
    final class FramingMapView: MLNMapView {
        var onResize: (() -> Void)?
        private var lastSize = CGSize.zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != lastSize else { return }
            lastSize = bounds.size
            onResize?()
        }
    }

    struct FramingKey: Equatable {
        let current: CLLocationCoordinate2D
        let partner: CLLocationCoordinate2D
        let box: CGRect
        let size: CGSize
        let avatarSize: CGFloat

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.current.latitude == rhs.current.latitude && lhs.current.longitude == rhs.current.longitude
                && lhs.partner.latitude == rhs.partner.latitude && lhs.partner.longitude == rhs.partner.longitude
                && lhs.box == rhs.box && lhs.size == rhs.size && lhs.avatarSize == rhs.avatarSize
        }
    }
}

/// MapLibre 6.31 reads handles at indices 0/1 instead of Core Animation's 1/2.
/// Adapt only the timing function passed to that reader.
/// https://github.com/maplibre/maplibre-native/blob/ios-v6.31.0/platform/ios/src/MLNMapView.mm#L335-L344
nonisolated final class HomeMapLibreTimingFunction: CAMediaTimingFunction {
    override func getControlPoint(at index: Int, values: UnsafeMutablePointer<Float>) {
        let handleIndex = index == 0 || index == 1 ? index + 1 : index
        super.getControlPoint(at: handleIndex, values: values)
    }
}
