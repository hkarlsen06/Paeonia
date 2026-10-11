import PencilKit
import UIKit

/// The partner's strokes while they are still drawing them. Each point is shown
/// `delay` after its stroke started arriving, at the pace it was drawn, so the
/// line grows smoothly instead of jumping each time a batch of points lands.
nonisolated struct WidgetLivePlayback {
    static let delay: TimeInterval = 0.1
    /// A finished stroke that never arrived as a real stroke is dropped after this.
    static let endedLifetime: TimeInterval = 3

    struct Point: Equatable {
        var location: CGPoint
        var timeOffset: TimeInterval
        var azimuth: CGFloat

        /// `[x, y, timeOffset, azimuth]`.
        init?(_ values: [Double]) {
            guard values.count == 4, values.allSatisfy(\.isFinite) else {
                return nil
            }
            location = CGPoint(x: values[0], y: values[1])
            timeOffset = values[2]
            azimuth = values[3]
        }
    }

    struct Stroke {
        var ink: PKInk
        var style: WidgetLiveInkCalibration.Style
        var side: CGFloat
        var points: [Point]
        /// Local time that matches the stroke's time offset 0.
        var origin: TimeInterval
        var endedAt: TimeInterval?
        let creationDate: Date
    }

    private(set) var strokes: [String: Stroke] = [:]
    private var order: [String] = []

    var isEmpty: Bool { strokes.isEmpty }

    mutating func receive(_ message: WidgetLiveMessage, now: TimeInterval) {
        guard let id = message.id, let rawPoints = message.points else {
            return
        }
        let points = rawPoints.compactMap(Point.init)
        if strokes[id] != nil {
            strokes[id]?.points.append(contentsOf: points)
            return
        }
        guard let first = points.first,
              let side = message.side, side > 0,
              let style = message.pointStyle, style.size.isFinite, style.size > 0,
              let inkName = message.ink,
              let color = message.color.flatMap(UIColor.init(liveComponents:))
        else {
            return
        }
        strokes[id] = Stroke(
            ink: PKInk(PKInk.InkType(rawValue: inkName) ?? .pen, color: color),
            style: style,
            side: side,
            points: points,
            origin: now + Self.delay - first.timeOffset,
            creationDate: Date()
        )
        order.append(id)
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

    /// The points shown at `now`, as PencilKit strokes on a canvas of `side` points.
    func pencilKitStrokes(at now: TimeInterval, side: CGFloat) -> [PKStroke] {
        order.compactMap { id in
            guard let stroke = strokes[id] else {
                return nil
            }
            let elapsed = now - stroke.origin
            let shown = stroke.points.prefix { $0.timeOffset <= elapsed }
            guard !shown.isEmpty else {
                return nil
            }
            let scale = side / stroke.side
            let controlPoints = shown.map { point in
                stroke.style.point(
                    at: CGPoint(x: point.location.x * scale, y: point.location.y * scale),
                    timeOffset: point.timeOffset,
                    azimuth: point.azimuth,
                    scale: scale
                )
            }
            return PKStroke(
                ink: stroke.ink,
                path: PKStrokePath(controlPoints: controlPoints, creationDate: stroke.creationDate)
            )
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
