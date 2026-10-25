#if DEBUG
import CoreGraphics
import Foundation

/// Appends one JSON line to `Documents/shape-captures.jsonl` each time the
/// hold check runs the recognizer, with the stroke and every candidate's fit,
/// for tuning `ShapeRecognizer` on real strokes. Debug builds only, and off
/// unless the app launches with `-PaeoniaShapeCapture YES` (add it under the
/// scheme's Run arguments). Pull the file from a phone with
/// `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer
/// --domain-identifier no.paeonia.app --source Documents/shape-captures.jsonl --destination <file>`.
nonisolated enum ShapeCapture {
    private static let queue = DispatchQueue(label: "no.paeonia.shape-capture", qos: .utility)
    private static let isEnabled = UserDefaults.standard.bool(forKey: "PaeoniaShapeCapture")

    static func record(_ samples: [InkSample], canvasSide: CGFloat, result: SnappedShape?) {
        guard isEnabled else { return }
        let time = Date()
        queue.async {
            let tuning = ShapeRecognizer.Tuning.standard
            let stroke = ShapeRecognizer.Stroke(samples.map(\.location), tuning: tuning)
            let line: [String: Any] = [
                "time": ISO8601DateFormatter().string(from: time),
                "canvasSide": Double(canvasSide),
                "samples": samples.map { [Double($0.location.x), Double($0.location.y), $0.timeOffset] },
                "result": result.map { name(of: $0.kind) } ?? NSNull(),
                "isClosed": stroke.map { $0.isClosed as Any } ?? NSNull(),
                "candidates": stroke.map { candidates(of: $0, tuning: tuning) } ?? [],
            ]
            append(line)
        }
    }

    /// Each candidate that found a fit. One whose fitter gave up (an ellipse
    /// on a stroke with a corner) is missing.
    private static func candidates(
        of stroke: ShapeRecognizer.Stroke,
        tuning: ShapeRecognizer.Tuning
    ) -> [[String: Any]] {
        stroke.fits(tuning).map { fit in
            var entry: [String: Any] = [
                "shape": name(of: fit.kind),
                "residual": Double(fit.residual),
                "score": Double(fit.score),
                "limit": Double(fit.limit),
                "accepted": fit.isAccepted,
            ]
            if case .ellipse = fit.kind {
                var unrounded = tuning
                unrounded.circleRatio = .infinity
                if case let .ellipse(_, radii, _) = ShapeRecognizer.fitEllipse(stroke, unrounded) {
                    entry["radiiRatio"] = Double(min(radii.width, radii.height) / max(radii.width, radii.height))
                    entry["circleRatio"] = Double(tuning.circleRatio)
                }
            }
            return entry
        }
    }

    private static func name(of kind: SnappedShape.Kind) -> String {
        switch kind {
        case .line: "line"
        case .arc: "arc"
        case let .ellipse(_, radii, _): radii.width == radii.height ? "circle" : "ellipse"
        case let .polygon(corners): corners.count == 3 ? "triangle" : "rectangle"
        case .heart: "heart"
        }
    }

    private static func append(_ line: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return
        }
        data.append(0x0A)
        let file = documents.appendingPathComponent("shape-captures.jsonl")
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
#endif
