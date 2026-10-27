import MapLibre
import UIKit

extension HomeMapLibreView {
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: HomeMapLibreView?
        var lastFraming: FramingKey?
        /// MapLibre drops timed camera moves until the map has loaded.
        var isLoaded = false
        weak var map: MLNMapView?
        var intro = Intro.none
        /// From 0 to 1 as the intro carries the avatars to their places. 1 without an intro.
        var introProgress: Double = 1
        /// Both places on the intro's first camera. They miss the waiting avatars when the
        /// map can't zoom out far enough.
        var introStartPoints = HomeMapAvatarPoints(own: .zero, partner: .zero)

        /// Frames the map again when the couple, the box or the view's real size changed.
        /// The box must fit inside the view, or the fit has no room and zooms out to the world.
        func frameIfNeeded(_ map: MLNMapView) {
            guard let parent, map.bounds.width > 0, map.bounds.height >= parent.framedBox.maxY,
                  parent.explorer?.isExploring != true else { return }
            let key = framingKey(parent, map)
            guard key != lastFraming else { return }
            // A new place or box after the first framing moves the map. A new size jumps,
            // since the old view's camera doesn't fit it.
            let animated = lastFraming?.size == key.size && isLoaded && !UIAccessibility.isReduceMotionEnabled
            let isFirstFraming = lastFraming == nil
            lastFraming = key
            self.map = map
            guard !holdsIntro(map, isFirstFraming: isFirstFraming) else { return }
            parent.frame(map, animated: animated) { [weak self] in self?.lastFraming == key }
            handOverToExplorer(map)
        }

        /// Lets the person move the map, and moves it back to the couple when they ask.
        func handOverToExplorer(_ map: MLNMapView) {
            guard let explorer = parent?.explorer, explorer.map !== map else { return }
            explorer.attach(map) { [weak self, weak map] in
                guard let self, let map, let parent = self.parent else { return }
                let key = self.framingKey(parent, map)
                self.lastFraming = key
                parent.frame(map, animated: self.isLoaded && !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                    self?.lastFraming == key
                }
            }
        }

        private func framingKey(_ parent: HomeMapLibreView, _ map: MLNMapView) -> FramingKey {
            FramingKey(
                current: parent.current, partner: parent.partner, box: parent.framedBox,
                size: map.bounds.size, avatarSize: parent.avatarSize
            )
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
                direction: mapView.direction,
                zoom: mapView.zoomLevel,
                introProgress: introProgress,
                introStart: introStartPoints
            ))
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            isLoaded = true
            startIntroIfReady()
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
    let zoom: Double
    /// From 0 to 1 while the intro plays (`HomeMapLibreView+Intro`), 1 after.
    let introProgress: Double
    /// The positions on the intro's first camera.
    let introStart: HomeMapAvatarPoints
}
