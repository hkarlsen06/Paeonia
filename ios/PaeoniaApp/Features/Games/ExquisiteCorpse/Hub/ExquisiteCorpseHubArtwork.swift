import SwiftUI

/// The picture at the top of the Exquisite corpse card: a strip of paper in three
/// parts, tilted toward the viewer. The parts swing open from the top one by one, and
/// each part draws itself before the next one opens: a cat's head, a striped sweater
/// and chicken legs, with the lines meeting at the folds. It plays once when the card
/// appears. With Reduce Motion it starts finished.
struct ExquisiteCorpseHubArtwork: View {
    static let height: CGFloat = 200
    private static let playDuration: TimeInterval = 4.4
    private static let playDelay: TimeInterval = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        let shown = isPlayed || reduceMotion
        ZStack {
            background
            ExquisiteCorpseHubScene(progress: shown ? 1 : 0)
                // An even pace, so each part can open and draw on its own (see `ExquisiteCorpseHubScene`).
                .animation(
                    reduceMotion ? nil : .linear(duration: Self.playDuration).delay(Self.playDelay),
                    value: isPlayed
                )
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The art is a picture, so it keeps its size at every text size.
        .dynamicTypeSize(.large)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(
                colors: [Color.paeoniaInkBlue.opacity(0.28), .clear],
                center: UnitPoint(x: 0.12, y: 0.15),
                startRadius: 0,
                endRadius: 200
            )
            RadialGradient(
                colors: [Color.paeoniaInkGold.opacity(0.22), .clear],
                center: UnitPoint(x: 0.92, y: 0.95),
                startRadius: 0,
                endRadius: 190
            )
        }
    }
}

/// The strip. `progress` runs from 0 to 1 at an even pace. Each part takes its own
/// slice of it: it swings down from edge-on to flat, and then its lines draw in.
/// When the legs are done, a light comes up behind the creature and it hops.
private struct ExquisiteCorpseHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let panelSize = CGSize(width: 136, height: 38)
    private static let parts: [ExquisiteCorpsePartKind] = [.head, .body, .legs]
    /// Where the first part starts, and how much of `progress` one part takes.
    private static let firstPart = 0.02
    private static let partStep = 0.27
    /// Of one part's slice, how much the swing takes. Drawing takes the rest.
    private static let swingShare = 0.3
    private static let finish = firstPart + partStep * Double(parts.count)

    private static let sparkles = [
        GameHubSparkle(size: 14, color: .paeoniaInkGold, x: 0.24, y: 0.62),
        GameHubSparkle(size: 9, color: .paeoniaInkBlue, x: 0.3, y: 0.3),
        GameHubSparkle(size: 11, color: .paeoniaTextPrimary, x: 0.75, y: 0.34),
        GameHubSparkle(size: 8, color: .paeoniaInkGold, x: 0.78, y: 0.7),
        GameHubSparkle(size: 9, color: .paeoniaInkLavender, x: 0.7, y: 0.86),
    ]

    var body: some View {
        let done = Timing.ease(progress, from: Self.finish - 0.02, to: Self.finish + 0.08)
        let hop = Timing.pop(progress, from: Self.finish, to: Self.finish + 0.1)
        ZStack {
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.35), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 120
            )
            .opacity(done)
            GameHubSparkleField(sparkles: Self.sparkles, progress: progress, start: Self.finish)
            strip
                .scaleEffect(1 + 0.05 * sin(hop * .pi))
                // Clear of the chips at the top of the card and the fade into the card at the bottom.
                .padding(.top, PaeoniaSpacing.space24)
                .padding(.bottom, PaeoniaSpacing.space16)
        }
    }

    private var strip: some View {
        VStack(spacing: 0) {
            ForEach(Self.parts, id: \.rawValue) { part in
                let start = Self.firstPart + Self.partStep * Double(part.rawValue)
                let swingEnd = start + Self.partStep * Self.swingShare
                ExquisiteCorpseHubPanel(
                    part: part,
                    open: Timing.ease(progress, from: start, to: swingEnd),
                    drawn: min(max((progress - swingEnd) / (start + Self.partStep - swingEnd), 0), 1)
                )
                .frame(width: Self.panelSize.width, height: Self.panelSize.height)
            }
        }
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.7), radius: 14, y: 8)
        .rotation3DEffect(.degrees(14), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotationEffect(.degrees(-4))
    }
}

/// One part of the strip. It hangs from its top edge and swings down from edge-on to
/// flat. While it is mostly folded it shows the back of the paper, which fades out to
/// leave the part's drawing. A dashed crease and a soft shadow mark the fold under it.
private struct ExquisiteCorpseHubPanel: View {
    let part: ExquisiteCorpsePartKind
    /// From 0 (folded) to 1 (open).
    let open: Double
    /// How much of the drawing is done, from 0 to 1.
    let drawn: Double

    var body: some View {
        let shape = panelShape
        let folded = 1 - open
        ZStack {
            Rectangle().fill(.paeoniaBackgroundPrimary)
            // Light from the top, so each part reads as its own fold of paper.
            LinearGradient(
                colors: [Color.paeoniaTextPrimary.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            ExquisiteCorpseHubDoodle(part: part, drawn: drawn)
            ExquisiteCorpsePaperBack()
                .opacity(min(1, folded * 2.5))
        }
        .overlay(alignment: .bottom) { crease }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.paeoniaTextPrimary.opacity(0.3), lineWidth: PaeoniaRadius.strokeDefault)
        }
        .rotation3DEffect(.degrees(folded * 90), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
        // Edge-on, a part is a thin line. It is not worth showing.
        .opacity(min(1, open * 6))
    }

    @ViewBuilder private var crease: some View {
        if part != .legs {
            ExquisiteCorpseHorizontalLine()
                .stroke(
                    Color.paeoniaTextPrimary.opacity(0.35),
                    style: StrokeStyle(lineWidth: PaeoniaRadius.strokeDefault, dash: [4, 3])
                )
                .frame(height: PaeoniaRadius.strokeDefault)
                .background(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, Color.paeoniaBackgroundSecondary.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                }
        }
    }

    /// Round only the outer corners of the strip.
    private var panelShape: UnevenRoundedRectangle {
        let isFirst = part == .head
        let isLast = part == .legs
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? PaeoniaRadius.radius12 : 0,
            bottomLeadingRadius: isLast ? PaeoniaRadius.radius12 : 0,
            bottomTrailingRadius: isLast ? PaeoniaRadius.radius12 : 0,
            topTrailingRadius: isFirst ? PaeoniaRadius.radius12 : 0,
            style: .continuous
        )
    }
}

#if DEBUG
#Preview {
    ExquisiteCorpseHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
