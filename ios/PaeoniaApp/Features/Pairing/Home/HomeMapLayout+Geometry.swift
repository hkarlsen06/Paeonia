import CoreLocation
import SwiftUI

struct HomeMapAvatarPoints: Equatable {
    let own: CGPoint
    let partner: CGPoint

    /// Holds each avatar inside the open map. Only a couple on opposite sides of the world
    /// can be too far apart for the widest zoom, and then an avatar waits at the edge, on
    /// the side its partner is.
    func kept(inside bounds: CGRect) -> Self {
        func keep(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        }
        return Self(own: keep(own), partner: keep(partner))
    }

    /// Where the avatars are while the person looks around, with these as their places
    /// on the map now. Each keeps the spacing `spaced` gave it on the camera the person
    /// started from, and that spacing turns with the map and shrinks with it as it zooms
    /// out, so the avatars stay where they were on the map and come together when they
    /// get small. `zoomChange` is the map's scale against that camera, and `turn` how far
    /// it has turned on screen, clockwise in radians.
    func pinned(zoomChange: CGFloat, turn: CGFloat, spaced: (Self) -> Self) -> Self {
        let between = CGPoint(x: partner.x - own.x, y: partner.y - own.y).rotated(by: -turn)
        let half = CGPoint(x: between.x / zoomChange / 2, y: between.y / zoomChange / 2)
        let atStart = Self(own: CGPoint(x: -half.x, y: -half.y), partner: half)
        let spacedAtStart = spaced(atStart)
        let shrink = min(1, zoomChange)
        func moved(_ point: CGPoint, from start: CGPoint, to spot: CGPoint) -> CGPoint {
            let offset = CGPoint(x: spot.x - start.x, y: spot.y - start.y).rotated(by: turn)
            return CGPoint(x: point.x + offset.x * shrink, y: point.y + offset.y * shrink)
        }
        return Self(
            own: moved(own, from: atStart.own, to: spacedAtStart.own),
            partner: moved(partner, from: atStart.partner, to: spacedAtStart.partner)
        )
    }

    /// Where the avatars are while the intro plays, with these as their places on the map
    /// now. They turn and zoom with the map. They start where they waited and end on their
    /// spaced-out spots, so the difference from their places on the map shifts from one to
    /// the other. Their midpoint slides straight across, since MapLibre keeps the poles out
    /// of sight by moving a far-out, turned camera.
    func duringIntro(
        rawStart: Self,
        waiting: Self,
        rawEnd: Self,
        end: Self,
        progress: Double
    ) -> Self {
        let waiting = HomeMapPairShape(waiting)
        let end = HomeMapPairShape(end)
        let shape = HomeMapPairShape(self)
            .applying(HomeMapPairShape(rawStart).change(to: waiting), times: 1 - progress)
            .applying(HomeMapPairShape(rawEnd).change(to: end), times: progress)
        let slide = waiting.change(to: end).mid
        let mid = CGPoint(x: waiting.mid.x + slide.x * progress, y: waiting.mid.y + slide.y * progress)
        return HomeMapPairShape(mid: mid, logDistance: shape.logDistance, angle: shape.angle).points
    }
}

/// Two avatars as their midpoint, how far apart they are and which way the partner is.
struct HomeMapPairShape {
    let mid: CGPoint
    /// The natural log of the distance in points, so a change scales it.
    let logDistance: Double
    /// In radians, from the person to the partner.
    let angle: Double

    init(mid: CGPoint, logDistance: Double, angle: Double) {
        self.mid = mid
        self.logDistance = logDistance
        self.angle = angle
    }

    init(_ points: HomeMapAvatarPoints) {
        let dx = Double(points.partner.x - points.own.x)
        let dy = Double(points.partner.y - points.own.y)
        self.init(
            mid: CGPoint(x: (points.own.x + points.partner.x) / 2, y: (points.own.y + points.partner.y) / 2),
            logDistance: log(max(hypot(dx, dy), 1)),
            angle: atan2(dy, dx)
        )
    }

    var points: HomeMapAvatarPoints {
        let half = exp(logDistance) / 2
        let step = CGPoint(x: half * cos(angle), y: half * sin(angle))
        return HomeMapAvatarPoints(
            own: CGPoint(x: mid.x - step.x, y: mid.y - step.y),
            partner: CGPoint(x: mid.x + step.x, y: mid.y + step.y)
        )
    }

    /// What turns this shape into `other`, turning the short way round.
    func change(to other: Self) -> Self {
        var turn = (other.angle - angle).truncatingRemainder(dividingBy: 2 * .pi)
        if turn > .pi { turn -= 2 * .pi } else if turn <= -.pi { turn += 2 * .pi }
        return Self(
            mid: CGPoint(x: other.mid.x - mid.x, y: other.mid.y - mid.y),
            logDistance: other.logDistance - logDistance,
            angle: turn
        )
    }

