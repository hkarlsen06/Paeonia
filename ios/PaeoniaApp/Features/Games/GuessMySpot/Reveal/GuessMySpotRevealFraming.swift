import MapKit
import SwiftUI

/// Where the reveal's camera looks at each stage, worked out from the two spots, the
/// map's size, and the room the bars and the card leave. `GuessMySpotRevealView` makes
/// one from its current state whenever it needs a camera position.
struct GuessMySpotRevealFraming {
    let guess: GuessMySpotCoordinate?
    let spot: GuessMySpotCoordinate?
    let isSender: Bool
    let mapSize: CGSize
    /// How tall the map draws, past its frame at the bottom.
    let drawnHeight: CGFloat
    /// The safe area over the map, under the top bar, which MapKit's own view reaches up into.
    let topInset: CGFloat
    let cardHeight: CGFloat
    /// A wide screen frames the map to the right of the card's column.
    let isWide: Bool

    /// Where the reveal starts and where it lands.
    var ends: (from: GuessMySpotCoordinate, to: GuessMySpotCoordinate)? {
        guard let guess, let spot else { return nil }
        return isSender ? (spot, guess) : (guess, spot)
    }

    /// The part of the map a camera move frames: under the top room and a pin's head,
    /// and clear of the card. The card's room is kept from the start, so nothing
    /// slides when it rises.
    func framed(
        _ position: MapCameraPosition,
        keepsCardRoom: Bool = true,
        maxScale: Double = .infinity
    ) -> MapCameraPosition {
        let insets = EdgeInsets(
            top: GuessMySpotRevealView.topRoom + GuessMySpotPin.headSize,
            leading: isWide ? GuessMySpotRevealView.cardColumn : 0,
            bottom: isWide || !keepsCardRoom ? PaeoniaSpacing.space8 : cardHeight + PaeoniaSpacing.space8,
            trailing: 0
        )
        return GuessMySpotCamera.filling(position, size: mapSize, insets: insets, maxScale: maxScale)
    }

    /// The framed camera of each stage.
    func target(for stage: GuessMySpotRevealTimeline.Camera) -> MapCameraPosition? {
        guard let ends else { return nil }
        let target: MapCameraPosition = switch stage {
        case .start: GuessMySpotCamera.around(ends.from, meters: 60_000)
        case .overview: GuessMySpotCamera.framing(ends.from, ends.to)
        case .landed: GuessMySpotCamera.landing(on: ends.to, guess: ends.from)
        }
        guard stage == .overview else { return framed(target) }
        // A far guess asks for more of the world than MapKit's flat map shows. Fly to
        // the view it really shows when that fits both spots, and to the globe when not.
        guard let asked = framed(target).rect else { return framed(target) }
        let widest = shown(asked)
        guard widest.width < asked.width * 0.99 else { return .rect(widest) }
        // The card rises only after the flight down, so a guess too far to fit over
        // its room may use it, and both pins show.
        if !isWide, let open = framed(target, keepsCardRoom: false).rect, shown(open).width >= open.width * 0.99 {
            return .rect(shown(open))
        }
        // Too far apart for any flat view: the globe. It needs every point it can get,
        // so a pin may stand anywhere it shows whole. The distance capsule comes later.
        return globe(
            top: GuessMySpotPin.height + PaeoniaSpacing.space8, bottom: mapSize.height - PaeoniaSpacing.space8
        )?.position
    }

    /// Both pins once the card is up, in the room between the camera buttons and
    /// the card, as tall as it is now. The flight's overview may use the card's room,
    /// because the card rises only after it, so it would hide a pin here. A guess too
    /// far to fit shows on the globe in that room. `fits` is false when the globe
    /// can't show both pins in it either.
    func settledOverview() -> (position: MapCameraPosition, fits: Bool)? {
        guard let guess, let spot else { return nil }
        let both = GuessMySpotCamera.framing(guess, spot, padding: 0.2)
        let insets = EdgeInsets(
            top: GuessMySpotRevealView.buttonsRoom + GuessMySpotPin.height,
            leading: isWide ? GuessMySpotRevealView.cardColumn : PaeoniaSpacing.space16,
            bottom: isWide ? PaeoniaSpacing.space8 : cardHeight + PaeoniaSpacing.space8,
            trailing: PaeoniaSpacing.space16
        )
        guard let asked = GuessMySpotCamera.filling(both, size: mapSize, insets: insets).rect else { return nil }
        let widest = shown(asked)
        guard widest.width < asked.width * 0.99 else { return (.rect(widest), true) }
        return globe(top: insets.top, bottom: mapSize.height - insets.bottom)
    }

    /// Both ends on the globe, their pins between `top` and `bottom` of the map. See `GuessMySpotGlobe`.
    private func globe(top: CGFloat, bottom: CGFloat) -> (position: MapCameraPosition, fits: Bool)? {
        guard let ends else { return nil }
        let below = max(0, drawnHeight - mapSize.height)
        let height = mapSize.height + topInset + below
        // MapKit's camera looks at the middle of its whole view, which reaches under the bars.
        let middle = height / 2 - topInset
        let room = GuessMySpotGlobe.Room(
            up: middle - top, down: bottom - middle, side: mapSize.width / 2 - PaeoniaSpacing.space24
        )
        let framing = GuessMySpotGlobe.framing(ends.from, ends.to, height: height, room: room)
        return (.camera(framing.camera), framing.fits)
    }

    private func shown(_ rect: MKMapRect) -> MKMapRect {
        GuessMySpotFlight.shown(rect, size: mapSize, above: topInset, below: max(0, drawnHeight - mapSize.height))
    }

    /// Where a flight from `start` to `end` is at each eased fraction: across the
    /// flat map, or as a camera when either end is on the globe.
    func path(
        from start: MapCameraPosition,
        to end: MapCameraPosition
    ) -> ((Double) -> MapCameraPosition)? {
        if let start = start.rect, let end = end.rect {
            return { .rect(GuessMySpotFlight.view(from: start, to: end, at: $0)) }
        }
        guard let start = mapCamera(start), let end = mapCamera(end) else { return nil }
        return { .camera(GuessMySpotGlobe.view(from: start, to: end, at: $0)) }
    }

    /// The views to load ahead of a flight. See `GuessMySpotFlight.stops`.
    func stops(from start: MapCameraPosition, to end: MapCameraPosition) -> [MapCameraPosition] {
        if let start = start.rect, let end = end.rect {
            return GuessMySpotFlight.stops(from: start, to: end).map { .rect($0) }
        }
        guard let start = mapCamera(start), let end = mapCamera(end) else { return [] }
        return GuessMySpotGlobe.stops(from: start, to: end).map { .camera($0) }
    }

    /// `position` as a camera, a part of the flat map as the camera that shows it.
    private func mapCamera(_ position: MapCameraPosition) -> MapCamera? {
        position.camera ?? position.rect.map {
            GuessMySpotGlobe.camera(
                showing: $0, size: mapSize, above: topInset, below: max(0, drawnHeight - mapSize.height)
            )
        }
    }

    /// `view` grown down to where the map draws, when it is a part of the flat map.
    func drawn(_ view: MapCameraPosition) -> MapCameraPosition {
        view.rect.map { .rect(drawn($0)) } ?? view
    }

    /// `rect`, a camera's view of the map's frame, grown down to where the map draws.
    private func drawn(_ rect: MKMapRect) -> MKMapRect {
        let extra = max(0, drawnHeight - mapSize.height) * rect.width / max(1, mapSize.width)
        return MKMapRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + extra)
    }
}
