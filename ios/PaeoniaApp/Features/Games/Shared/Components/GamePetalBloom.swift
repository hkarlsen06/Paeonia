import SwiftUI

/// A short burst of petals from one point, drawn on a canvas. The same seed gives
/// the same burst, so a round always blooms the same way. It is lighter than the
/// pairing celebration: about 40 petals over 0.9 seconds.
struct GamePetalBloom: View {
    let start: Date
    let seed: String
    /// Where the petals leave from, as a fraction of the view.
    var origin = UnitPoint(x: 0.5, y: 0.5)
    /// 1 for the guesser's reveal, 0.5 for the drawer's.
    var intensity: CGFloat = 1

    static let duration: TimeInterval = 0.9
    private static let petalCount = 40

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True once the burst is over, so the timeline stops asking for frames.
    @State private var isFinished = false

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(paused: isFinished)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    guard !isFinished, elapsed >= 0, elapsed < Self.duration else { return }
                    draw(in: &context, size: size, progress: elapsed / Self.duration)
                }
            }
            .task(id: start) {
                isFinished = false
                let remaining = start.addingTimeInterval(Self.duration).timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(max(0, remaining)))
                guard !Task.isCancelled else { return }
                isFinished = true
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, progress: Double) {
        let center = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
        let reach = min(size.width, size.height) * 0.55 * intensity
        let eased = 1 - pow(1 - progress, 2.4)
        let count = Int(Double(Self.petalCount) * Double(intensity).squareRoot())
        for index in 0..<count {
            let seed = Double(index) + seedOffset
            let angle = rand(seed, 3.1) * 2 * .pi
            let distance = reach * (0.35 + rand(seed, 7.7) * 0.65) * eased
            // The burst fans out wider than it rises, then the petals sink a little.
            let sink = progress * progress * 26
            let position = CGPoint(
                x: center.x + cos(angle) * distance * 1.15,
                y: center.y + sin(angle) * distance * 0.8 + sink
            )
            let opacity = (1 - progress) * (0.65 + rand(seed, 11.3) * 0.35)
            guard opacity > 0.02 else { continue }

            let length = (6 + rand(seed, 5.3) * 5) * intensity.squareRoot()
            let spin = angle + progress * (rand(seed, 13.9) - 0.5) * 6
            var petal = context
            petal.translateBy(x: position.x, y: position.y)
            petal.rotate(by: .radians(spin))
            let rect = CGRect(x: -length / 2, y: -length * 0.3, width: length, height: length * 0.6)
            petal.fill(Path(ellipseIn: rect), with: .color(color(for: index).opacity(opacity)))
        }
    }

    private func color(for index: Int) -> Color {
        switch index % 3 {
        case 0: .paeoniaAccentPrimary
        case 1: .paeoniaAccentSecondary
        default: .paeoniaMemory
        }
    }

    /// A number from the seed string, so each round has its own burst.
    private var seedOffset: Double {
        Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9_973 })
    }

    private func rand(_ seed: Double, _ salt: Double) -> Double {
        let x = sin(seed * salt + salt) * 43_758.5453
        return x - floor(x)
    }
}
