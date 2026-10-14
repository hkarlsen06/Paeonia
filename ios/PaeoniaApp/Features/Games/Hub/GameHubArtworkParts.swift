import SwiftUI

/// The painting a hub card is made of. `docs/games/hub-artwork.md` has the rules.
enum GameHubArtworkLayout {
    /// The painting's size in pixels. It is as wide as the card and anchored at the top,
    /// so one pixel is `cardWidth / 1024` points.
    static let plateSize = CGSize(width: 1_024, height: 1_536)
    /// How far down the scene reaches, as a share of the card's width. The card's text
    /// starts below it, so the scene keeps its shape at every card width.
    static let sceneShare: CGFloat = 640 / 1_024
}

/// A hub card's picture: the game's painting, as wide as the card and anchored at the top,
/// with one animated beat on top. The beat is laid out in the painting's own pixels, so
/// it lands on the spot the painting leaves for it at every card width. It plays once when
/// the card appears, as `progress` runs from 0 to 1 at an even pace. With Reduce Motion
/// it starts finished. VoiceOver skips the picture, since the card says the same in words.
struct GameHubArtwork<Beat: View & Animatable>: View {
    let plate: ImageResource
    let duration: TimeInterval
    var delay: TimeInterval = 0.4
    let beat: (_ progress: Double) -> Beat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        GeometryReader { proxy in
            let plateSize = GameHubArtworkLayout.plateSize
            let scale = proxy.size.width / plateSize.width
            ZStack(alignment: .topLeading) {
                Image(plate)
                    .resizable()
                    .accessibilityHidden(true)
                    .frame(width: proxy.size.width, height: plateSize.height * scale)
                beat(isPlayed || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : .linear(duration: duration).delay(delay), value: isPlayed)
                    .frame(width: plateSize.width, height: plateSize.height)
                    .scaleEffect(scale, anchor: .topLeading)
            }
        }
        // The paintings end in deep plum, so a card taller than its painting continues it.
        .background(Color.paeoniaBackgroundSecondary)
        .clipped()
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
    }
}

/// An illustrated object that pops into place on a painting, for the beat that lands a
/// card's moment. `center` and `size` are in the painting's pixels.
struct GameHubBeatPop: View {
    let image: ImageResource
    let center: CGPoint
    let size: CGFloat
    let progress: Double
    let start: Double

    var body: some View {
        let pop = GameHubArtworkTiming.pop(progress, from: start, to: start + 0.12)
        Image(image)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(max(0, pop))
            .rotationEffect(.degrees(-30 * (1 - pop)))
            .position(center)
    }
}

/// A soft light that swells behind a spot on a painting. `center` and `radius` are in the
/// painting's pixels.
struct GameHubBeatGlow: View {
    let color: Color
    let center: CGPoint
    let radius: CGFloat
    let strength: Double

    var body: some View {
        RadialGradient(
            colors: [color.opacity(0.55 * strength), .clear],
            center: .center,
            startRadius: 0,
            endRadius: radius
        )
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            .blendMode(.screen)
    }
}

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
