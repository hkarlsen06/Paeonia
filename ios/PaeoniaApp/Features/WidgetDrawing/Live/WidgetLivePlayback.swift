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
        let samples = rawPoints.compactMap(InkSample.init(liveValues:))
        if strokes[id] != nil {
            strokes[id]?.ink.append(samples)
            return
        }
        guard let first = samples.first,
              let style = Self.style(of: message),
              let seed = message.seed,
              let side = message.side, side.isFinite, side > 0
        else {
            return
        }
        var ink = InkStroke(style: style, first: first, seed: seed)
        ink.append(Array(samples.dropFirst()))
        strokes[id] = Stroke(ink: ink, side: side, origin: now + Self.delay - first.timeOffset)
        order.append(id)
    }

    /// The stroke's look, or nil when the message does not describe one.
    private static func style(of message: WidgetLiveMessage) -> InkStyle? {
        guard let kind = message.ink.flatMap(InkKind.init(rawValue:)),
              let color = message.color.flatMap(UIColor.init(liveComponents:)),
              let width = message.width.map({ CGFloat($0) }),
              kind.validWidthRange.contains(width)
        else {
            return nil
        }
        return InkStyle(kind: kind, color: color, width: width)
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
