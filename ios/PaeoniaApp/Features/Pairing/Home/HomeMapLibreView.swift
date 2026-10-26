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
            map.setCenter(mid, zoomLevel: Self.nearZoom, animated: false)
        } else {
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(
                    latitude: min(current.latitude, partner.latitude),
                    longitude: min(current.longitude, partner.longitude)
                ),
                ne: CLLocationCoordinate2D(
                    latitude: max(current.latitude, partner.latitude),
                    longitude: max(current.longitude, partner.longitude)
                )
            )
            // Keeps each whole avatar, and the note bubble over it, inside the box.
            let half = avatarSize / 2
            map.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: half + 44, left: half + 28, bottom: half + 4, right: half + 28),
                animated: false,
                completionHandler: nil
            )
        }
        report(map)
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
                    layer.fillColor = constant(green)
                    layer.fillOpacity = constant(0.55)
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
}
