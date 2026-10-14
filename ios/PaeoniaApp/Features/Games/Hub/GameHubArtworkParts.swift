import SwiftUI

/// Timing that the hub artwork scenes share. A scene runs one `progress` from 0 to 1
/// at an even pace, and each part of the picture eases through its own slice of it.
enum GameHubArtworkTiming {
    /// 0 before `start`, 1 after `end`, and a smooth ease in between.
    static func ease(_ value: Double, from start: Double, to end: Double) -> Double {
        let fraction = min(max((value - start) / (end - start), 0), 1)
        return fraction * fraction * (3 - 2 * fraction)
    }

    /// Like `ease`, but it overshoots a little before it settles, like a small spring.
    static func pop(_ value: Double, from start: Double, to end: Double) -> Double {
        let fraction = min(max((value - start) / (end - start), 0), 1)
        let overshoot = 1.7
        let shifted = fraction - 1
        return 1 + (overshoot + 1) * shifted * shifted * shifted + overshoot * shifted * shifted
    }
}

/// One sparkle on a hub picture, placed as a fraction of the picture's size.
struct GameHubSparkle {
    let size: CGFloat
    let color: Color
    let x: CGFloat
    let y: CGFloat
}

/// The sparkles around a hub picture. They pop in one after another from `start`,
/// a fraction of the scene's `progress`.
struct GameHubSparkleField: View {
    let sparkles: [GameHubSparkle]
    let progress: Double
    let start: Double

    var body: some View {
        GeometryReader { proxy in
            ForEach(sparkles.indices, id: \.self) { index in
                let sparkle = sparkles[index]
                let begin = start + 0.025 * Double(index)
                let pop = GameHubArtworkTiming.pop(progress, from: begin, to: begin + 0.08)
                Image(systemName: "sparkle")
                    .accessibilityHidden(true)
                    .font(.system(size: sparkle.size, weight: .bold))
                    .foregroundStyle(sparkle.color)
                    .scaleEffect(0.3 + 0.7 * pop)
                    .opacity(min(1, pop * 2))
                    .position(x: proxy.size.width * sparkle.x, y: proxy.size.height * sparkle.y)
            }
        }
        .accessibilityHidden(true)
    }
}
