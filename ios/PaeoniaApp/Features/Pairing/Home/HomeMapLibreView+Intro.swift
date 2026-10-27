import MapLibre
import SwiftUI

/// PROTOTYPE. When the map first shows, it fades in under the avatars and carries them from
/// where they waited, side by side, to their places. The avatars follow the camera, so the
/// camera starts where the two places land on those spots, then zooms and turns to the framing.
extension HomeMapLibreView {
    static let introDuration: CFTimeInterval = 1.8
    /// The intro starts this long after the map appears even if its tiles have not loaded.
    static let introLoadWait: TimeInterval = 1.2
    /// The house curve (`PaeoniaMotion.standardCurve`).
    static let introCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.65, y: 0),
        endControlPoint: UnitPoint(x: 0.35, y: 1)
    )
    /// Street level. Two places closer than the avatars' spacing start no closer than this.
    private static let introMaxZoom: Double = 17

    /// A camera as its zoom, its turn, and where the midpoint between the two places lands.
    struct IntroPose {
        let zoom: Double
        let direction: Double
        let mid: CGPoint

        init(zoom: Double, direction: Double, mid: CGPoint) {
            self.zoom = zoom
            self.direction = direction
            self.mid = mid
        }

        init(_ framing: Framing) {
            self.init(zoom: framing.zoom, direction: framing.direction, mid: midpoint(framing.own, framing.partner))
        }

        /// Zoom and turn change at an even pace, the short way round, so both avatars swing
        /// around the midpoint while it slides to its place.
        func toward(_ end: Self, by progress: Double) -> Self {
            var turn = (end.direction - direction).truncatingRemainder(dividingBy: 360)
            if turn > 180 { turn -= 360 } else if turn <= -180 { turn += 360 }
            return Self(
                zoom: zoom + (end.zoom - zoom) * progress,
                direction: direction + turn * progress,
                mid: CGPoint(x: mid.x + (end.mid.x - mid.x) * progress, y: mid.y + (end.mid.y - mid.y) * progress)
            )
        }
    }

    /// The pose that lands `current` on `own` and `partner` on `partnerAt`, as close as the
    /// map's zoom allows.
    func introPose(own: CGPoint, partnerAt: CGPoint, viewSize: CGSize, fallbackDirection: Double) -> IntroPose {
        let (ownPoint, partnerPoint) = Self.mercatorPair(current, partner)
        let dx = Double(partnerPoint.x - ownPoint.x)
        let dy = Double(partnerPoint.y - ownPoint.y)
        let sx = Double(partnerAt.x - own.x)
        let sy = Double(partnerAt.y - own.y)
        let mapLength = hypot(dx, dy)
        // The whole world, as small as MapLibre draws it.
        let widestZoom = log2(max(512, Double(viewSize.height)) / 512)
        guard mapLength > 1e-12 else {
            return IntroPose(zoom: Self.introMaxZoom, direction: fallbackDirection, mid: Self.midpoint(own, partnerAt))
        }
        let zoom = log2(hypot(sx, sy) / mapLength / 512)
        return IntroPose(
            zoom: min(max(zoom, widestZoom), Self.introMaxZoom),
            direction: (atan2(dy, dx) - atan2(sy, sx)) * 180 / .pi,
            mid: Self.midpoint(own, partnerAt)
        )
    }

    func show(_ pose: IntroPose, on map: MLNMapView) {
        let (ownPoint, partnerPoint) = Self.mercatorPair(current, partner)
        let center = Self.mapCenter(
            putting: Self.midpoint(ownPoint, partnerPoint),
            at: pose.mid,
            worldSize: 512 * pow(2, pose.zoom),
            turn: pose.direction * .pi / 180,
            viewSize: map.bounds.size
        )
        map.setCenter(
            Self.coordinate(center), zoomLevel: pose.zoom, direction: Self.heading(pose.direction), animated: false
        )
    }
}

extension HomeMapLibreView.Coordinator {
    enum Intro {
        case none
        /// The camera holds the start pose until the map loads and the person can see it.
        case waiting(HomeMapLibreView.IntroPose, since: Date)
        case flying(HomeMapLibreView.IntroPose, began: CFTimeInterval)
    }

    /// Holds the camera on the intro's start pose, or leaves it to a flight under way.
    /// Returns false when there is no intro, and the map takes its framing.
    func holdsIntro(_ map: MLNMapView, isFirstFraming: Bool) -> Bool {
        guard let parent else { return false }
        let since: Date
        switch intro {
        case .flying:
            return true
        case let .waiting(_, waitingSince):
            since = waitingSince
        case .none:
            guard isFirstFraming, parent.introStart != nil, !UIAccessibility.isReduceMotionEnabled else {
                return false
            }
            since = .now
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(HomeMapLibreView.introLoadWait))
                self?.startIntroIfReady()
            }
        }
        guard let start = parent.introStart else {
            intro = .none
            introProgress = 1
            return false
        }
        let pose = parent.introPose(
            own: start.own,
            partnerAt: start.partner,
            viewSize: map.bounds.size,
            fallbackDirection: parent.framing(in: map.bounds.size).direction
        )
        intro = .waiting(pose, since: since)
        introProgress = 0
        parent.show(pose, on: map)
        introStartPoints = HomeMapAvatarPoints(
            own: map.convert(parent.current, toPointTo: map),
            partner: map.convert(parent.partner, toPointTo: map)
        )
        return true
    }

    func startIntroIfReady() {
        guard case let .waiting(pose, since) = intro, let parent, let map, parent.canStartIntro,
              isLoaded || Date.now.timeIntervalSince(since) >= HomeMapLibreView.introLoadWait else { return }
        intro = .flying(pose, began: CACurrentMediaTime())
        map.tileLodZoomShift = min(max(6 - parent.framing(in: map.bounds.size).zoom, 0), 3)
        let link = CADisplayLink(target: self, selector: #selector(introTick))
        link.add(to: .main, forMode: .common)
    }

    /// Reads the framing each frame, so the flight lands on a framing that changed on the way.
    @objc private func introTick(_ link: CADisplayLink) {
        guard let parent, let map, case let .flying(start, began) = intro else {
            link.invalidate()
            return
        }
        let time = min(1, (link.targetTimestamp - began) / HomeMapLibreView.introDuration)
        guard time < 1 else {
            link.invalidate()
            intro = .none
            introProgress = 1
            parent.frame(map, animated: false) { true }
            handOverToExplorer(map)
            return
        }
        introProgress = HomeMapLibreView.introCurve.value(at: time)
        let end = HomeMapLibreView.IntroPose(parent.framing(in: map.bounds.size))
        parent.show(start.toward(end, by: introProgress), on: map)
    }
}
