import SwiftUI

/// Where Home's map puts the two avatars, how big and how visible they are, and the map's
/// own fade-in, all read from the camera the map is drawing.
extension HomeMapLayout {
    /// Over the avatars, which may sit under it while the person looks around.
    func showBothButton(_ couple: HomeMapCouple, _ screen: HomeMapScreen) -> some View {
        GeometryReader { band in
            HomeMapShowBothButton(
                explorer: explorer,
                mapBottom: metrics(couple, screen, bandHeight: band.size.height).framedBottom
            )
        }
    }

    /// Follow the camera's current projection instead of animating to its destination.
    /// Without the intro, before the map's first frame, use the same math that places the map.
    func points(_ couple: HomeMapCouple?, _ metrics: HomeMapMetrics) -> HomeMapAvatarPoints {
        guard let couple else { return waitingPoints(metrics) }
        guard let mapProjection else {
            if !reduceMotion { return waitingPoints(metrics) }
            let framing = framing(couple, metrics)
            let raw = HomeMapAvatarPoints(own: framing.own, partner: framing.partner)
            return separated(raw, isNear: couple.isNear).kept(inside: metrics.avatarBounds)
        }
        let raw = HomeMapAvatarPoints(own: mapProjection.own, partner: mapProjection.partner)
        guard mapProjection.introProgress < 1 else {
            // While the person looks around, the avatars stay on the map, off its edges too.
            guard let start = explorer.start else {
                return separated(raw, isNear: couple.isNear).kept(inside: metrics.avatarBounds)
            }
            return raw.pinned(
                zoomChange: pow(2, mapProjection.zoom - start.zoom),
                turn: (start.direction - mapProjection.direction) * .pi / 180
            ) { separated($0, isNear: couple.isNear) }
        }
        return introPoints(raw, couple, metrics, mapProjection)
    }

    func introPoints(
        _ raw: HomeMapAvatarPoints,
        _ couple: HomeMapCouple,
        _ metrics: HomeMapMetrics,
        _ projection: HomeMapProjection
    ) -> HomeMapAvatarPoints {
        let framing = framing(couple, metrics)
        let rawEnd = HomeMapAvatarPoints(own: framing.own, partner: framing.partner)
        return raw.duringIntro(
            rawStart: projection.introStart,
            waiting: waitingPoints(metrics),
            rawEnd: rawEnd,
            end: separated(rawEnd, isNear: couple.isNear).kept(inside: metrics.avatarBounds),
            progress: projection.introProgress
        )
        .kept(inside: metrics.avatarBounds)
    }

    /// Smaller as the person zooms out from where they started looking around, so far
    /// out the avatars are too small to see. Never bigger than their usual size.
    var avatarScale: CGFloat {
        guard let start = explorer.start, let mapProjection else { return 1 }
        return min(1, pow(2, mapProjection.zoom - start.zoom))
    }

    /// Side by side in the middle of the open map, where the avatars wait while it loads.
    func waitingPoints(_ metrics: HomeMapMetrics) -> HomeMapAvatarPoints {
        let near = HomeMapMetrics(
            screen: metrics.screen, bandHeight: metrics.bandHeight, avatarSize: avatarSize, isNear: true
        )
        let center = CGPoint(x: near.framedBox.midX, y: near.framedBox.midY)
        let together = separated(HomeMapAvatarPoints(own: center, partner: center), isNear: true)
        return together.kept(inside: near.avatarBounds)
    }

    /// The map fades in over the first half of the intro.
    var mapOpacity: Double {
        guard !reduceMotion else { return 1 }
        guard let mapProjection else { return 0 }
        return min(1, mapProjection.introProgress * 2)
    }

    func separated(_ points: HomeMapAvatarPoints, isNear: Bool) -> HomeMapAvatarPoints {
        // Wide enough that the two note bubbles never touch.
        let minimum = max(StoryNoteBubble.maxWidth + PaeoniaSpacing.space8, avatarSize + PaeoniaSpacing.space16)
        guard isNear else {
            // Apart: pushed away from each other along the line between the two places,
            // so north stays north, with room for a note bubble when one sits above the other.
            let apart = max(minimum, avatarSize + 56)
            let (own, partner) = CoupleMapFraming.separated(points.own, points.partner, minimumDistance: apart)
            return HomeMapAvatarPoints(own: own, partner: partner)
        }
        // Together: side by side around the midpoint, you on the left, with room for the heart between.
        let together = max(minimum, avatarSize + Self.heartWidth - 2 * Self.heartOverlap)
        let mid = CGPoint(x: (points.own.x + points.partner.x) / 2, y: (points.own.y + points.partner.y) / 2)
        return HomeMapAvatarPoints(
            own: CGPoint(x: mid.x - together / 2, y: mid.y),
            partner: CGPoint(x: mid.x + together / 2, y: mid.y)
        )
    }
}
