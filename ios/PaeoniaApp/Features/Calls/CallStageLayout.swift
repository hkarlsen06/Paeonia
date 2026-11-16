import SwiftUI

/// The corner of the call screen the previews sit in, as the person sees it. Held on its side, the
/// phone shows them in the corner that is top right to the person, wherever that is on the screen.
nonisolated struct CallPreviewCorner: Equatable, Sendable {
    var vertical: VerticalEdge
    var horizontal: HorizontalEdge

    /// Top right, under the chevron's row.
    static let initial = CallPreviewCorner(vertical: .top, horizontal: .trailing)

    /// The corner that `point`, measured from the middle of what the person sees, is nearest.
    init(nearest point: CGPoint) {
        self.init(vertical: point.y < 0 ? .top : .bottom, horizontal: point.x < 0 ? .leading : .trailing)
    }

    init(vertical: VerticalEdge, horizontal: HorizontalEdge) {
        self.vertical = vertical
        self.horizontal = horizontal
    }
}

/// Where each video of the call screen shows: the big one over the whole stage, and the previews
/// stacked from the person's corner toward the middle, inside the room the controls leave. A phone on
/// its side lays them out as the person sees the screen, then turns them onto it.
nonisolated struct CallStageLayout {
    struct Tile: Equatable {
        /// The middle of the tile on screen.
        var center: CGPoint
        /// The tile's size before it turns, upright to the person.
        var size: CGSize
    }

    static let previewGap = PaeoniaSpacing.space8
    /// Previews never shrink below this to fit beside each other.
    private static let smallestScale: CGFloat = 0.6

    let tiles: [CallVideoSource: Tile]

    /// `frame` is where the videos show on screen, and `margins` the room around the previews inside
    /// it, on screen.
    init(
        stage: CallStage, session: CallSession, in frame: CGRect, margins: EdgeInsets, corner: CallPreviewCorner,
        turn: CallTurn
    ) {
        let seen = turn.asSeen(frame.size)
        let room = turn.asSeen(margins)
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        func onScreen(_ point: CGPoint) -> CGPoint {
            let turned = turn.onScreen(CGPoint(x: point.x - seen.width / 2, y: point.y - seen.height / 2))
            return CGPoint(x: middle.x + turned.x, y: middle.y + turned.y)
        }

        var tiles: [CallVideoSource: Tile] = [:]
        if let main = stage.main {
            tiles[main] = Tile(center: middle, size: seen)
        }
        let sizes = stage.previews.map { $0.previewSize(in: session, sideways: turn.isSideways) }
        let total = sizes.reduce(0) { $0 + $1.height } + Self.previewGap * CGFloat(max(0, sizes.count - 1))
        let height = max(0, seen.height - room.top - room.bottom)
        let scale = total > 0 ? max(Self.smallestScale, min(1, height / total)) : 1
        var edge = corner.vertical == .top ? room.top : seen.height - room.bottom
        for (source, size) in zip(stage.previews, sizes) {
            let scaled = CGSize(width: size.width * scale, height: size.height * scale)
            let x = corner.horizontal == .leading
                ? room.leading + scaled.width / 2 : seen.width - room.trailing - scaled.width / 2
            let y = corner.vertical == .top ? edge + scaled.height / 2 : edge - scaled.height / 2
            edge += (corner.vertical == .top ? 1 : -1) * (scaled.height + Self.previewGap)
            tiles[source] = Tile(center: onScreen(CGPoint(x: x, y: y)), size: scaled)
        }
        self.tiles = tiles
    }

    /// The corner a drag that ends at `point` on screen heads for.
    static func corner(nearest point: CGPoint, in frame: CGRect, turn: CallTurn) -> CallPreviewCorner {
        CallPreviewCorner(nearest: turn.asSeen(CGPoint(x: point.x - frame.midX, y: point.y - frame.midY)))
    }
}

/// Puts a tile at its place on the stage, turned and rounded. Every step of a move lays the tile out
/// again, because the video inside is a UIKit view, which would jump to the end of a move that SwiftUI
/// only animates.
struct CallTilePlacement: ViewModifier, Animatable {
    var center: CGPoint
    var size: CGSize
    var degrees: Double
    var cornerRadius: CGFloat
    /// A thin light edge and a shadow, so a preview stands out from the video under it.
    var isOutlined: Bool

    var animatableData: AnimatablePair<
        AnimatablePair<CGPoint.AnimatableData, CGSize.AnimatableData>, AnimatablePair<Double, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(center.animatableData, size.animatableData), AnimatablePair(degrees, cornerRadius))
        }
        set {
            center.animatableData = newValue.first.first
            size.animatableData = newValue.first.second
            degrees = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content
            .frame(width: max(0, size.width), height: max(0, size.height))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(isOutlined ? 0.25 : 0))
            }
            .rotationEffect(.degrees(degrees))
            .shadow(color: .black.opacity(isOutlined ? 0.35 : 0), radius: 12, y: 4)
            .position(center)
    }
}
