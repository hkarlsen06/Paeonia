import CoreGraphics
import Foundation

/// The note on the welcome widget, written by hand: "miss you" in English and
/// "savner deg" in Norwegian, in lowercase joined-up script on two lines, with a loose
/// pink heart and a little shine beside it. `WelcomeWidgetDoodle` writes it in stroke
/// by stroke.
///
/// Each word is one pen stroke, like real joined-up writing. A stroke is a list of
/// smooth runs (Catmull-Rom curves through the points) that meet at sharp turns, such
/// as the top of an `s`. The points are in letter units, with the baseline at 0 and the
/// top of a lowercase letter at 1, and the stroke places and slants them on a canvas
/// 100 points square.
nonisolated struct WelcomeDoodleInk {
    enum Ink {
        /// The petal pink of the drawing palette.
        case petal
        /// The near white blush of the drawing palette.
        case blush
    }

    struct Stroke {
        /// The pen's path on the 100-point canvas, finely sampled.
        let points: [CGPoint]
        /// How far along the path each point is, from 0 to `length`.
        let distances: [CGFloat]
        let ink: Ink
        /// The full line width on the 100-point canvas.
        let width: CGFloat
        /// Seconds after the note starts that the pen lands.
        let start: TimeInterval
        let duration: TimeInterval

        var length: CGFloat {
            distances.last ?? 0
        }
    }

    static let canvasSide: CGFloat = 100
    /// Canvas points the pen covers per second. A real hand is slower, but the note
    /// should be done within about three seconds.
    private static let writingSpeed: CGFloat = 260

    let strokes: [Stroke]

    /// Seconds from the first stroke landing to the last one lifting.
    var duration: TimeInterval {
        strokes.last.map { $0.start + $0.duration } ?? 0
    }

    /// The note in the language the app shows its text in.
    static var current: WelcomeDoodleInk {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return language.hasPrefix("nb") || language.hasPrefix("no") ? savnerDeg : missYou
    }

    /// How wide the line is at `fraction` of the way along a stroke `length` long,
    /// as a share of its full width. The line starts thin where the pen lands, is
    /// full through the stroke with a slight wobble, and thins again as it lifts.
    static func taper(at fraction: CGFloat, length: CGFloat) -> CGFloat {
        let landing = min(1, fraction * length / 4)
        let lifting = min(1, (1 - fraction) * length / 7)
        let pressure = min(landing * (2 - landing), lifting * (2 - lifting))
        let wobble = 0.92 + 0.08 * sin(fraction * length * 0.35)
        return 0.35 + 0.65 * pressure * wobble
    }

    // MARK: Building the strokes

    private typealias LetterPoint = (CGFloat, CGFloat)

    /// One stroke before it is placed: its runs, where letter (0, 0) lands on the
    /// canvas, the height of a lowercase letter, and how long to wait after the
    /// previous stroke lifts.
    private struct Draft {
        let runs: [[LetterPoint]]
        let ink: Ink
        let origin: CGPoint
        let size: CGFloat
        var slant: CGFloat = 0.28
        /// Letters are drawn narrow and widened here.
        var stretch: CGFloat = 1.3
        let width: CGFloat
        var pause: TimeInterval = 0.08
    }

    private init(_ drafts: [Draft]) {
        var strokes: [Stroke] = []
        var clock: TimeInterval = 0
        for draft in drafts {
            let points = Self.sample(draft)
            var distances: [CGFloat] = [0]
            for index in points.indices.dropFirst() {
                let step = hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
                distances.append(distances[index - 1] + step)
            }
            let duration = max(0.1, Double((distances.last ?? 0) / Self.writingSpeed))
            clock += strokes.isEmpty ? 0 : draft.pause
            strokes.append(
                Stroke(
                    points: points,
                    distances: distances,
                    ink: draft.ink,
                    width: draft.width,
                    start: clock,
                    duration: duration
                )
            )
            clock += duration
        }
        self.strokes = strokes
    }

    private static func sample(_ draft: Draft) -> [CGPoint] {
        var points: [CGPoint] = []
        for run in draft.runs {
            let placed = run.map { letter in
                CGPoint(
                    x: draft.origin.x + (letter.0 * draft.stretch + letter.1 * draft.slant) * draft.size,
                    y: draft.origin.y - letter.1 * draft.size
                )
            }
            let smooth = catmullRom(through: placed)
            points.append(contentsOf: points.isEmpty ? smooth : Array(smooth.dropFirst()))
        }
        return points
    }

    /// A smooth curve through every point, sampled `steps` times between each pair.
    private static func catmullRom(through points: [CGPoint], steps: Int = 10) -> [CGPoint] {
        guard points.count > 2 else {
            return points
        }
        var curve = [points[0]]
        for index in 0..<(points.count - 1) {
            let before = points[max(index - 1, 0)]
            let from = points[index]
            let to = points[index + 1]
            let after = points[min(index + 2, points.count - 1)]
            for step in 1...steps {
                let time = CGFloat(step) / CGFloat(steps)
                curve.append(
                    CGPoint(
                        x: catmullRom(before.x, from.x, to.x, after.x, time),
                        y: catmullRom(before.y, from.y, to.y, after.y, time)
                    )
                )
            }
        }
        return curve
    }

    private static func catmullRom(
        _ before: CGFloat,
        _ from: CGFloat,
        _ to: CGFloat,
        _ after: CGFloat,
        _ time: CGFloat
    ) -> CGFloat {
        let linear = (to - before) * time
        let square = (2 * before - 5 * from + 4 * to - after) * time * time
        let cube = (3 * from - before - 3 * to + after) * time * time * time
        return 0.5 * (2 * from + linear + square + cube)
    }

    // MARK: The notes

    private static func word(
        _ runs: [[LetterPoint]],
        at origin: CGPoint,
        size: CGFloat,
        width: CGFloat = 2
    ) -> Draft {
        Draft(runs: runs, ink: .blush, origin: origin, size: size, width: width)
    }

    private static func heart(at origin: CGPoint) -> Draft {
        Draft(
            runs: heartRuns, ink: .petal, origin: origin, size: 13, slant: 0.12, stretch: 1, width: 2.3, pause: 0.22
        )
    }

    /// Three short ticks off the heart's shoulder.
    private static func shine(at origin: CGPoint) -> [Draft] {
        shineRuns.map { runs in
            Draft(runs: runs, ink: .petal, origin: origin, size: 5, slant: 0, stretch: 1, width: 1.9, pause: 0.06)
        }
    }

    static let missYou = WelcomeDoodleInk(
        [
            word(miss, at: CGPoint(x: 10, y: 42), size: 16),
            word(missDot, at: CGPoint(x: 10, y: 42), size: 16, width: 2.8),
            word(you, at: CGPoint(x: 19, y: 70), size: 16),
            heart(at: CGPoint(x: 81, y: 71)),
        ] + shine(at: CGPoint(x: 89, y: 47))
    )

    static let savnerDeg = WelcomeDoodleInk(
        [
            word(savner, at: CGPoint(x: 8, y: 42), size: 15),
            word(deg, at: CGPoint(x: 28, y: 72), size: 15),
            heart(at: CGPoint(x: 79, y: 72)),
        ] + shine(at: CGPoint(x: 87, y: 48))
    )

    private static let miss: [[LetterPoint]] = [
        [(-0.1, 0.3), (0.04, 0.68), (0.13, 0.92), (0.22, 0.98)],
        [(0.22, 0.98), (0.32, 0.85), (0.36, 0.4), (0.36, 0.0)],
        [(0.36, 0.0), (0.4, 0.55), (0.5, 0.95), (0.6, 0.9), (0.66, 0.5), (0.66, 0.0)],
        [
            (0.66, 0.0), (0.7, 0.55), (0.8, 0.95), (0.9, 0.9), (0.96, 0.5), (0.98, 0.1), (1.08, 0.0), (1.2, 0.25),
            (1.32, 0.98),
        ],
        [(1.32, 0.98), (1.32, 0.4), (1.38, 0.05), (1.5, 0.05), (1.62, 0.4), (1.75, 1.05)],
        [(1.75, 1.05), (1.86, 0.6), (1.88, 0.25), (1.78, 0.03), (1.62, 0.05), (1.6, 0.18)],
        [(1.6, 0.18), (1.75, 0.1), (1.9, 0.12), (2.02, 0.45), (2.15, 1.05)],
        [(2.15, 1.05), (2.26, 0.6), (2.28, 0.25), (2.18, 0.03), (2.02, 0.05), (2.0, 0.18)],
        [(2.0, 0.18), (2.15, 0.1), (2.32, 0.15), (2.5, 0.45)],
    ]

    private static let missDot: [[LetterPoint]] = [[(1.3, 1.42), (1.33, 1.45)]]

    private static let you: [[LetterPoint]] = [
        [(-0.15, 0.6), (-0.02, 0.92), (0.06, 0.95)],
        [(0.06, 0.95), (0.05, 0.4), (0.15, 0.03), (0.3, 0.05), (0.42, 0.5), (0.48, 0.98)],
        [
            (0.48, 0.98), (0.47, 0.2), (0.42, -0.5), (0.32, -0.85), (0.2, -0.88), (0.17, -0.65), (0.35, -0.35),
            (0.6, -0.05), (0.8, 0.4), (0.98, 0.82), (1.12, 0.96),
        ],
        [
            (1.12, 0.96), (0.92, 0.8), (0.85, 0.35), (0.98, 0.02), (1.2, 0.04), (1.32, 0.45), (1.26, 0.9),
            (1.1, 0.98), (1.04, 0.86), (1.25, 0.86), (1.5, 0.88), (1.68, 0.84),
        ],
        [(1.68, 0.84), (1.64, 0.4), (1.7, 0.04), (1.84, 0.05), (1.96, 0.5), (2.02, 0.98)],
        [(2.02, 0.98), (2.01, 0.4), (2.06, 0.04), (2.19, 0.1), (2.32, 0.38)],
    ]

    private static let savner: [[LetterPoint]] = [
        [(-0.1, 0.3), (0.05, 0.62), (0.15, 1.05)],
        [(0.15, 1.05), (0.27, 0.6), (0.29, 0.25), (0.19, 0.03), (0.03, 0.05), (0.0, 0.18)],
        [(0.0, 0.18), (0.15, 0.1), (0.32, 0.15), (0.5, 0.5), (0.7, 0.9), (0.82, 0.95)],
        [(0.82, 0.95), (0.62, 0.86), (0.52, 0.45), (0.58, 0.05), (0.75, 0.06), (0.86, 0.5), (0.9, 0.96)],
        [(0.9, 0.96), (0.89, 0.3), (0.95, 0.03), (1.06, 0.08), (1.18, 0.5), (1.26, 0.95)],
        [
            (1.26, 0.95), (1.3, 0.45), (1.42, 0.02), (1.54, 0.35), (1.62, 0.88), (1.6, 0.98), (1.54, 0.9),
            (1.68, 0.86), (1.86, 0.84),
        ],
        [(1.86, 0.84), (1.85, 0.4), (1.86, 0.0)],
        [
            (1.86, 0.0), (1.9, 0.55), (2.02, 0.95), (2.14, 0.88), (2.19, 0.45), (2.2, 0.08), (2.3, 0.02),
            (2.46, 0.3), (2.66, 0.55), (2.72, 0.8), (2.64, 0.97), (2.53, 0.88), (2.48, 0.45), (2.55, 0.06),
            (2.72, 0.04), (2.88, 0.35), (2.98, 0.85), (3.02, 1.02),
        ],
        [(3.02, 1.02), (3.12, 0.92), (3.2, 0.88)],
        [(3.2, 0.88), (3.2, 0.4), (3.24, 0.05), (3.38, 0.08), (3.52, 0.35)],
    ]

    private static let deg: [[LetterPoint]] = [
        [(-0.15, 0.2), (0.1, 0.68), (0.36, 0.92)],
        [(0.36, 0.92), (0.15, 0.84), (0.05, 0.45), (0.12, 0.05), (0.3, 0.05), (0.44, 0.5), (0.53, 1.05), (0.6, 1.65)],
        [
            (0.6, 1.65), (0.53, 1.05), (0.49, 0.3), (0.54, 0.03), (0.68, 0.05), (0.84, 0.32), (1.02, 0.52),
            (1.08, 0.78), (1.0, 0.96), (0.9, 0.86), (0.86, 0.45), (0.93, 0.07), (1.08, 0.04), (1.24, 0.35),
            (1.38, 0.82), (1.52, 0.94),
        ],
        [(1.52, 0.94), (1.34, 0.86), (1.26, 0.45), (1.33, 0.05), (1.5, 0.07), (1.6, 0.5), (1.66, 0.96)],
        [
            (1.66, 0.96), (1.64, 0.2), (1.58, -0.5), (1.46, -0.86), (1.32, -0.88), (1.3, -0.65), (1.5, -0.32),
            (1.76, -0.04), (1.94, 0.3),
        ],
    ]

    /// One loop: down the left lobe from the tip, over both lobes, and back past the
    /// tip, where it does not quite meet.
    private static let heartRuns: [[LetterPoint]] = [
        [(0.0, 0.0), (-0.45, 0.5), (-0.62, 1.0), (-0.42, 1.3), (-0.12, 1.2), (0.02, 0.92)],
        [(0.02, 0.92), (0.2, 1.3), (0.55, 1.32), (0.66, 0.98), (0.45, 0.45), (0.04, -0.06)],
    ]

    private static let shineRuns: [[[LetterPoint]]] = [
        [[(0.0, 0.0), (0.05, 0.9)]],
        [[(0.45, -0.1), (1.0, 0.5)]],
        [[(0.55, -0.6), (1.15, -0.65)]],
    ]
}
