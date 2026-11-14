import MapKit
import SwiftUI
import UIKit

/// A revealed round in the preview square: both pins and the line between them over a
/// still of the game's map. The pins and line are placed from the map rect, so they
/// show at once, and offline, while the map fades in when its still is ready.
struct GuessMySpotPreviewMap: View {
    let preview: GuessMySpotPreview
    /// The still and the round it shows, so a view that gets a new round never shows the old map.
    @State private var still: (preview: GuessMySpotPreview, image: UIImage)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The pins are drawn for a full-size map, and the hub tile shows this square at
    /// about 0.4 times, so they are scaled up to stay readable there.
    private static let pinScale: CGFloat = 1.4

    init(preview: GuessMySpotPreview) {
        self.preview = preview
        // Read at once, so an image renderer, which never runs tasks, draws a map it already has.
        _still = State(initialValue: GuessMySpotPreviewMaps.shared[preview].map { (preview, $0) })
    }

    var body: some View {
        let rect = GuessMySpotPreviewMaps.rect(for: preview)
        let side = GameChatPreview.side
        let guess = Self.point(preview.guess, in: rect, side: side)
        let spot = Self.point(preview.spot, in: rect, side: side)
        let styles = GameChatBoardThumbnail.styles(me: .one)
        ZStack(alignment: .topLeading) {
            Color.paeoniaBackgroundSecondary
            if let still, still.preview == preview {
                Image(uiImage: still.image)
                    .resizable()
                    .transition(.opacity)
            }
            line(from: guess, to: spot)
            pin(at: guess, style: preview.guessedByMe ? styles.one : styles.two)
            pin(at: spot, style: preview.guessedByMe ? styles.two : styles.one)
        }
        .frame(width: side, height: side)
        .clipped()
        .accessibilityHidden(true)
        .task(id: preview) {
            guard still?.preview != preview else { return }
            guard let image = await GuessMySpotPreviewMaps.shared.load(preview), !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { still = (preview, image) }
        }
    }

    @ViewBuilder
    private func line(from start: CGPoint, to end: CGPoint) -> some View {
        let path = Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        if preview.isFar {
            path.stroke(Color.paeoniaTextSecondary, style: StrokeStyle(lineWidth: 5, lineCap: .butt, dash: [8, 9]))
        } else {
            path.stroke(Color.paeoniaInkGold.opacity(0.3), style: StrokeStyle(lineWidth: 16, lineCap: .round))
            path.stroke(Color.paeoniaInkGold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }

    private func pin(at point: CGPoint, style: BoardPieceStyle) -> some View {
        GuessMySpotPin(style: style)
            .scaleEffect(Self.pinScale, anchor: .bottom)
            .position(x: point.x, y: point.y - GuessMySpotPin.height / 2)
    }

    /// Where `coordinate` lies in a `side` square showing `rect`. Measured eastward from
    /// the rect's west edge around the world, so a rect across the 180th meridian works.
    private static func point(_ coordinate: GuessMySpotCoordinate, in rect: MKMapRect, side: CGFloat) -> CGPoint {
        let world = MKMapSize.world.width
        let mapPoint = MKMapPoint(coordinate.location)
        var dx = (mapPoint.x - rect.minX).truncatingRemainder(dividingBy: world)
        if dx < 0 { dx += world }
        return CGPoint(x: dx / rect.width * side, y: (mapPoint.y - rect.minY) / rect.height * side)
    }
}

/// The map stills made so far this session, so a tile that scrolls back into view, the
/// chat thumbnail and the tile's palette share one snapshot.
final class GuessMySpotPreviewMaps {
    static let shared = GuessMySpotPreviewMaps()

    private var images: [GuessMySpotPreview: UIImage] = [:]
    private var loads: [GuessMySpotPreview: Task<UIImage?, Never>] = [:]
    private static let limit = 8

    subscript(preview: GuessMySpotPreview) -> UIImage? { images[preview] }

    /// The still for `preview`, made once. Nil when MapKit can't make it, such as offline,
    /// and the next call tries again.
    func load(_ preview: GuessMySpotPreview) async -> UIImage? {
        if let image = images[preview] { return image }
        if let load = loads[preview] { return await load.value }
        let load = Task { await Self.snapshot(Self.rect(for: preview), side: GameChatPreview.side) }
        loads[preview] = load
        let image = await load.value
        loads[preview] = nil
        if let image {
            if images.count >= Self.limit { images.removeAll() }
            images[preview] = image
        }
        return image
    }

    /// The round's framing as a square no bigger than the world, with its west edge
    /// inside the world and its top and bottom on the map, so MapKit shows that rect.
    /// The spots fill the middle half and sit 15 percent below the middle, so the
    /// scaled-up pins standing on them keep their heads inside the square.
    static func rect(for preview: GuessMySpotPreview) -> MKMapRect {
        let framed = GuessMySpotCamera.framing(preview.guess, preview.spot, padding: 1).rect ?? .world
        let world = MKMapSize.world
        let side = min(max(framed.width, framed.height), world.height)
        var x = (framed.midX - side / 2).truncatingRemainder(dividingBy: world.width)
        if x < 0 { x += world.width }
        let y = min(max(0, framed.midY - side * 0.65), world.height - side)
        return MKMapRect(x: x, y: y, width: side, height: side)
    }

    /// Runs off the main thread, as `CoupleMapSnapshot` does.
    @concurrent
    private static func snapshot(_ rect: MKMapRect, side: CGFloat) async -> UIImage? {
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = CGSize(width: side, height: side)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration
        return try? await MKMapSnapshotter(options: options).start().image
    }
}
