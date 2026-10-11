import PencilKit
import UIKit

/// A stroke being drawn here, collected from touches and sent in small batches.
struct WidgetLiveOutgoingStroke {
    let id = UUID().uuidString
    let startTimestamp: TimeInterval
    let ink: String
    let color: [Double]
    /// How the real stroke's points will look, learned on this phone.
    let style: WidgetLiveInkCalibration.Style
    let side: CGFloat
    private var buffer: [[Double]] = []
    private(set) var lastSentAt: TimeInterval = 0
    /// An `ops` message already named this stroke in `ended`.
    var isPartOfOps = false

    init(touch: UITouch, tool: PKInkingTool, side: CGFloat, style: WidgetLiveInkCalibration.Style?) {
        startTimestamp = touch.timestamp
        ink = tool.ink.inkType.rawValue
        color = tool.ink.color.liveComponents
        self.style = style ?? .fallback(width: tool.width)
        self.side = side
    }

    mutating func append(_ touch: UITouch, event: UIEvent, in view: UIView) {
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let location = sample.preciseLocation(in: view)
            // ponytail: every point gets the typical width, so a fast part of the
            // line is not thicker until the real stroke replaces this one.
            buffer.append([
                location.x,
                location.y,
                sample.timestamp - startTimestamp,
                sample.azimuthAngle(in: view),
            ].map { (Double($0) * 1_000).rounded() / 1_000 })
        }
    }

    /// The points collected since the last call, as a `live` message.
    mutating func takeMessage(now: TimeInterval) -> WidgetLiveMessage? {
        guard !buffer.isEmpty else {
            return nil
        }
        defer {
            buffer = []
            lastSentAt = now
        }
        return WidgetLiveMessage(
            type: .live,
            id: id,
            ink: ink,
            color: color,
            side: Double(side),
            points: buffer,
            pointStyle: style
        )
    }
}
