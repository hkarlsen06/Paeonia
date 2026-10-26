import MapLibre
import SwiftUI
import UIKit

/// PROTOTYPE. A still MapLibre map of OpenStreetMap data from OpenFreeMap, recolored to
/// Paeonia's plum. It frames both partners inside `framedBox` and reports where each one
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

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: Self.styleURL)
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.compassView.isHidden = true
        map.showsScale = false
        map.backgroundColor = UIColor(Color.paeoniaBackgroundPrimary)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        let key = FramingKey(
            current: current, partner: partner, box: framedBox, size: map.bounds.size, avatarSize: avatarSize
        )
        guard map.bounds.width > 0, key != context.coordinator.lastFraming else { return }
        context.coordinator.lastFraming = key
        frame(map)
    }

    private func frame(_ map: MLNMapView) {
        // The box becomes the map's content area, so "center" means the middle of the box.
        map.contentInset = UIEdgeInsets(
            top: framedBox.minY,
            left: framedBox.minX,
            bottom: max(map.bounds.height - framedBox.maxY, 0),
            right: max(map.bounds.width - framedBox.maxX, 0)
        )
        if isNear {
            let mid = CLLocationCoordinate2D(
                latitude: (current.latitude + partner.latitude) / 2,
                longitude: (current.longitude + partner.longitude) / 2
            )
            map.setCenter(mid, zoomLevel: Self.nearZoom, direction: 0, animated: false)
        } else {
            // Turned so the two sit on one level line, which fits the map's fixed height.
            // Each whole avatar stays inside the box's sides.
            var coordinates = [current, partner]
            let line = MLNPolyline(coordinates: &coordinates, count: 2)
            let side = avatarSize / 2 + 28
            let camera = map.cameraThatFitsShape(
                line,
                direction: Self.direction(from: current, to: partner),
                edgePadding: UIEdgeInsets(top: 0, left: side, bottom: 0, right: side)
            )
            map.setCamera(camera, animated: false)
        }
        report(map)
    }

    /// The map rotation, in degrees clockwise from north, that lays the line between the
    /// two places out level on screen. The angle is measured on the flat Mercator map the
    /// view draws, so it holds far north too. It turns at most a quarter turn either way,
    /// so north is never below the middle, and whoever is further west stays on the left.
    static func direction(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
        var dx = b.longitude - a.longitude
        if dx > 180 { dx -= 360 } else if dx < -180 { dx += 360 }
        func mercatorY(_ latitude: Double) -> Double {
            log(tan(.pi / 4 + latitude * .pi / 360)) * 180 / .pi
        }
        let dy = mercatorY(b.latitude) - mercatorY(a.latitude)
        guard dx != 0 || dy != 0 else { return 0 }
        var direction = atan2(dx, dy) * 180 / .pi - 90
        while direction > 90 { direction -= 180 }
        while direction <= -90 { direction += 180 }
        return direction
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
        let farWater = UIColor(red: 0.22, green: 0.07, blue: 0.15, alpha: 1)

        for layer in style.layers {
            let id = layer.identifier
            switch layer {
            case let layer as MLNBackgroundStyleLayer:
                layer.backgroundColor = constant(land)
            case let layer as MLNFillStyleLayer:
                if id.hasPrefix("aeroway") || id.hasPrefix("road") {
                    layer.isVisible = false
                } else if id.hasPrefix("water") {
                    // Zoomed out, the tiles carry simplified coastlines, so water fades
                    // toward the land color there and only reads as a hint.
                    layer.fillColor = byZoom([4: farWater, 8: water])
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
