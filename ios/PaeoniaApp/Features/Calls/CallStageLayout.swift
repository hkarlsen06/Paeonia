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

/// How the partner's shared screen shows while it is the big video. Fitted, it keeps its shape in the
/// room the controls and the previews leave, so nothing covers it. Full, it fills the safe area, and
/// the previews fade out.
nonisolated enum CallSharedScreenMode: Equatable, Sendable {
    case fitted
    case full
}

/// Where each video of the call screen shows. A camera fills the whole stage, or shows whole when its
/// picture is held the other way from the screen. The previews stack from the person's corner toward
/// the middle, inside the room the controls leave. A fitted shared
/// screen takes what is left of that room beside the previews, or above or below them, whichever
/// lets it show larger. A phone on its side lays them out as the person sees the screen, then turns
/// them onto it.
nonisolated struct CallStageLayout {
    struct Tile: Equatable {
        /// The middle of the tile on screen.
        var center: CGPoint
        /// The tile's size before it turns, upright to the person.
        var size: CGSize
    }

    /// The previews stack from the corner along its side, or line up from it along its top or bottom
    /// edge.
    private enum Arrangement {
        case column
        case row
    }

    /// How the previews sit, and the box a fitted shared screen gets beside them.
    private struct Plan {
        var arrangement: Arrangement
        var scale: CGFloat
        var screenBox: CGRect
    }

    static let previewGap = PaeoniaSpacing.space8
    /// Between a fitted shared screen and the previews.
    private static let screenGap = PaeoniaSpacing.space12
    /// Previews never shrink below this, to fit beside each other or to give a shared screen room.
    private static let smallestScale: CGFloat = 0.6

    let tiles: [CallVideoSource: Tile]

    /// `frame` is where the videos show on screen, `margins` the room around the previews and a fitted
    /// shared screen inside it, and `safeArea` the screen's own edges inside it, all on screen.
    init(
        stage: CallStage, session: CallSession, in frame: CGRect, margins: EdgeInsets, safeArea: EdgeInsets,
        corner: CallPreviewCorner, turn: CallTurn, sharedScreen: CallSharedScreenMode
    ) {
        let seen = turn.asSeen(frame.size)
        let room = Self.inset(seen, by: turn.asSeen(margins))
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        func onScreen(_ point: CGPoint) -> CGPoint {
            let turned = turn.onScreen(CGPoint(x: point.x - seen.width / 2, y: point.y - seen.height / 2))
            return CGPoint(x: middle.x + turned.x, y: middle.y + turned.y)
        }

        var tiles: [CallVideoSource: Tile] = [:]
        let sizes = stage.previews.map { $0.previewSize(in: session, sideways: turn.isSideways) }
        var plan = Plan(arrangement: .column, scale: Self.columnScale(sizes, height: room.height), screenBox: room)
        if stage.main == .partnerScreen {
            // A shared screen is read, not looked at, so it shows whole. Cropped like a camera, its
            // edges went under the status bar and out of sight.
            let ratio = session.partnerScreenAspectRatio ?? CallVideoSource.phoneScreenAspectRatio
            let plans = [Arrangement.column, .row].compactMap {
                Self.plan($0, beside: sizes, in: room, corner: corner, screen: ratio)
            }
            // On a tie the column wins, the way the previews sit over a camera.
            plan = plans.max { Self.area(ratio, in: $0.screenBox) < Self.area(ratio, in: $1.screenBox) } ?? plan
            let box = sharedScreen == .full ? Self.inset(seen, by: turn.asSeen(safeArea)) : plan.screenBox
            let size = Self.fit(ratio, in: box.size)
            // In the box's own middle, a screen narrower than a wide room sat off to one side, such as
            // on an iPad, so it keeps as near the room's middle as the previews let it.
            let around = sharedScreen == .full ? box : room
            let center = Self.center(of: size, in: box, nearest: CGPoint(x: around.midX, y: around.midY))
            tiles[.partnerScreen] = Tile(center: onScreen(center), size: size)
        } else if let main = stage.main {
            let ratio = main == .local ? session.localVideoAspectRatio : session.partnerVideoAspectRatio
            tiles[main] = Tile(center: middle, size: Self.camera(ratio, on: seen))
        }
        let scaled = sizes.map { CGSize(width: $0.width * plan.scale, height: $0.height * plan.scale) }
        for (source, rect) in zip(stage.previews, Self.place(scaled, as: plan.arrangement, in: room, corner: corner)) {
            tiles[source] = Tile(center: onScreen(CGPoint(x: rect.midX, y: rect.midY)), size: rect.size)
        }
        self.tiles = tiles
    }

    /// `size` less `insets`, from its top left corner.
    private static func inset(_ size: CGSize, by insets: EdgeInsets) -> CGRect {
        CGRect(
            x: insets.leading, y: insets.top,
            width: max(0, size.width - insets.leading - insets.trailing),
            height: max(0, size.height - insets.top - insets.bottom))
    }

    /// The scale that fits a column of previews of `sizes` into `height`, never above 1.
    private static func columnScale(_ sizes: [CGSize], height: CGFloat) -> CGFloat {
        let total = sizes.reduce(0) { $0 + $1.height } + previewGap * CGFloat(max(0, sizes.count - 1))
        return total > 0 ? max(smallestScale, min(1, height / total)) : 1
    }

    /// Previews of `sizes` in `room` arranged as `arrangement`, beside a fitted shared screen of shape
    /// `ratio`. They never grow past the scale a column over a camera takes, and shrink below it only as
    /// far as that lets the screen grow. Nil when a row of them can't fit across the room.
    private static func plan(
        _ arrangement: Arrangement, beside sizes: [CGSize], in room: CGRect, corner: CallPreviewCorner,
        screen ratio: CGFloat
    ) -> Plan? {
        let largest = columnScale(sizes, height: room.height)
        guard !sizes.isEmpty else { return Plan(arrangement: arrangement, scale: largest, screenBox: room) }
        switch arrangement {
        case .column:
            let across = sizes.map(\.width).max() ?? 0
            // At this scale and below, the column leaves the screen room for the room's whole height.
            let enough = (room.width - screenGap - room.height * ratio) / across
            let scale = min(largest, max(smallestScale, enough))
            let taken = across * scale + screenGap
            return Plan(arrangement: arrangement, scale: scale, screenBox: CGRect(
                x: corner.horizontal == .leading ? room.minX + taken : room.minX, y: room.minY,
                width: max(0, room.width - taken), height: room.height))
        case .row:
            let along = sizes.reduce(0) { $0 + $1.width }
            let widest = min(largest, (room.width - previewGap * CGFloat(sizes.count - 1)) / along)
            guard widest >= smallestScale else { return nil }
            let across = sizes.map(\.height).max() ?? 0
            // At this scale and below, the row leaves the screen room for the room's whole width.
            let enough = (room.height - screenGap - room.width / ratio) / across
            let scale = min(widest, max(smallestScale, enough))
            let taken = across * scale + screenGap
            return Plan(arrangement: arrangement, scale: scale, screenBox: CGRect(
                x: room.minX, y: corner.vertical == .top ? room.minY + taken : room.minY,
                width: room.width, height: max(0, room.height - taken)))
        }
    }

    /// Where previews of `sizes` sit in `room`, starting in `corner`, one after another toward the
    /// middle.
    private static func place(
        _ sizes: [CGSize], as arrangement: Arrangement, in room: CGRect, corner: CallPreviewCorner
    ) -> [CGRect] {
        let top = corner.vertical == .top
        let leading = corner.horizontal == .leading
        var edge = switch arrangement {
        case .column: top ? room.minY : room.maxY
        case .row: leading ? room.minX : room.maxX
        }
        return sizes.map { size in
            let rect: CGRect
            switch arrangement {
            case .column:
                rect = CGRect(
                    x: leading ? room.minX : room.maxX - size.width, y: top ? edge : edge - size.height,
                    width: size.width, height: size.height)
                edge += (top ? 1 : -1) * (size.height + previewGap)
            case .row:
                rect = CGRect(
                    x: leading ? edge : edge - size.width, y: top ? room.minY : room.maxY - size.height,
                    width: size.width, height: size.height)
                edge += (leading ? 1 : -1) * (size.width + previewGap)
            }
            return rect
        }
    }

    /// The big camera's size on a stage of size `stage`. It fills the stage, cropped at the edges, while
    /// its picture is held the same way as the screen. Held the other way, such as an upright phone's
    /// picture on an iPad on its side, filling showed only a band across the face, so it shows whole.
    private static func camera(_ aspectRatio: CGFloat?, on stage: CGSize) -> CGSize {
        guard let aspectRatio, (aspectRatio > 1) != (stage.width > stage.height) else { return stage }
        return fit(aspectRatio, in: stage)
    }

    /// The middle nearest `point` for a tile of `size` that stays inside `box`.
    private static func center(of size: CGSize, in box: CGRect, nearest point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, box.minX + size.width / 2), box.maxX - size.width / 2),
            y: min(max(point.y, box.minY + size.height / 2), box.maxY - size.height / 2))
    }

    private static func area(_ aspectRatio: CGFloat, in box: CGRect) -> CGFloat {
        let size = fit(aspectRatio, in: box.size)
        return size.width * size.height
    }

    /// The largest size of the shape `aspectRatio` (width over height) that fits in `box`.
    private static func fit(_ aspectRatio: CGFloat, in box: CGSize) -> CGSize {
        guard aspectRatio > 0, box.width > 0, box.height > 0 else { return box }
        return box.width / box.height > aspectRatio
            ? CGSize(width: box.height * aspectRatio, height: box.height)
            : CGSize(width: box.width, height: box.width / aspectRatio)
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
