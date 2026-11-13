import SwiftUI

/// Where Home's map puts the two avatars, how big and how visible they are, and the map's
/// own fade-in, all read from the camera the map is drawing.
extension HomeMapLayout {
    /// Over the avatars, which may sit under it while the person looks around.
    func showBothButton(_ couple: HomeMapCouple, _ screen: HomeMapScreen) -> some View {
        HomeMapBand { bandHeight in
            HomeMapShowBothButton(
                explorer: explorer,
                onDetails: { isShowingMapDetails = true },
                mapBottom: metrics(couple, screen, bandHeight: bandHeight).framedBottom
            )
        }
    }

    /// Follow the camera's current projection instead of animating to its destination.
    /// Without the intro, before the map's first frame, use the same math that places the map.
    /// Offline, the map may never draw, so the avatars go to their places without it.
    func points(_ couple: HomeMapCouple?, _ metrics: HomeMapMetrics) -> HomeMapAvatarPoints {
        guard let couple else { return waitingPoints(metrics) }
        guard let mapProjection, mapTiles.tiles != .offline || mapProjection.introProgress > 0 else {
            if !reduceMotion, mapTiles.tiles != .offline { return waitingPoints(metrics) }
            let framing = framing(couple, metrics)
            let raw = HomeMapAvatarPoints(own: framing.own, partner: framing.partner)
            return fitted(separated(raw, isNear: couple.isNear), in: metrics)
        }
        let raw = HomeMapAvatarPoints(own: mapProjection.own, partner: mapProjection.partner)
        guard mapProjection.introProgress < 1 else {
            // While the person looks around, the avatars stay on the map, off its edges too.
            guard let start = explorer.start else {
                return fitted(separated(raw, isNear: couple.isNear), in: metrics)
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
        // The map carries the avatars to where they land, so only a start the camera could
        // not reach is left to make up.
        let end = landingPoints(couple, metrics)
        let points = raw.duringIntro(
            rawStart: projection.introStart,
            waiting: waitingPoints(metrics),
            rawEnd: end,
            end: end,
            progress: projection.introProgress
        )
        return fitted(points, in: metrics)
    }

    /// Where the map's intro takes the avatars from and to. Reduce Motion has no intro.
    func introSpots(_ couple: HomeMapCouple, _ metrics: HomeMapMetrics) -> HomeMapLibreView.IntroSpots? {
        guard !reduceMotion else { return nil }
        return HomeMapLibreView.IntroSpots(waiting: waitingPoints(metrics), landing: landingPoints(couple, metrics))
    }

    /// Where the avatars sit once the map has framed the couple.
    func landingPoints(_ couple: HomeMapCouple, _ metrics: HomeMapMetrics) -> HomeMapAvatarPoints {
        let framing = framing(couple, metrics)
        let places = HomeMapAvatarPoints(own: framing.own, partner: framing.partner)
        return fitted(separated(places, isNear: couple.isNear), in: metrics)
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
            screen: metrics.screen, bandHeight: metrics.bandHeight, avatarSize: avatarSize, isNear: true,
            markerMeasurements: markerMeasurements
        )
        let center = CGPoint(x: near.framedBox.midX, y: near.framedBox.midY)
        let together = separated(HomeMapAvatarPoints(own: center, partner: center), isNear: true)
        return fitted(together, in: near)
    }

    /// Clamping to the map can bring markers together. Keep their complete content apart.
    func fitted(_ points: HomeMapAvatarPoints, in metrics: HomeMapMetrics) -> HomeMapAvatarPoints {
        let kept = points.kept(inside: metrics.avatarBounds)
        let horizontal = 2 * markerMeasurements.halfWidth + PaeoniaSpacing.space8
        let vertical = markerMeasurements.above + markerMeasurements.below + PaeoniaSpacing.space8
        guard abs(kept.own.x - kept.partner.x) < horizontal,
              abs(kept.own.y - kept.partner.y) < vertical,
              metrics.avatarBounds.width >= horizontal else { return kept }
        let half = horizontal / 2
        let middle = min(
            max((kept.own.x + kept.partner.x) / 2, metrics.avatarBounds.minX + half),
            metrics.avatarBounds.maxX - half
        )
        let direction: CGFloat = kept.own.x <= kept.partner.x ? 1 : -1
        return HomeMapAvatarPoints(
            own: CGPoint(x: middle - direction * half, y: kept.own.y),
            partner: CGPoint(x: middle + direction * half, y: kept.partner.y)
        )
    }

    /// The map fades in over the first half of the intro.
    var mapOpacity: Double {
        guard !reduceMotion else { return 1 }
        guard let mapProjection else { return 0 }
        return min(1, mapProjection.introProgress * 2)
    }

    func separated(_ points: HomeMapAvatarPoints, isNear: Bool) -> HomeMapAvatarPoints {
        // Wide enough that the two note bubbles never touch.
        let decorations = avatarStyling?.decorations ?? CoupleAvatarDecorations()
        let decoratedWidth = avatarSize * (1 + decorations.own.outset + decorations.partner.outset)
        let minimum = max(
            StoryNoteBubble.maxWidth + PaeoniaSpacing.space8,
            decoratedWidth + PaeoniaSpacing.space16,
            2 * markerMeasurements.halfWidth + PaeoniaSpacing.space8
        )
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
