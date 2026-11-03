import SwiftUI

/// A hub card's picture: the game's scene on a moving backdrop in the colors of the scene
/// itself (`GameHubFluidBackdrop`), behind the whole card. The scene is laid out in the
/// canvas's pixels, so it keeps its shape at every card width. It plays once when the card
/// appears, as `progress` runs from 0 to 1 at an even pace. With Reduce Motion it starts
/// finished. VoiceOver skips the picture, since the card says the same in words.
///
/// On a hub tile with the couple's own content (`gameHubTilePicture`), that content stands
/// in place of the scene, and the backdrop takes its colors. Without a `kind`, as on the
/// daily question card, the scene stands in the painted room (`GameHubBackdrop`) instead.
struct GameHubArtwork<Scene: View & Animatable>: View {
    var kind: GameKind?
    let duration: TimeInterval
    var delay: TimeInterval = 0.4
    let scene: (_ progress: Double) -> Scene

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.paeoniaIllustratedScene) private var layout
    @Environment(\.gameHubTilePicture) private var picture
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter: PaeoniaBannerCenter?
    @State private var isPlayed = false

    private var paletteSource: GameHubPaletteSource? {
        if let picture { return .content(picture.preview) }
        return kind.map { .illustration($0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = PaeoniaIllustratedCardLayout.canvasSize
            let scale = proxy.size.width / canvasSize.width
            let objectScale = scale * layout.objectScale
            let base = PaeoniaIllustratedCardLayout.Scene.fullObjectBase
            ZStack(alignment: .topLeading) {
                if let paletteSource {
                    GameHubFluidBackdrop(palette: GameHubPalettes.shared[paletteSource] ?? .fallback)
                } else {
                    room(
                        size: CGSize(width: proxy.size.width, height: canvasSize.height * scale),
                        top: -layout.top * scale,
                        textTop: proxy.size.width * layout.share
                    )
                }
                Group {
                    if let picture {
                        GameHubTileContent(picture: picture)
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
        // The room ends in deep plum, so a card taller than the canvas continues it.
        .background(Color.paeoniaBackgroundSecondary)
        .clipped()
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
        .task(id: paletteSource) {
            guard let paletteSource else { return }
            await GameHubPalettes.shared.load(paletteSource, drawings: picture?.drawings, render: renderPicture)
        }
    }

    /// The card's picture drawn small, for its palette. An image renderer starts with an
    /// empty environment, and the board views in the couple's content read the banner center.
    private func renderPicture() -> CGImage? {
        if let picture {
            let content = GameChatPreviewContent(
                preview: picture.preview, drawings: picture.drawings, ownerUserID: picture.ownerUserID,
                participants: picture.participants
            ) { Color.clear }
            return GameHubPalettes.render(content.environment(bannerCenter), width: GameChatPreview.side)
        }
        let canvas = PaeoniaIllustratedCardLayout.canvasSize
        return GameHubPalettes.render(scene(1).frame(width: canvas.width, height: canvas.height), width: canvas.width)
    }

    /// The room, sharp above the text and out of focus under it.
    private func room(size: CGSize, top: CGFloat, textTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            GameHubBackdrop()
                .frame(width: size.width, height: size.height)
                .offset(y: top)
            GameHubBackdrop()
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

/// The daily question card's backdrop: a room at night, its left wall lit pink and its
/// right wall lavender. The corner where they meet is behind the middle of the scene, and
/// the floor in front is where the objects stand. Below the scene the floor darkens to
/// deep plum, so the card's text reads on it.
struct GameHubBackdrop: View {
    var body: some View {
        Image(.gameHubBackdrop)
            .resizable()
            .accessibilityHidden(true)
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
