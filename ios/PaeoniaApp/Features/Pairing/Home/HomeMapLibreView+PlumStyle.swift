import MapLibre
import UIKit

extension HomeMapLibreView {
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
                recolor(layer, id: id, water: water, building: building, green: green)
            case let layer as MLNLineStyleLayer:
                recolor(layer, id: id, mainRoad: mainRoad, water: water)
            case is MLNSymbolStyleLayer:
                layer.isVisible = false
            default:
                break
            }
        }
    }

    private static func recolor(
        _ layer: MLNFillStyleLayer, id: String, water: UIColor, building: UIColor, green: UIColor
    ) {
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
    }

    private static func recolor(_ layer: MLNLineStyleLayer, id: String, mainRoad: UIColor, water: UIColor) {
        let isMainRoad = (id.hasPrefix("highway_motorway") || id.hasPrefix("highway_major"))
            && !id.hasSuffix("_casing")
        if isMainRoad {
            layer.lineColor = constant(mainRoad)
            // Zoomed out to a continent, the sharper tiles carry every main road, a tangle
            // at that size. The map is then only land and sea.
            layer.lineOpacity = byZoom([4.5: 0, 6: 1])
            layer.lineWidth = constant(0.6)
        } else if id.hasPrefix("waterway") {
            layer.lineColor = constant(water)
        } else {
            layer.isVisible = false
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
