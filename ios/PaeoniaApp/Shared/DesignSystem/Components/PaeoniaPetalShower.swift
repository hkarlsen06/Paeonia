import SwiftUI

/// Petals fired from two cannons below the bottom corners. They shoot up, spread over the whole
/// width of the screen, and tumble back down over about three and a half seconds. The same seed
/// gives the same shower. With `hearts`, every fifth petal is a heart. `PaeoniaPetalShowerHost`
/// draws it over the whole window.
struct PaeoniaPetalShower: View {
    let start: Date
    let seed: String
    var hearts = false

    static let duration: TimeInterval = 3.6
    private static let petalCount = 150
    private static let drag = 2.6
    private static let fadeIn = 0.05
    private static let fadeOut = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True once the shower is over, so the timeline stops asking for frames.
    @State private var isFinished = false

    private struct Petal {
        let position: CGPoint
        let length: Double
        let rotation: Double
        let flip: Double
        let opacity: Double
    }

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(paused: isFinished)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    guard !isFinished, elapsed >= 0, elapsed < Self.duration else { return }
                    draw(in: &context, size: size, elapsed: elapsed)
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

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let heart = hearts ? context.resolve(Image(systemName: "heart.fill")) : nil
        for index in 0..<Self.petalCount {
            guard let petal = petal(index, size: size, elapsed: elapsed) else { continue }
            var layer = context
            layer.translateBy(x: petal.position.x, y: petal.position.y)
            layer.rotate(by: .radians(petal.rotation))
            if var heart, index.isMultiple(of: 5) {
                heart.shading = .color(color(for: index).opacity(petal.opacity))
                let side = petal.length * 1.3
                layer.draw(heart, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                continue
            }
            let height = petal.length * 0.58 * petal.flip
            let rect = CGRect(x: -petal.length / 2, y: -height / 2, width: petal.length, height: height)
            layer.fill(Path(ellipseIn: rect), with: .color(color(for: index).opacity(petal.opacity)))
        }
    }

    private func petal(_ index: Int, size: CGSize, elapsed: Double) -> Petal? {
        let seed = Double(index) + seedOffset
        let isSecondPop = index % 3 == 0
        let wait = rand(seed, 2.3) * 0.22 + (isSecondPop ? 0.35 : 0)
        let age = elapsed - wait
        guard age >= 0 else { return nil }

        let width = size.width
        let height = size.height
        let fromLeft = index.isMultiple(of: 2)
        let travel = (1 - exp(-Self.drag * age)) / Self.drag
        let launchUp = height * (1.5 + rand(seed, 3.7) * 1.5)
        let launchAcross = width * (0.1 + rand(seed, 5.1) * 2.4) * (fromLeft ? 1 : -1)
        let fall = height * (0.18 + rand(seed, 6.9) * 0.3) * (age - travel)
        let phase = rand(seed, 8.3) * 2 * .pi
        let sway = sin(age * (2.2 + rand(seed, 9.7) * 2.4) + phase) * (10 + rand(seed, 11.3) * 16) * min(1, age / 0.6)

        let position = CGPoint(
            x: width * (fromLeft ? 0.08 : 0.92) + launchAcross * travel + sway,
            y: height * 1.02 - launchUp * travel + fall
        )
        let length = 9 + rand(seed, 12.7) * 9
        guard position.x > -length, position.x < width + length,
              position.y > -length, position.y < height + length else { return nil }

        let fadeIn = min(1, age / Self.fadeIn)
        let fadeOut = min(1, (Self.duration - elapsed) / Self.fadeOut)
        return Petal(
            position: position,
            length: length,
            rotation: rand(seed, 14.1) * 2 * .pi + age * (rand(seed, 15.9) - 0.5) * 7,
            flip: max(0.18, abs(cos(age * (4 + rand(seed, 17.3) * 5) + phase))),
            opacity: 0.95 * fadeIn * max(0, fadeOut)
        )
    }

    /// Counts by threes because every third petal is in the second pop, which would otherwise
    /// all be one colour.
    private func color(for index: Int) -> Color {
        switch (index / 3) % 3 {
        case 0: .paeoniaAccentPrimary
        case 1: .paeoniaAccentSecondary
        default: .paeoniaMemory
        }
    }

    /// A number from the seed string, so each moment has its own shower.
    private var seedOffset: Double {
        Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9_973 })
    }

    private func rand(_ seed: Double, _ salt: Double) -> Double {
        let x = sin(seed * salt + salt) * 43_758.5453
        return x - floor(x)
    }
}
