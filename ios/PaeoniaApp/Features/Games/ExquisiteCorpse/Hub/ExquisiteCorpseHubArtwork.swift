import SwiftUI

/// The picture at the top of the Exquisite corpse card: three paper panels stacked
/// like a folded strip. They unfold one by one to show a doodle creature, a cat's
/// head, a striped sweater and chicken legs, with the parts meeting at the folds.
/// It plays once when the card appears. With Reduce Motion it starts unfolded.
struct ExquisiteCorpseHubArtwork: View {
    static let height: CGFloat = 200
    private static let panelSize = CGSize(width: 120, height: 44)
    private static let parts: [ExquisiteCorpsePartKind] = [.head, .body, .legs]
    /// Seconds before the first panel opens.
    private static let unfoldDelay: TimeInterval = 0.3
    /// Seconds one panel takes to open.
    private static let unfoldDuration: TimeInterval = 0.8
    /// Seconds between the start of one panel and the start of the next.
    private static let unfoldStagger: TimeInterval = 0.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isUnfolded = false

    private var showsUnfolded: Bool {
        isUnfolded || reduceMotion
    }

    var body: some View {
        ZStack {
            background
            sparkles
            stack
                .padding(.top, PaeoniaSpacing.space8)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The art is a picture, so it keeps its size at every text size.
        .dynamicTypeSize(.large)
        .clipped()
        .accessibilityHidden(true)
        // The animations sit on the panels, so this change needs no animation of its own.
        .onAppear { isUnfolded = true }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.45), .clear],
                center: UnitPoint(x: 0.12, y: 0.1),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color.paeoniaInkLavender.opacity(0.3), .clear],
                center: UnitPoint(x: 0.95, y: 0.95),
                startRadius: 0,
                endRadius: 200
            )
            // A glow behind the strip that comes up as it opens.
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.25), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 120
            )
            .opacity(showsUnfolded ? 1 : 0)
            .animation(
                reduceMotion ? nil : PaeoniaMotion.standardCurve(duration: Self.totalDuration),
                value: showsUnfolded
            )
        }
    }

    private var stack: some View {
        VStack(spacing: 0) {
            ForEach(Self.parts, id: \.rawValue) { part in
                ExquisiteCorpseHubPanel(part: part, progress: showsUnfolded ? 1 : 0)
                    .frame(width: Self.panelSize.width, height: Self.panelSize.height)
                    .animation(reduceMotion ? nil : unfold(part), value: showsUnfolded)
            }
        }
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.6), radius: 14, y: 8)
        .rotationEffect(.degrees(-3))
    }

    /// Each panel opens a little after the one above it, at an even pace between
    /// them, so the strip unfolds from the top.
    private func unfold(_ part: ExquisiteCorpsePartKind) -> Animation {
        PaeoniaMotion.standardCurve(duration: Self.unfoldDuration)
            .delay(Self.unfoldDelay + Double(part.rawValue) * Self.unfoldStagger)
    }

    private static var totalDuration: TimeInterval {
        unfoldDelay + Double(parts.count - 1) * unfoldStagger + unfoldDuration
    }

    // MARK: Sparkles

    private var sparkles: some View {
        GeometryReader { proxy in
            ForEach(Self.sparkles.indices, id: \.self) { index in
                let sparkle = Self.sparkles[index]
                Image(systemName: "sparkle")
                    .accessibilityHidden(true)
                    .font(.system(size: sparkle.size, weight: .bold))
                    .foregroundStyle(sparkle.color)
                    .position(x: proxy.size.width * sparkle.x, y: proxy.size.height * sparkle.y)
                    .opacity(showsUnfolded ? 1 : 0)
                    .scaleEffect(showsUnfolded ? 1 : 0.3)
                    .animation(reduceMotion ? nil : sparkleAnimation(index), value: showsUnfolded)
            }
        }
    }

    /// The sparkles pop in one after another as the last panel settles.
    private func sparkleAnimation(_ index: Int) -> Animation {
        PaeoniaMotion.cardReveal.delay(Self.totalDuration - 0.3 + Double(index) * 0.1)
    }

    private struct Sparkle {
        let size: CGFloat
        let color: Color
        let x: CGFloat
        let y: CGFloat
    }

    private static let sparkles = [
        Sparkle(size: 14, color: .paeoniaInkGold, x: 0.14, y: 0.62),
        Sparkle(size: 9, color: .paeoniaTextSecondary, x: 0.24, y: 0.3),
        Sparkle(size: 11, color: .paeoniaTextPrimary, x: 0.84, y: 0.34),
        Sparkle(size: 8, color: .paeoniaInkGold, x: 0.88, y: 0.7),
        Sparkle(size: 9, color: .paeoniaAccentSecondary, x: 0.76, y: 0.86),
    ]
}

/// One panel of the strip. It hangs from its top edge and swings down from edge-on
/// to flat. While it is mostly folded it shows the back of the paper, which fades
/// out to leave the doodle. `progress` runs from 0 (folded) to 1 (open).
private struct ExquisiteCorpseHubPanel: View, Animatable {
    let part: ExquisiteCorpsePartKind
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let shape = panelShape
        let folded = 1 - progress
        ZStack {
            Rectangle().fill(.paeoniaBackgroundPrimary)
            ExquisiteCorpseHubDoodle(part: part)
            ExquisiteCorpsePaperBack()
                .opacity(min(1, folded * 2.5))
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.paeoniaTextPrimary.opacity(0.25), lineWidth: PaeoniaRadius.strokeDefault)
        }
        .rotation3DEffect(.degrees(folded * 90), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
        // Edge-on, a panel is a thin line. It is not worth showing.
        .opacity(min(1, progress * 6))
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
