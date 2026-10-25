import UIKit

/// A stroke being drawn here, sent to the partner in small batches. Every
/// message carries the stroke's recipe, so the partner builds the same
/// `InkStroke` and its preview looks like the finished stroke.
nonisolated struct WidgetLiveOutgoingStroke {
    let id = UUID().uuidString
    let side: CGFloat
    private var sentCount = 0
    private(set) var lastSentAt: TimeInterval = 0

    init(side: CGFloat) {
        self.side = side
    }

    /// The samples of `stroke` not sent yet, as a `live` message.
    mutating func takeMessage(from stroke: InkStroke, now: TimeInterval) -> WidgetLiveMessage? {
        let fresh = stroke.samples.dropFirst(sentCount)
        guard !fresh.isEmpty else {
            return nil
        }
        sentCount = stroke.samples.count
        lastSentAt = now
        return WidgetLiveMessage(
            type: .live,
            id: id,
            ink: stroke.style.kind.rawValue,
            color: stroke.style.color.liveComponents,
            side: Double(side),
            points: fresh.map(\.liveValues),
            width: Double(stroke.style.width),
            seed: stroke.seed,
            lineStyle: stroke.style.lineStyle.rawValue
        )
    }
}

extension InkSample {
    /// `[x, y, timeOffset, azimuth, altitude]`, then `force` for Apple Pencil,
    /// as sent in `WidgetLiveMessage.points`.
    nonisolated var liveValues: [Double] {
        var values = [location.x, location.y, timeOffset, azimuth, altitude]
        if let force {
            values.append(force)
        }
        return values.map { (Double($0) * 1_000).rounded() / 1_000 }
    }

    nonisolated init?(liveValues values: [Double]) {
        guard (5...6).contains(values.count), values.allSatisfy(\.isFinite) else {
            return nil
        }
        self.init(
            location: CGPoint(x: values[0], y: values[1]),
            timeOffset: values[2],
            force: values.count == 6 ? values[5] : nil,
            azimuth: values[3],
            altitude: values[4]
        )
    }
}
