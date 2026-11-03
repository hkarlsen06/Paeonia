import MapLibre
import SwiftUI
import UIKit

extension HomeMapLibreView {
    /// Paints OpenFreeMap's dark style in Paeonia's colors: plum land and deeper plum water,
    /// no labels, and only the main roads, as hairlines.
    static func recolor(_ style: MLNStyle) {
        let land = UIColor(PaeoniaMapPalette.land)
        let water = UIColor(PaeoniaMapPalette.water)
        let green = UIColor(PaeoniaMapPalette.vegetation)
        let building = UIColor(PaeoniaMapPalette.building)
        let mainRoad = UIColor(PaeoniaMapPalette.mainRoad)

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
            // at that size. The map is then only land and sea. Closer in, the roads stay
            // faint: the map shows where the partner is, not how to get there.
            layer.lineOpacity = byZoom([4.5: 0, 6: 0.4])
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
            format: "FUNCTION($zoomLevel, 'mgl_interpolateWithCurveType:parameters:stops:', 'linear', nil, %@)",
            stops as NSDictionary
        )
    }
}
