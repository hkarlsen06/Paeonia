import PencilKit
import UIKit

/// The partner's strokes while they are still drawing them. Each point is shown
/// `delay` after its stroke started arriving, at the pace it was drawn, so the
/// line grows smoothly instead of jumping each time a batch of points lands.
/// A stroke is rebuilt from the same recipe the sender draws with, so it looks
/// like the finished stroke that replaces it.
nonisolated struct WidgetLivePlayback {
    static let delay: TimeInterval = 0.1
    /// A finished stroke that never arrived as a real stroke is dropped after this.
    static let endedLifetime: TimeInterval = 3
    /// Limits on what a partner's message may describe. A finger stays far
    /// inside them. Past them, one small message could make this phone build
    /// millions of points.
    static let maxSide: CGFloat = 4_096
    static let maxSamplesPerStroke = 20_000

    struct Stroke {
        var ink: InkStroke
        /// The side of the sender's square canvas.
        var side: CGFloat
        /// Local time that matches the stroke's time offset 0.
        var origin: TimeInterval
        var endedAt: TimeInterval?
    }

    private(set) var strokes: [String: Stroke] = [:]
    private var order: [String] = []

    var isEmpty: Bool { strokes.isEmpty }

    mutating func receive(_ message: WidgetLiveMessage, now: TimeInterval) {
        guard let id = message.id, let rawPoints = message.points else {
            return
        }
        if let stroke = strokes[id] {
            let room = Self.maxSamplesPerStroke - stroke.ink.samples.count
            strokes[id]?.ink.append(Array(Self.samples(rawPoints, side: stroke.side).prefix(max(0, room))))
        } else {
            guard let side = message.side.map({ CGFloat($0) }), (1...Self.maxSide).contains(side) else {
                return
            }
            let samples = Self.samples(rawPoints, side: side).prefix(Self.maxSamplesPerStroke)
            guard let first = samples.first, let style = Self.style(of: message), let seed = message.seed else {
                return
            }
            var ink = InkStroke(style: style, first: first, seed: seed)
            ink.append(Array(samples.dropFirst()))
            strokes[id] = Stroke(ink: ink, side: side, origin: now + Self.delay - first.timeOffset)
            order.append(id)
        }
        // `SnappedShape` refuses an undrawable shape when the message decodes.
        if let snap = message.snap, snap.time.isFinite {
            strokes[id]?.ink.snap(to: snap.shape, at: snap.time)
        } else {
            strokes[id]?.ink.unsnap()
        }
    }

    /// The points of a message that lie on or near the sender's canvas of
    /// `side` points. Exquisite Corpse draws a little above the canvas, so
    /// points up to one side outside it count.
    private static func samples(_ rawPoints: [[Double]], side: CGFloat) -> [InkSample] {
        let reach = -side...(2 * side)
        return rawPoints.compactMap(InkSample.init(liveValues:)).filter { sample in
            reach.contains(sample.location.x) && reach.contains(sample.location.y)
        }
    }

    /// The stroke's look, or nil when the message does not describe one.
    private static func style(of message: WidgetLiveMessage) -> InkStyle? {
        guard let kind = message.ink.flatMap(InkKind.init(rawValue:)),
              let color = message.color.flatMap(UIColor.init(liveComponents:)),
              let width = message.width.map({ CGFloat($0) }),
              kind.validWidthRange.contains(width),
              let lineStyle = message.lineStyle.flatMap(InkLineStyle.init(rawValue:))
        else {
            return nil
        }
        return InkStyle(kind: kind, color: color, width: width, lineStyle: lineStyle)
    }

    mutating func end(_ id: String, now: TimeInterval) {
        strokes[id]?.endedAt = now
    }

    mutating func remove(_ ids: [String]) {
        for id in ids {
            strokes[id] = nil
        }
        order.removeAll { strokes[$0] == nil }
    }

    mutating func removeAll() {
        strokes = [:]
        order = []
    }

    /// Drops finished strokes whose real stroke never came.
    mutating func prune(now: TimeInterval) {
        let expired = strokes.filter { _, stroke in
            stroke.endedAt.map { now - $0 > Self.endedLifetime } ?? false
        }
        remove(Array(expired.keys))
    }

    /// The strokes as far as they are shown at `now`, on a canvas of `side`
    /// points. They are scaled the way `PKDrawing.scaled` scales the finished
    /// strokes, so the finished stroke lands exactly on its preview.
    func pencilKitStrokes(at now: TimeInterval, side: CGFloat) -> [PKStroke] {
        order.compactMap { id in
            guard let stroke = strokes[id], let shown = stroke.ink.prefix(through: now - stroke.origin) else {
                return nil
            }
            let scale = side / stroke.side
            return shown.pencilKitStroke(transform: CGAffineTransform(scaleX: scale, y: scale))
        }
    }
}

extension UIColor {
    /// RGBA in `0...1`, as sent in `WidgetLiveMessage.color`. The canvas is
    /// always light, so dynamic colors resolve in light mode.
    nonisolated var liveComponents: [Double] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // Extended-range colors can read past 1.
        return [red, green, blue, alpha].map { min(max(Double($0), 0), 1) }
    }

    nonisolated convenience init?(liveComponents components: [Double]) {
        guard components.count == 4, components.allSatisfy({ (0...1).contains($0) }) else {
            return nil
        }
        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}
