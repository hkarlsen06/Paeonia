import SwiftUI

/// The picture a hub card is made of: the shared backdrop, with the game's objects on
/// it. `docs/games/hub-artwork.md` has the rules.
enum GameHubArtworkLayout {
    /// The canvas the picture is laid out on, in pixels. It is as wide as the card and
    /// anchored at the top, so one pixel is `cardWidth / 1024` points.
    static let canvasSize = CGSize(width: 1_024, height: 1_536)
    /// How far down the scene reaches, as a share of the card's width. The card's text
    /// starts below it, so the scene keeps its shape at every card width.
    static let sceneShare: CGFloat = 720 / 1_024
    /// The backdrop goes out of focus under the text: a Gaussian blur that fades in over
    /// `blurFadeIn` points, starting `blurLead` points above where the text starts.
    static let blurRadius: CGFloat = 20
    static let blurLead: CGFloat = 24
    static let blurFadeIn: CGFloat = 40
}

/// A hub card's picture: the shared backdrop, as wide as the card and anchored at the
/// top, with the game's scene on it. Under the card's text the backdrop goes out of focus
/// with a Gaussian blur, so the picture carries on behind the text. The scene is laid out
/// in the canvas's pixels, so it keeps its shape at every card width. It plays once when
/// the card appears, as `progress` runs from 0 to 1 at an even pace. With Reduce Motion it
/// starts finished. VoiceOver skips the picture, since the card says the same in words.
struct GameHubArtwork<Scene: View & Animatable>: View {
    let duration: TimeInterval
    var delay: TimeInterval = 0.4
    let scene: (_ progress: Double) -> Scene

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = GameHubArtworkLayout.canvasSize
            let scale = proxy.size.width / canvasSize.width
            let textTop = proxy.size.width * GameHubArtworkLayout.sceneShare
            let backdropSize = CGSize(width: proxy.size.width, height: canvasSize.height * scale)
            ZStack(alignment: .topLeading) {
                GameHubBackdrop()
                    .frame(width: backdropSize.width, height: backdropSize.height)
                GameHubBackdrop()
                    .frame(width: backdropSize.width, height: backdropSize.height)
                    .blur(radius: GameHubArtworkLayout.blurRadius, opaque: true)
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: textTop - GameHubArtworkLayout.blurLead)
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: GameHubArtworkLayout.blurFadeIn)
                            Color.black
                        }
                    }
                scene(isPlayed || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : .linear(duration: duration).delay(delay), value: isPlayed)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(scale, anchor: .topLeading)
            }
        }
        // The backdrop ends in deep plum, so a card taller than the canvas continues it.
        .background(Color.paeoniaBackgroundSecondary)
        .clipped()
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
    }
}

/// The backdrop every hub card shares: a deep plum sky with two big hills, petal pink on
/// the left and lavender on the right, the two partners' worlds. They meet in a soft seam
/// behind the middle of the scene. The hills start at about pixel 220, below the badge,
/// and darken toward the bottom, so the card's text reads on them.
struct GameHubBackdrop: View {
    private static let sky = Gradient(stops: [
        .init(color: .paeoniaBackgroundSecondary, location: 0),
        .init(color: .paeoniaBackgroundPrimary, location: 0.46),
        .init(color: .paeoniaBackgroundSecondary, location: 1)
    ])
    /// The hills darken toward plum from the middle of the scene down, so the card's text
    /// keeps its contrast (`art_asset.py text` checks it).
    private static let hillShade = Gradient(stops: [
        .init(color: .paeoniaBackgroundElevated.opacity(0), location: 240 / 1_536),
        .init(color: .paeoniaBackgroundElevated.opacity(0.25), location: 480 / 1_536),
        .init(color: .paeoniaBackgroundElevated.opacity(0.6), location: 760 / 1_536),
        .init(color: .paeoniaBackgroundElevated, location: 1)
    ])

    var body: some View {
        Canvas { context, size in
            Self.paint(context, size: size)
        }
    }

    private static func paint(_ context: GraphicsContext, size: CGSize) {
        let scale = size.width / GameHubArtworkLayout.canvasSize.width
        let height = GameHubArtworkLayout.canvasSize.height * scale
        let top = CGPoint.zero
        let bottom = CGPoint(x: 0, y: height)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(sky, startPoint: top, endPoint: bottom)
        )
        var hills = Path()
        hills.addEllipse(in: circle(centerX: 190, centerY: 880, radius: 660, scale: scale))
        hills.addEllipse(in: circle(centerX: 834, centerY: 880, radius: 660, scale: scale))
        context.fill(
            hills,
            with: .linearGradient(
                Gradient(colors: [.paeoniaAccentPrimary, .paeoniaInkLavender]),
                startPoint: CGPoint(x: 482 * scale, y: 0),
                endPoint: CGPoint(x: 542 * scale, y: 0)
            )
        )
        context.fill(hills, with: .linearGradient(hillShade, startPoint: top, endPoint: bottom))
    }

    private static func circle(centerX: CGFloat, centerY: CGFloat, radius: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(
            x: (centerX - radius) * scale,
            y: (centerY - radius) * scale,
            width: radius * 2 * scale,
            height: radius * 2 * scale
        )
    }
}

/// Where an object stands in a card's scene. `base` is the middle of its lower edge and
/// `width` its width, both in the canvas's pixels. `aspect` is the image's width divided
/// by its height, measured from the asset.
struct GameHubPlacement {
    let base: CGPoint
    let width: CGFloat
    let aspect: CGFloat

    var height: CGFloat { width / aspect }

    /// A spot on the image, given as fractions of its width and height, in the canvas's
    /// pixels. Measure the fractions from the asset's pixels.
    func point(_ across: CGFloat, _ down: CGFloat) -> CGPoint {
        CGPoint(x: base.x - width / 2 + width * across, y: base.y - height + height * down)
    }
}

/// An illustrated object standing on the backdrop, such as a game board. A soft shadow
/// sits right under its lower edge, so it stands on the hill instead of floating over it.
struct GameHubObject: View {
    let image: ImageResource
    let placement: GameHubPlacement
    var tilt: Double = 0
    var shadow = true

    var body: some View {
        let base = placement.base
        ZStack {
            if shadow {
                Ellipse()
                    .fill(Color.paeoniaBackgroundSecondary.opacity(0.4))
                    .frame(width: placement.width * 0.8, height: max(18, placement.height * 0.07))
                    .blur(radius: 10)
                    .position(x: base.x, y: base.y - 4)
            }
            Image(image)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: placement.width, height: placement.height)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .position(x: base.x, y: base.y - placement.height / 2)
        }
    }
}

/// An illustrated object that pops into place on the scene, for the beat that lands a
/// card's moment. `center` and `size` are in the canvas's pixels.
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

/// A soft light that swells behind a spot in the scene. `center` and `radius` are in the
/// canvas's pixels.
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
