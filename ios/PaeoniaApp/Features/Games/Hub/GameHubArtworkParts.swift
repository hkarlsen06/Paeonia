import SwiftUI

/// A hub card's picture: the shared backdrop, as wide as the card and anchored at the
/// top, with the game's scene on it. Under the card's text the backdrop goes out of focus
/// with a Gaussian blur, so the picture carries on behind the text. The scene is laid out
/// in the canvas's pixels, so it keeps its shape at every card width. It plays once when
/// the card appears, as `progress` runs from 0 to 1 at an even pace. With Reduce Motion it
/// starts finished. VoiceOver skips the picture, since the card says the same in words.
///
/// `kind` tints the backdrop's walls in the game's color. On a hub tile with the couple's
/// own content (`gameHubTilePicture`), that picture stands in place of the scene.
struct GameHubArtwork<Scene: View & Animatable>: View {
    var kind: GameKind?
    let duration: TimeInterval
    var delay: TimeInterval = 0.4
    let scene: (_ progress: Double) -> Scene

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.paeoniaIllustratedScene) private var layout
    @Environment(\.gameHubTilePicture) private var picture
    @State private var isPlayed = false

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = PaeoniaIllustratedCardLayout.canvasSize
            let scale = proxy.size.width / canvasSize.width
            let textTop = proxy.size.width * layout.share
            let backdropSize = CGSize(width: proxy.size.width, height: canvasSize.height * scale)
            let backdropTop = -layout.top * scale
            let objectScale = scale * layout.objectScale
            let base = PaeoniaIllustratedCardLayout.Scene.fullObjectBase
            ZStack(alignment: .topLeading) {
                backdrop(size: backdropSize, top: backdropTop, textTop: textTop)
                Group {
                    if let picture {
                        GameHubTileContent(picture: picture, tint: kind?.hubWallTint)
                    } else {
                        scene(isPlayed || reduceMotion ? 1 : 0)
                            .animation(reduceMotion ? nil : .linear(duration: duration).delay(delay), value: isPlayed)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(objectScale, anchor: .topLeading)
                // The middle of the main object's lower edge lands where the layout puts it.
                .offset(
                    x: canvasSize.width / 2 * (scale - objectScale),
                    y: (layout.objectBase - layout.top) * scale - base * objectScale
                )
            }
        }
        // The backdrop ends in deep plum, so a card taller than the canvas continues it.
        .background(Color.paeoniaBackgroundSecondary)
        .clipped()
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
    }

    /// The backdrop, sharp above the text and out of focus under it.
    private func backdrop(size: CGSize, top: CGFloat, textTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            GameHubBackdrop(tint: kind?.hubWallTint)
                .frame(width: size.width, height: size.height)
                .offset(y: top)
            GameHubBackdrop(tint: kind?.hubWallTint)
                .frame(width: size.width, height: size.height)
                .offset(y: top)
                .blur(radius: PaeoniaIllustratedCardLayout.blurRadius, opaque: true)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: textTop - PaeoniaIllustratedCardLayout.blurLead)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: PaeoniaIllustratedCardLayout.blurFadeIn)
                        Color.black
                    }
                }
        }
    }
}

/// The backdrop every hub card shares: a room at night, its left wall lit pink and its
/// right wall lavender. The corner where they meet is behind the middle of the scene, and
/// the floor in front is where the game's objects stand. Below the scene the floor darkens
/// to deep plum, so the card's text reads on it. A game's `tint` colors the walls and
/// keeps their light and shade (a `color` blend), so every game has its own room in the
/// same house. The floor stays as it is.
struct GameHubBackdrop: View {
    var tint: Color?

    /// Keep in step with `TINT_OPACITY` and `TINT_SHADE` in `art_asset.py`. The shade keeps
    /// a cream object 3:1 from the tinted wall behind it.
    static let tintOpacity = 0.85
    static let tintShade = 0.1

    var body: some View {
        Image(.gameHubBackdrop)
            .resizable()
            .overlay {
                if let tint {
                    tint.opacity(Self.tintOpacity)
                        .blendMode(.color)
                        .mask { GameHubWalls().blur(radius: 1) }
                }
            }
            .overlay {
                if tint != nil {
                    Color.black.opacity(Self.tintShade)
                        .mask { GameHubWalls().blur(radius: 1) }
                }
            }
            .compositingGroup()
            .accessibilityHidden(true)
    }
}

/// The two walls of the backdrop, down to where they meet the floor, measured on the image.
nonisolated private struct GameHubWalls: Shape {
    func path(in rect: CGRect) -> Path {
        let canvas = PaeoniaIllustratedCardLayout.canvasSize
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / canvas.width, y: rect.minY + rect.height * y / canvas.height)
        }
        var path = Path()
        path.addLines([point(0, 0), point(1_024, 0), point(1_024, 316), point(514, 250), point(0, 325)])
        path.closeSubpath()
        return path
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
