import CoreLocation
import MapLibre

/// Before both places are known, Home shows the world faintly behind the row of avatars,
/// a hint of the map to come. It is the same map view, so once both places arrive the
/// intro flies from this world to the couple's framing, with its tiles already loaded.
extension HomeMapLibreView {
    struct PreviewCamera: Equatable {
        /// On the Web Mercator square, 0 to 1 across and down.
        let center: CGPoint
        let zoom: Double

        /// About three screen widths of world, a third of the way round. Northern mid
        /// latitudes sit where the row of avatars is, and the middle of this phone's time
        /// zone runs down the middle, so most people see their own part of the world.
        init(viewSize: CGSize, timeZone: TimeZone = .current) {
            let width = Double(viewSize.width)
            let height = Double(viewSize.height)
            // MapLibre never shows past the poles, so the world is at least as tall as the view.
            zoom = log2(max(3 * width, height, 512) / 512)
            let worldSize = 512 * pow(2, zoom)
            let standardOffset = Double(timeZone.secondsFromGMT()) - timeZone.daylightSavingTimeOffset()
            let longitude = standardOffset / 3_600 * 15
            let focus = HomeMapLibreView.mercator(CLLocationCoordinate2D(latitude: 50, longitude: longitude))
            // 50° north lands at the row of avatars, about a sixth of the way down the view.
            var y = focus.y + (height / 2 - height * Self.focusFraction) / worldSize
            let reach = max(0, (worldSize - height) / 2) / worldSize
            y = min(max(y, 0.5 - reach), 0.5 + reach)
            center = CGPoint(x: focus.x, y: y)
        }

        private static let focusFraction = 0.16

        /// The intro's pose for this camera: its zoom, north up, and where the midpoint
        /// between the two map points lands, on the copy of the world nearest the middle.
        func pose(of anchors: MapPair, viewSize: CGSize) -> IntroPose {
            let worldSize = 512 * pow(2, zoom)
            var mid = HomeMapLibreView.midpoint(anchors.own, anchors.partner)
            mid.x -= (mid.x - center.x).rounded()
            return IntroPose(
                zoom: zoom,
                direction: 0,
                mid: CGPoint(
                    x: Double(viewSize.width) / 2 + (mid.x - center.x) * worldSize,
                    y: Double(viewSize.height) / 2 + (mid.y - center.y) * worldSize
                )
            )
        }
    }
}

extension HomeMapLibreView.Coordinator {
    /// Shows the world for a view of this size. A couple that arrives later is a first
    /// framing, so the intro plays from here, even when the last one left mid-flight or
    /// while the person was looking around.
    func showPreview(_ map: MLNMapView) {
        self.map = map
        lastFraming = nil
        if case .none = intro {} else { intro = .none }
        parent?.explorer?.detach()
        let camera = HomeMapLibreView.PreviewCamera(viewSize: map.bounds.size)
        guard camera != preview else { return }
        preview = camera
        map.tileLodZoomShift = HomeMapLibreView.tileDetailShift(zoom: camera.zoom)
        map.setCenter(
            HomeMapLibreView.coordinate(camera.center), zoomLevel: camera.zoom, direction: 0, animated: false
        )
    }
}
