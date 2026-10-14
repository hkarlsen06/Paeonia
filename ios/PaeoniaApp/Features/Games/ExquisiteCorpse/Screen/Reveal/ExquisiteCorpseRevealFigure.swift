import SwiftUI

/// The figure of the reveal: three squares stacked head, body, legs, each under a
/// flap of folded paper. A flap swings up around its top edge to open its fold.
///
/// The figure is laid out once at `camera.layoutSide` per part. The camera scales
/// it down and moves it, so strokes stay crisp at every size. Each part draws its
/// strokes on a replay canvas that the `player` drives.
///
/// The caller adds the VoiceOver label, because it knows the figure's number and
/// who drew it.
struct ExquisiteCorpseRevealFigure: View {
    let player: ExquisiteCorpseFigurePlayer
    let camera: ExquisiteCorpseRevealCamera
    let shot: ExquisiteCorpseRevealCamera.Shot
    /// The parts whose fold has opened.
    let openParts: Set<ExquisiteCorpsePartKind>
    /// The drawings are on the phone, so the parts can draw them.
    let isLoaded: Bool
    /// The closed paper waits for the drawings and shimmers while it does.
    let isWaiting: Bool
    let reduceMotion: Bool
    let cameraAnimation: Animation?

    var body: some View {
        let placement = camera.placement(for: shot)
        figure
            .scaleEffect(placement.scale, anchor: .topLeading)
            .offset(x: placement.origin.x, y: placement.origin.y)
            .frame(width: camera.stage.width, height: camera.stage.height, alignment: .topLeading)
            // A framed part hides what comes after it, so its caption sits on empty space.
            .mask(alignment: .top) {
                Rectangle().frame(height: camera.visibleHeight(for: shot))
            }
            .animation(cameraAnimation, value: shot)
    }

    private var figure: some View {
        let side = camera.layoutSide
        let corner = RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(ExquisiteCorpsePartKind.allCases, id: \.self) { kind in
                ExquisiteCorpseRevealPart(
                    kind: kind,
                    side: side,
                    seam: kind == .head ? 0 : camera.hairline,
                    player: player,
                    isLoaded: isLoaded,
                    isOpen: openParts.contains(kind),
                    isWaiting: isWaiting,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(width: side, height: side * CGFloat(ExquisiteCorpsePartKind.allCases.count))
        .clipShape(corner)
        .overlay {
            corner
                .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeEmphasis)
                .allowsHitTesting(false)
        }
    }
}

/// One square of the figure: the drawing under a flap of paper.
private struct ExquisiteCorpseRevealPart: View {
    let kind: ExquisiteCorpsePartKind
    let side: CGFloat
    /// The thickness of the line along the top edge, 0 for none.
    let seam: CGFloat
    let player: ExquisiteCorpseFigurePlayer
    let isLoaded: Bool
    let isOpen: Bool
    let isWaiting: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.paeoniaBackgroundPrimary
            if isLoaded {
                GameReplaySurface(frames: player.frames(for: kind), side: side)
                    // Fresh canvases after the parts were blanked, so no old strokes stay.
                    .id(player.generation)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            Rectangle()
                .fill(.paeoniaTextTertiary.opacity(0.3))
                .frame(height: seam)
                .frame(maxHeight: .infinity, alignment: .top)
            // The flap's shadow falls on the drawing and fades as the flap lifts.
            LinearGradient(
                colors: [.paeoniaBackgroundSecondary.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(isOpen ? 0 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: isOpen)
            flap
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// The back of the paper. It swings up around its top edge until it is edge-on
    /// and gone. The perspective makes its bottom edge come toward the viewer.
    private var flap: some View {
        ExquisiteCorpsePaperBack()
            .overlay {
                if isWaiting {
                    ExquisiteCorpseRevealShimmer()
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: isWaiting)
            .clipped()
            .rotation3DEffect(
                .degrees(isOpen ? Self.openAngle : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: Self.perspective
            )
            .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: isOpen)
            .allowsHitTesting(false)
    }

    private static let openAngle = -90.0
    private static let perspective: CGFloat = 0.5
}

/// A soft band of light that crosses the closed paper again and again while it
/// waits for the drawings. With Reduce Motion the paper keeps a still tint.
private struct ExquisiteCorpseRevealShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.paeoniaAccentPrimary.opacity(0.14)
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, .paeoniaTextPrimary.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.6)
                    .offset(x: isSweeping ? proxy.size.width : -proxy.size.width)
                    .animation(Self.sweep, value: isSweeping)
                }
            }
        }
        .clipped()
        .onAppear { isSweeping = true }
        .accessibilityHidden(true)
    }

    private static let sweep = PaeoniaMotion.standardCurve(duration: 2.4).repeatForever(autoreverses: false)
}
