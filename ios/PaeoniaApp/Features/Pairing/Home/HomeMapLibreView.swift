import MapLibre
import SwiftUI
import UIKit

/// PROTOTYPE. A still MapLibre map of OpenStreetMap data from OpenFreeMap, recolored to
/// Paeonia's plum. It frames both partners' centers inside `framedBox` and reports where each one
/// lands, so SwiftUI can draw the avatars on top. The data credit lives off the map.
struct HomeMapLibreView: UIViewRepresentable {
    let current: CLLocationCoordinate2D
    let partner: CLLocationCoordinate2D
    let isNear: Bool
    /// Where the couple should sit, in the map view's own coordinates.
    let framedBox: CGRect
    let avatarSize: CGFloat
    let onPoints: (_ own: CGPoint, _ partner: CGPoint) -> Void

    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/dark")!
    /// Shown wherever the app credits its map data.
    static let credit = "Kartdata © OpenStreetMap-bidragsytere · OpenFreeMap · OpenMapTiles"
    /// About 10 km across a phone screen: the city, not its streets.
    private static let nearZoom: Double = 11

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

    fileprivate func frame(_ map: MLNMapView) {
        let camera = Self.camera(
            current: current, partner: partner, isNear: isNear, area: framedBox, viewSize: map.bounds.size
        )
        map.contentInset = .zero
        // MapLibre reads a negative direction as "keep the current one", so the same turn
        // goes in as 0 to 360 degrees.
        let heading = camera.direction < 0 ? camera.direction + 360 : camera.direction
        map.setCenter(camera.center, zoomLevel: camera.zoom, direction: heading, animated: false)
        // Zoomed far out, the tiles for that zoom carry only very simplified coastlines.
        // Loading tiles up to three levels more detailed keeps them sharp. A city needs none.
        map.tileLodZoomShift = min(max(6 - camera.zoom, 0), 3)
        report(map)
    }

    /// Where the camera looks, how close, and how far it turns, worked out on the Web
    /// Mercator map MapLibre draws (512 point tiles). `area` is where the two avatars'
    /// centers may go, in the view's points. Apart, the map stays north up when both fit
    /// there, and otherwise turns only as far as it must to fit them. The zoom is as close
    /// as still fits both, and the midpoint between them lands in the middle of `area`.
    static func camera(
        current: CLLocationCoordinate2D,
        partner: CLLocationCoordinate2D,
        isNear: Bool,
        area: CGRect,
        viewSize: CGSize
    ) -> (center: CLLocationCoordinate2D, zoom: Double, direction: Double) {
        var a = mercator(current)
        var b = mercator(partner)
        // The short way round, across the date line if need be.
        if b.x - a.x > 0.5 { b.x -= 1 } else if a.x - b.x > 0.5 { a.x -= 1 }
        var direction = 0.0
        var zoom = nearZoom
        if !isNear {
            let dx = Double(b.x - a.x)
            let dy = Double(b.y - a.y)
            // How far the line between them leans from level, north up, from -90 to 90.
            var lean = atan2(dx, -dy) * 180 / .pi - 90
            while lean > 90 { lean -= 180 }
            while lean <= -90 { lean += 180 }
            // The most lean that still fits the area's height at the level zoom.
            let mostLean = asin(min(1, Double(area.height) / max(Double(area.width), 1))) * 180 / .pi
            if abs(lean) > mostLean {
                direction = lean - (lean > 0 ? mostLean : -mostLean)
            }
            func worldSize(turnedBy degrees: Double) -> Double {
                let turn = degrees * .pi / 180
                let across = abs(dx * cos(turn) + dy * sin(turn))
                let down = abs(-dx * sin(turn) + dy * cos(turn))
                return min(Double(area.width) / max(across, 1e-12), Double(area.height) / max(down, 1e-12))
            }
            // MapLibre never shows past the poles, so the world is at least as tall as the
            // view. Very far apart, the small turn can need a wider zoom than that. Lying
            // level uses the full width, so turn all the way instead.
            let widest = max(512, Double(viewSize.height))
            if worldSize(turnedBy: direction) < widest {
                direction = lean
            }
            zoom = min(max(log2(worldSize(turnedBy: direction) / 512), log2(widest / 512)), nearZoom + 1)
        }
        let worldSize = 512 * pow(2, zoom)
        // From the area's middle to the view's middle, in points, turned into the map's
        // own directions.
        let right = (Double(viewSize.width) / 2 - Double(area.midX)) / worldSize
        let below = (Double(viewSize.height) / 2 - Double(area.midY)) / worldSize
        let turn = direction * .pi / 180
        let center = CGPoint(
            x: (a.x + b.x) / 2 + right * cos(turn) - below * sin(turn),
            y: (a.y + b.y) / 2 + right * sin(turn) + below * cos(turn)
        )
        return (coordinate(center), zoom, direction)
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

    fileprivate func report(_ map: MLNMapView) {
        let own = map.convert(current, toPointTo: map)
        let other = map.convert(partner, toPointTo: map)
        // Off the SwiftUI update pass, which this can run inside.
        DispatchQueue.main.async { onPoints(own, other) }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: HomeMapLibreView?
        var lastFraming: FramingKey?

        /// Frames the map again when the couple, the box or the view's real size changed.
        /// The box must fit inside the view, or the fit has no room and zooms out to the world.
        func frameIfNeeded(_ map: MLNMapView) {
            guard let parent, map.bounds.width > 0, map.bounds.height >= parent.framedBox.maxY else { return }
            let key = FramingKey(
                current: parent.current, partner: parent.partner, box: parent.framedBox,
                size: map.bounds.size, avatarSize: parent.avatarSize
            )
            guard key != lastFraming else { return }
            lastFraming = key
            parent.frame(map)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            HomeMapLibreView.recolor(style)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent?.report(mapView)
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            parent?.report(mapView)
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
