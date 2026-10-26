import MapLibre
import SwiftUI
import UIKit

/// PROTOTYPE. A still MapLibre map of OpenStreetMap data from OpenFreeMap, recolored to
/// Paeonia's plum. It places both partners' centers inside `framedBox`, with the camera from
/// `camera(current:partner:isNear:area:viewSize:)`, which also says where each one lands, so
/// SwiftUI draws the avatars on top in its own layout. The data credit lives off the map.
struct HomeMapLibreView: UIViewRepresentable {
    let current: CLLocationCoordinate2D
    let partner: CLLocationCoordinate2D
    let isNear: Bool
    /// Where the couple should sit, in the map view's own coordinates.
    let framedBox: CGRect
    let avatarSize: CGFloat

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
        return map
    }

    func updateUIView(_ map: FramingMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.frameIfNeeded(map)
    }

    /// `animated` pans on Paeonia's standard curve and timing, so the map moves with the
    /// cards when the box changes.
    fileprivate func frame(_ map: MLNMapView, animated: Bool, isCurrent: @escaping () -> Bool) {
        let camera = Self.camera(
            current: current, partner: partner, isNear: isNear, area: framedBox, viewSize: map.bounds.size
        )
        map.contentInset = .zero
        // MapLibre reads a negative direction as "keep the current one", so the same turn
        // goes in as 0 to 360 degrees.
        let heading = camera.direction < 0 ? camera.direction + 360 : camera.direction
        // Zoomed far out, the tiles for that zoom carry only very simplified coastlines.
        // Loading tiles up to three levels more detailed keeps them sharp. A city needs none.
        map.tileLodZoomShift = min(max(6 - camera.zoom, 0), 3)
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
            withDuration: PaeoniaMotion.motionDefault,
            animationTimingFunction: CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
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
        var a = mercator(current)
        var b = mercator(partner)
        // The short way round, across the date line if need be.
        if b.x - a.x > 0.5 { b.x -= 1 } else if a.x - b.x > 0.5 { a.x -= 1 }
        var direction = 0.0
        var zoom = nearZoom
        if !isNear {
            let dx = Double(b.x - a.x)
            let dy = Double(b.y - a.y)
            func worldSize(turnedBy degrees: Double) -> Double {
                let turn = degrees * .pi / 180
                let across = abs(dx * cos(turn) + dy * sin(turn))
                let down = abs(-dx * sin(turn) + dy * cos(turn))
                return min(Double(area.width) / max(across, 1e-12), Double(area.height) / max(down, 1e-12))
            }
            // MapLibre never shows past the poles, so the world is at least as tall as the view.
            let widest = max(512, Double(viewSize.height))
            // `apartSpacing` apart, never closer in than together and never wider than the world.
            zoom = max(min(log2(apartSpacing / hypot(dx, dy) / 512), nearZoom), log2(widest / 512))
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
        }
        let worldSize = 512 * pow(2, zoom)
        // From the area's middle to the view's middle, in points, turned into the map's
        // own directions.
        let right = (Double(viewSize.width) / 2 - Double(area.midX)) / worldSize
        let below = (Double(viewSize.height) / 2 - Double(area.midY)) / worldSize
        let turn = direction * .pi / 180
        var center = CGPoint(
            x: (a.x + b.x) / 2 + right * cos(turn) - below * sin(turn),
            y: (a.y + b.y) / 2 + right * sin(turn) + below * cos(turn)
        )
        // MapLibre keeps the poles out of sight, measured on the view's height, and moves
        // the camera to do so. The same limit here keeps the avatars on their places.
        let reach = max(0, (worldSize - Double(viewSize.height)) / 2) / worldSize
        center.y = min(max(center.y, 0.5 - reach), 0.5 + reach)
        // Back from the map to the view: the same turn, the other way.
        func point(_ m: CGPoint) -> CGPoint {
            let x = (m.x - center.x) * worldSize
            let y = (m.y - center.y) * worldSize
            return CGPoint(
                x: Double(viewSize.width) / 2 + x * cos(turn) + y * sin(turn),
                y: Double(viewSize.height) / 2 - x * sin(turn) + y * cos(turn)
            )
        }
        return Framing(
            center: coordinate(center), zoom: zoom, direction: direction, own: point(a), partner: point(b)
        )
    }

    /// From latitude and longitude to the Web Mercator square, 0 to 1 across and down.
    private static func mercator(_ c: CLLocationCoordinate2D) -> CGPoint {
        let latitude = min(max(c.latitude, -85.05), 85.05) * .pi / 180
        return CGPoint(
            x: (c.longitude + 180) / 360,
            y: (1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2
        )
    }

    private static func coordinate(_ p: CGPoint) -> CLLocationCoordinate2D {
        var x = p.x.truncatingRemainder(dividingBy: 1)
        if x < 0 { x += 1 }
        let latitude = atan(sinh(.pi * (1 - 2 * Double(p.y)))) * 180 / .pi
        return CLLocationCoordinate2D(latitude: latitude, longitude: Double(x) * 360 - 180)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: HomeMapLibreView?
        var lastFraming: FramingKey?
        /// MapLibre drops timed camera moves until the map has loaded.
        var isLoaded = false

        /// Frames the map again when the couple, the box or the view's real size changed.
        /// The box must fit inside the view, or the fit has no room and zooms out to the world.
        func frameIfNeeded(_ map: MLNMapView) {
            guard let parent, map.bounds.width > 0, map.bounds.height >= parent.framedBox.maxY else { return }
            let key = FramingKey(
                current: parent.current, partner: parent.partner, box: parent.framedBox,
                size: map.bounds.size, avatarSize: parent.avatarSize
            )
            guard key != lastFraming else { return }
            // A new place or box after the first framing moves the map. A new size jumps,
            // since the old view's camera doesn't fit it.
            let animated = lastFraming?.size == key.size && isLoaded && !UIAccessibility.isReduceMotionEnabled
            lastFraming = key
            parent.frame(map, animated: animated) { [weak self] in self?.lastFraming == key }
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            isLoaded = true
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            HomeMapLibreView.recolor(style)
        }

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

    // MARK: Plum style

    /// Paints OpenFreeMap's dark style in Paeonia's colors: plum land and deeper plum water,
    /// no labels, and only the main roads, as hairlines.
    static func recolor(_ style: MLNStyle) {
        let land = UIColor(red: 0.27, green: 0.09, blue: 0.19, alpha: 1)
        let water = UIColor(red: 0.13, green: 0.03, blue: 0.09, alpha: 1)
        let green = UIColor(red: 0.30, green: 0.11, blue: 0.22, alpha: 1)
        let building = UIColor(red: 0.33, green: 0.13, blue: 0.24, alpha: 1)
        let mainRoad = UIColor(red: 0.42, green: 0.17, blue: 0.30, alpha: 1)

        for layer in style.layers {
            let id = layer.identifier
            switch layer {
            case let layer as MLNBackgroundStyleLayer:
                layer.backgroundColor = constant(land)
            case let layer as MLNFillStyleLayer:
                if id.hasPrefix("aeroway") || id.hasPrefix("road") {
                    layer.isVisible = false
                } else if id.hasPrefix("water") {
                    layer.fillColor = constant(water)
                    layer.fillOpacity = constant(1)
                } else if id.hasPrefix("building") {
                    layer.fillColor = constant(building)
                    layer.fillOpacity = constant(0.6)
                } else {
                    // Forest, park and ice patches are coarse blocks until about zoom 8.
                    layer.fillColor = constant(green)
                    layer.fillOpacity = byZoom([7: 0, 9: 0.55])
                }
            case let layer as MLNLineStyleLayer:
                let isMainRoad = (id.hasPrefix("highway_motorway") || id.hasPrefix("highway_major"))
                    && !id.hasSuffix("_casing")
                if isMainRoad {
                    layer.lineColor = constant(mainRoad)
                    layer.lineOpacity = constant(1)
                    layer.lineWidth = constant(0.6)
                } else if id.hasPrefix("waterway") {
                    layer.lineColor = constant(water)
                } else {
                    layer.isVisible = false
                }
            case is MLNSymbolStyleLayer:
                layer.isVisible = false
            default:
                break
            }
        }
    }

    private static func constant(_ value: Any) -> NSExpression {
        NSExpression(forConstantValue: value)
    }

    /// A value that changes smoothly with the zoom level, between the given stops.
    private static func byZoom(_ stops: [Double: Any]) -> NSExpression {
        NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            stops as NSDictionary
        )
    }
}
