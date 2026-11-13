import MapLibre
import SwiftUI

/// PROTOTYPE. When the map first shows, it fades in under the avatars and carries them from
/// where they waited, side by side, to where they land. The avatars ride on the map points
/// under their landing spots (`introAnchors`), so the camera starts with those points on the
/// waiting spots, then zooms and turns to the framing.
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

    struct IntroSpots {
        let waiting: HomeMapAvatarPoints
        let landing: HomeMapAvatarPoints
    }

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

    /// The pose that lands `anchors` on `own` and `partnerAt`, as close as the map allows.
    /// MapLibre keeps the poles out of sight, so a couple far apart in the far north or
    /// south starts zoomed in just enough for the camera to sit where it must.
    func introPose(
        _ anchors: MapPair, own: CGPoint, partnerAt: CGPoint, viewSize: CGSize, fallbackDirection: Double
    ) -> IntroPose {
        let (ownPoint, partnerPoint) = anchors
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
        let pose = IntroPose(
            zoom: min(max(log2(hypot(sx, sy) / mapLength / 512), widestZoom), Self.introMaxZoom),
            direction: (atan2(dy, dx) - atan2(sy, sx)) * 180 / .pi,
            mid: Self.midpoint(own, partnerAt)
        )
        func zoomed(_ zoom: Double) -> IntroPose { IntroPose(zoom: zoom, direction: pose.direction, mid: pose.mid) }
        guard !keepsPolesOut(pose, anchors, viewSize: viewSize) else { return pose }
        // A wider world gives the camera more room, so the closest zoom that fits is found
        // by halving the range.
        var fits = Self.introMaxZoom
        var tooWide = pose.zoom
        for _ in 0..<24 where fits - tooWide > 0.001 {
            let zoom = (fits + tooWide) / 2
            if keepsPolesOut(zoomed(zoom), anchors, viewSize: viewSize) { fits = zoom } else { tooWide = zoom }
        }
        return zoomed(fits)
    }

    /// Whether MapLibre draws `pose` as asked. It moves the camera instead when the view,
    /// measured on its height, would show past a pole (the same limit `camera` applies).
    private func keepsPolesOut(_ pose: IntroPose, _ anchors: MapPair, viewSize: CGSize) -> Bool {
        let worldSize = 512 * pow(2, pose.zoom)
        let reach = max(0, (worldSize - Double(viewSize.height)) / 2) / worldSize
        return abs(introCenter(pose, anchors, viewSize: viewSize).y - 0.5) <= reach
    }

    /// Where the two map points land on `pose`.
    func introPoints(_ anchors: MapPair, on pose: IntroPose) -> HomeMapAvatarPoints {
        let (ownPoint, partnerPoint) = anchors
        let worldSize = 512 * pow(2, pose.zoom)
        let turn = pose.direction * .pi / 180
        let mid = Self.midpoint(ownPoint, partnerPoint)
        func point(_ mapPoint: CGPoint) -> CGPoint {
            let x = (mapPoint.x - mid.x) * worldSize
            let y = (mapPoint.y - mid.y) * worldSize
            return CGPoint(x: pose.mid.x + x * cos(turn) + y * sin(turn), y: pose.mid.y - x * sin(turn) + y * cos(turn))
        }
        return HomeMapAvatarPoints(own: point(ownPoint), partner: point(partnerPoint))
    }

    private func introCenter(_ pose: IntroPose, _ anchors: MapPair, viewSize: CGSize) -> CGPoint {
        let (ownPoint, partnerPoint) = anchors
        return Self.mapCenter(
            putting: Self.midpoint(ownPoint, partnerPoint),
            at: pose.mid,
            worldSize: 512 * pow(2, pose.zoom),
            turn: pose.direction * .pi / 180,
            viewSize: viewSize
        )
    }

    /// The map points under the spots where the avatars land: their places, moved as far
    /// as the avatars are pushed apart or kept on the map. The intro flies these, so the
    /// map carries the avatars the whole way.
    func introAnchors(viewSize: CGSize) -> MapPair {
        let places = Self.mercatorPair(current, partner)
        guard let landing = introSpots?.landing else { return places }
        let framing = framing(in: viewSize)
        let worldSize = 512 * pow(2, framing.zoom)
        let turn = framing.direction * .pi / 180
        var center = Self.mercator(framing.center)
        // The places may sit across the date line from the camera's center.
        let mid = Self.midpoint(places.own, places.partner)
        if center.x - mid.x > 0.5 { center.x -= 1 } else if mid.x - center.x > 0.5 { center.x += 1 }
        // Back from the view to the map: the inverse of `camera`'s turn.
        func mapPoint(_ point: CGPoint) -> CGPoint {
            let x = Double(point.x) - Double(viewSize.width) / 2
            let y = Double(point.y) - Double(viewSize.height) / 2
            return CGPoint(
                x: center.x + (x * cos(turn) - y * sin(turn)) / worldSize,
                y: center.y + (x * sin(turn) + y * cos(turn)) / worldSize
            )
        }
        return (mapPoint(landing.own), mapPoint(landing.partner))
    }

    /// The framing, with the avatars where they land.
    func introEndPose(viewSize: CGSize) -> IntroPose {
        let framing = framing(in: viewSize)
        let landing = introSpots?.landing ?? HomeMapAvatarPoints(own: framing.own, partner: framing.partner)
        return IntroPose(
            zoom: framing.zoom, direction: framing.direction, mid: Self.midpoint(landing.own, landing.partner)
        )
    }

    func show(_ pose: IntroPose, _ anchors: MapPair, on map: MLNMapView) {
        let center = introCenter(pose, anchors, viewSize: map.bounds.size)
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
        case flying(began: CFTimeInterval)
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
            guard isFirstFraming, parent.introSpots != nil, !UIAccessibility.isReduceMotionEnabled else {
                return false
            }
            since = .now
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(HomeMapLibreView.introLoadWait))
                self?.startIntroIfReady()
            }
        }
        guard let pose = startPose(parent, map) else {
            intro = .none
            introProgress = 1
            return false
        }
        intro = .waiting(pose, since: since)
        introProgress = 0
        parent.show(pose, introAnchors, on: map)
        return true
    }

    /// Where the flight starts: the landing points on the spots where the avatars wait now.
    /// Read again each frame, because those spots move while the cards settle.
    private func startPose(_ parent: HomeMapLibreView, _ map: MLNMapView) -> HomeMapLibreView.IntroPose? {
        guard let start = parent.introSpots?.waiting else { return nil }
        let anchors = parent.introAnchors(viewSize: map.bounds.size)
        introAnchors = anchors
        let pose = parent.introPose(
            anchors,
            own: start.own,
            partnerAt: start.partner,
            viewSize: map.bounds.size,
            fallbackDirection: parent.framing(in: map.bounds.size).direction
        )
        introStartPoints = parent.introPoints(anchors, on: pose)
        return pose
    }

    func startIntroIfReady() {
        guard case let .waiting(_, since) = intro, let parent, let map, parent.canStartIntro,
              isLoaded || Date.now.timeIntervalSince(since) >= HomeMapLibreView.introLoadWait else { return }
        intro = .flying(began: CACurrentMediaTime())
        map.tileLodZoomShift = HomeMapLibreView.tileDetailShift(zoom: parent.framing(in: map.bounds.size).zoom)
        let link = CADisplayLink(target: self, selector: #selector(introTick))
        // ProMotion screens run the flight at up to 120 Hz, like the map's own redraws.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
    }

    /// Reads where it starts and where it lands each frame, so the avatars stay on the map
    /// when either moves on the way.
    @objc private func introTick(_ link: CADisplayLink) {
        guard let parent, let map, case let .flying(began) = intro else {
            link.invalidate()
            return
        }
        let time = min(1, (link.targetTimestamp - began) / HomeMapLibreView.introDuration)
        let start = startPose(parent, map)
        guard time < 1, let start else {
            link.invalidate()
            intro = .none
            introProgress = 1
            parent.frame(map, animated: false) { true }
            handOverToExplorer(map)
            return
        }
        introProgress = HomeMapLibreView.introCurve.value(at: time)
        let end = parent.introEndPose(viewSize: map.bounds.size)
        parent.show(start.toward(end, by: introProgress), introAnchors, on: map)
    }
}

extension HomeMapLibreView.Coordinator {
    /// The intro changes during view updates, so the root hears about it on the next
    /// turn. The reports run in order, so the last one wins.
    func reportLaunchFlight() {
        guard let flight = parent?.launchFlight else { return }
        let isPlaying = if case .none = intro { false } else { true }
        Task { flight.isPlaying = isPlaying }
    }
}
