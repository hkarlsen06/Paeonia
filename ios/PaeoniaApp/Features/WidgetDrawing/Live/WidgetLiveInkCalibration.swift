import Foundation
import PencilKit

/// PencilKit does not say how a tool width becomes the attributes of a stroke's
/// points, and they decide how thick the line looks: size, but also opacity
/// and the newer secondary scale, threshold, and jitter. The slider spans a
/// wide range while the strokes barely change. This learns the attributes from
/// the strokes finished on this phone, so a live stroke on the partner's phone
/// looks like the real one will.
nonisolated struct WidgetLiveInkCalibration: Codable, Equatable {
    /// The typical point of a real stroke drawn with `width`.
    struct Style: Codable, Equatable {
        var width: Double
        var size: Double
        var opacity: Double = 1
        var force: Double = 1
        var altitude: Double = .pi / 2
        var secondaryScale: Double = 1
        var threshold: Double = 0
        var lateralJitter: Double = 0

        /// Before anything was learned: the tool width as the point size.
        static func fallback(width: CGFloat) -> Self {
            Style(width: Double(width), size: Double(width))
        }

        /// A point at `location` that looks like this style.
        func point(at location: CGPoint, timeOffset: TimeInterval, azimuth: CGFloat, scale: CGFloat) -> PKStrokePoint {
            let size = CGSize(width: self.size * scale, height: self.size * scale)
            if #available(iOS 27.0, *) {
                return PKStrokePoint(
                    location: location,
                    timeOffset: timeOffset,
                    size: size,
                    opacity: opacity,
                    force: force,
                    azimuth: azimuth,
                    altitude: altitude,
                    secondaryScale: secondaryScale,
                    threshold: threshold,
                    lateralJitter: lateralJitter
                )
            }
            return PKStrokePoint(
                location: location,
                timeOffset: timeOffset,
                size: size,
                opacity: opacity,
                force: force,
                azimuth: azimuth,
                altitude: altitude,
                secondaryScale: secondaryScale,
                threshold: threshold
            )
        }
    }

    static let maxSamplesPerInk = 24
    private static let storageKey = "widgetLive.inkCalibration.v2"

    private var samples: [String: [Style]] = [:]

    /// Finger and Apple Pencil strokes get very different points from
    /// PencilKit, so each ink is learned per input.
    static func key(ink: String, isPencil: Bool) -> String {
        "\(ink)|\(isPencil ? "pencil" : "finger")"
    }

    /// Records the typical point of a stroke drawn with `width`.
    mutating func record(ink key: String, width: CGFloat, stroke: PKStroke) {
        let points = Array(stroke.path)
        guard !points.isEmpty, width > 0 else {
            return
        }
        func median(_ value: (PKStrokePoint) -> CGFloat) -> Double {
            let sorted = points.map(value).sorted()
            return Double(sorted[sorted.count / 2])
        }
        var style = Style(width: Double(width), size: median(\.size.width))
        style.opacity = median(\.opacity)
        style.force = median(\.force)
        style.altitude = median(\.altitude)
        style.secondaryScale = median(\.secondaryScale)
        style.threshold = median(\.threshold)
        if #available(iOS 27.0, *) {
            style.lateralJitter = median(\.lateralJitter)
        }
        var list = samples[key, default: []].filter { abs($0.width - style.width) >= 0.01 }
        list.append(style)
        samples[key] = Array(list.suffix(Self.maxSamplesPerInk))
    }

    /// The style for `width`, from the closest recorded widths. Nil until a
    /// stroke with this ink and input was finished here.
    func style(ink key: String, width: CGFloat) -> Style? {
        let target = Double(width)
        let sorted = (samples[key] ?? []).sorted { $0.width < $1.width }
        if let exact = sorted.first(where: { abs($0.width - target) < 0.01 }) {
            return exact
        }
        let lower = sorted.last { $0.width < target }
        let upper = sorted.first { $0.width > target }
        if let lower, let upper {
            let fraction = (target - lower.width) / (upper.width - lower.width)
            var style = lower
            style.width = target
            style.size = lower.size + (upper.size - lower.size) * fraction
            return style
        }
        // Past the recorded widths: follow the size slope of the two nearest.
        guard let nearest = lower ?? upper else {
            return nil
        }
        let neighbor = lower != nil ? sorted.dropLast().last : sorted.dropFirst().first
        let slope = neighbor.map { max(0, ($0.size - nearest.size) / ($0.width - nearest.width)) } ?? 0
        var style = nearest
        style.width = target
        style.size = max(0.1, nearest.size + slope * (target - nearest.width))
        return style
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
