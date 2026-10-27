import MapLibre
import UIKit

extension HomeMapLibreView {
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

        // Give SwiftUI time to lay out before the map draws. The render callback
        // also covers the first frame and changes made without animation.
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            publishProjection(mapView)
        }

        func mapViewWillStartRenderingFrame(_ mapView: MLNMapView) {
            publishProjection(mapView)
        }

        private func publishProjection(_ mapView: MLNMapView) {
            guard let parent, lastFraming != nil else { return }
            parent.onProjection(HomeMapProjection(
                own: mapView.convert(parent.current, toPointTo: mapView),
                partner: mapView.convert(parent.partner, toPointTo: mapView),
                direction: mapView.direction
            ))
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            isLoaded = true
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            HomeMapLibreView.recolor(style)
        }
    }
}

/// The positions on the camera being drawn, before any avatar spacing is applied.
struct HomeMapProjection: Equatable {
    let own: CGPoint
    let partner: CGPoint
    let direction: Double
}