    func applying(_ change: Self, times fraction: Double) -> Self {
        Self(
            mid: CGPoint(x: mid.x + change.mid.x * fraction, y: mid.y + change.mid.y * fraction),
            logDistance: logDistance + change.logDistance * fraction,
            angle: angle + change.angle * fraction
        )
    }
}

struct HomeMapCouple {
    let current: LocationPoint
    let partner: LocationPoint
    let currentCoordinate: CLLocationCoordinate2D
    let partnerCoordinate: CLLocationCoordinate2D
    let partnerWasStaleAtLastRefresh: Bool

    /// Close enough that the map shows one city, so both avatars sit side by side in the middle.
    var isNear: Bool {
        CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
            .distance(from: CLLocation(latitude: partnerCoordinate.latitude, longitude: partnerCoordinate.longitude))
            < CoupleMapFraming.minimumSpanMeters / CoupleMapFraming.paddingFactor
    }
}

/// The screen the page sits in, in the scroll content's coordinates, which start at the top
/// of the screen.
struct HomeMapScreen {
    let width: CGFloat
    let topInset: CGFloat
    /// Where the safe area ends, at the top of the tab bar.
    let visibleBottom: CGFloat

    init(geo: GeometryProxy) {
        width = geo.size.width
        topInset = geo.safeAreaInsets.top
        visibleBottom = topInset + geo.size.height
    }

    /// The page's height when the cards fit: the last card ends just above the tab bar.
    var fillHeight: CGFloat { visibleBottom - PaeoniaSpacing.space8 }
    /// At least room for the avatars, plus the fade.
    var shortestBand: CGFloat { topInset + 212 + HomeMapMetrics.fadeHeight }
    /// The map view's own height: the tallest the band can be.
    var mapHeight: CGFloat { visibleBottom + HomeMapMetrics.fadeHeight }
}

struct HomeMapMetrics {
    static let fadeHeight: CGFloat = 260
    static var cardsOverlap: CGFloat { fadeHeight - PaeoniaSpacing.space16 }

    let screen: HomeMapScreen
    let bandHeight: CGFloat
    /// The bottom of the last row where the map is fully shown.
    let framedBottom: CGFloat
    /// Where the avatars' centers may go, in the map's coordinates.
    let framedBox: CGRect
    /// The open map, less half an avatar, so a held avatar stays whole and clear of the
    /// bar and the first card.
    let avatarBounds: CGRect
    /// How far past `avatarBounds` an avatar fades out while the person looks around. It is
    /// gone by the time its middle reaches the screen's side.
    let avatarFade: CGFloat

    var width: CGFloat { screen.width }
    /// The fade starts a little above the cards and runs to the bottom of the band.
    var fadeLength: CGFloat { Self.fadeHeight + 20 }

    init(screen: HomeMapScreen, bandHeight: CGFloat, avatarSize: CGFloat, isNear: Bool) {
        self.screen = screen
        self.bandHeight = bandHeight
        framedBottom = bandHeight - Self.fadeHeight
        let cardsTop = framedBottom + PaeoniaSpacing.space16
        // The avatars are centered in the open map between the streak pill and the first
        // card. The bar's glass is off at rest, so the pill is where the space starts.
        // Together they sit side by side in the middle. Apart, they may go anywhere in that
        // space with the same margin above and below, room for a note bubble each way, so
        // the pair always stays centered.
        let pillBottom = screen.topInset + PaeoniaSpacing.compactButtonHeight
        let half = avatarSize / 2
        let width = screen.width
        // An avatar's edge never comes closer to the screen's sides than the cards do.
        let sideMargin = PaeoniaSpacing.screenHorizontalPadding
        avatarFade = half + sideMargin
        avatarBounds = CGRect(
            x: half + sideMargin,
            y: pillBottom + PaeoniaSpacing.space8 + half,
            width: max(width - avatarSize - 2 * sideMargin, 1),
            height: max(cardsTop - pillBottom - avatarSize - 2 * PaeoniaSpacing.space8 - PaeoniaSpacing.space32, 1)
        )
        if isNear {
            framedBox = CGRect(x: 0, y: (pillBottom + cardsTop) / 2 - 1, width: width, height: 2)
        } else {
            let margin = PaeoniaSpacing.space8 + 44 + half
            let top = pillBottom + margin
            let bottom = cardsTop - margin
            let side = half + sideMargin
            framedBox = CGRect(x: side, y: top, width: width - 2 * side, height: max(bottom - top, 1))
        }
    }

    /// 1 while an avatar centered at `point` is on the open map, down to 0 as it leaves.
    func avatarOpacity(at point: CGPoint) -> Double {
        let outside = max(
            avatarBounds.minX - point.x, point.x - avatarBounds.maxX,
            avatarBounds.minY - point.y, point.y - avatarBounds.maxY, 0
        )
        return max(0, 1 - outside / avatarFade)
    }
}

private extension CGPoint {
    /// Turned about the origin, clockwise on screen.
    func rotated(by angle: CGFloat) -> CGPoint {
        CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
    }
}
