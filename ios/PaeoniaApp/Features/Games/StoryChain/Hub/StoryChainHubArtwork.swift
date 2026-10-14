import SwiftUI

/// The picture at the top of the Story Chain card: a notebook page tilted toward the
/// viewer, where a story writes itself in looping handwriting. The ink changes where
/// one partner's sentence ends and the other's begins, one word gets the gold dare
/// underline, and a small flower closes the story. It plays once when the card appears.
/// With Reduce Motion it starts finished.
struct StoryChainHubArtwork: View {
    static let height: CGFloat = 200
    private static let playDuration: TimeInterval = 4.8
    private static let playDelay: TimeInterval = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        let shown = isPlayed || reduceMotion
        ZStack {
            background
            StoryChainHubScene(progress: shown ? 1 : 0)
                // An even pace, so each word can write itself on its own (see `StoryChainHubScene`).
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
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.4), .clear],
                center: UnitPoint(x: 0.15, y: 0.1),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color.paeoniaInkGold.opacity(0.2), .clear],
                center: UnitPoint(x: 0.9, y: 0.95),
                startRadius: 0,
                endRadius: 200
            )
        }
    }
}

/// The page. `progress` runs from 0 to 1 at an even pace. The words write themselves
/// one after another, each taking a share of the writing time that fits its width, and
/// a dot of wet ink rides the tip of the line being written.
private struct StoryChainHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    static let pageSize = CGSize(width: 236, height: 122)
    static let margin: CGFloat = 30
    static let firstBaseline: CGFloat = 27
    static let rowHeight: CGFloat = 20
    static let wordSpacing: CGFloat = 7
    private static let writeStart = 0.04
    private static let writeEnd = 0.8
    private static let finish = writeEnd + 0.02

    private static let sparkles = [
        GameHubSparkle(size: 12, color: .paeoniaInkGold, x: 0.09, y: 0.3),
        GameHubSparkle(size: 9, color: .paeoniaTextSecondary, x: 0.13, y: 0.76),
        GameHubSparkle(size: 14, color: .paeoniaTextPrimary, x: 0.91, y: 0.32),
        GameHubSparkle(size: 8, color: .paeoniaInkGold, x: 0.88, y: 0.8),
    ]

    var body: some View {
        ZStack {
            GameHubSparkleField(sparkles: Self.sparkles, progress: progress, start: Self.finish)
            pages
                // Clear of the chips at the top of the card and the fade into the card at the bottom.
                .padding(.top, PaeoniaSpacing.space24)
                .padding(.bottom, PaeoniaSpacing.space16)
        }
    }

    /// The page with the story, and a second page under it.
    private var pages: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
        return ZStack {
            shape
                .fill(.paeoniaSurfaceSecondary)
                .frame(width: Self.pageSize.width, height: Self.pageSize.height)
                .rotationEffect(.degrees(4))
                .offset(x: 8, y: 5)
            ZStack(alignment: .topLeading) {
                shape.fill(.paeoniaBackgroundPrimary)
                shape.fill(LinearGradient(
                    colors: [Color.paeoniaTextPrimary.opacity(0.07), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                StoryChainHubPaper()
                StoryChainHubWriting(progress: Self.writing(progress))
                flower
            }
            .frame(width: Self.pageSize.width, height: Self.pageSize.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault) }
        }
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.65), radius: 16, y: 10)
        .rotation3DEffect(.degrees(14), axis: (x: 1, y: -0.35, z: 0), perspective: 0.5)
        .rotationEffect(.degrees(-4))
    }

    /// The writing's own progress, from 0 to 1, inside its slice of the scene.
    private static func writing(_ progress: Double) -> Double {
        min(max((progress - writeStart) / (writeEnd - writeStart), 0), 1)
    }

    /// The flower after the last word, like the one that closes a finished story.
    private var flower: some View {
        let pop = Timing.pop(progress, from: Self.finish, to: Self.finish + 0.1)
        let end = StoryChainHubWriting.endOfStory
        return Image(systemName: "camera.macro")
            .accessibilityHidden(true)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.paeoniaAccentSecondary)
            .scaleEffect(max(0, pop))
            .rotationEffect(.degrees(-30 * (1 - pop)))
            .position(x: end.x + 14, y: end.y - 6)
    }
}

/// Ruled lines and a margin, like a page from a notebook.
private struct StoryChainHubPaper: View {
    var body: some View {
        Canvas { context, size in
            var rules = Path()
            var baseline = StoryChainHubScene.firstBaseline + 3
            while baseline < size.height {
                rules.move(to: CGPoint(x: 0, y: baseline))
                rules.addLine(to: CGPoint(x: size.width, y: baseline))
                baseline += StoryChainHubScene.rowHeight
            }
            context.stroke(rules, with: .color(.paeoniaTextPrimary.opacity(0.08)), lineWidth: 1)
            var margin = Path()
            margin.move(to: CGPoint(x: StoryChainHubScene.margin - 9, y: 0))
            margin.addLine(to: CGPoint(x: StoryChainHubScene.margin - 9, y: size.height))
            context.stroke(margin, with: .color(.paeoniaAccentPrimary.opacity(0.35)), lineWidth: 1)
        }
    }
}

/// The story as handwriting. Each word is a run of small arches with an odd tall
/// stroke, like letters joined in a quick hand. `progress` runs from 0 to 1 across all
/// of the words.
private struct StoryChainHubWriting: View {
    let progress: Double

    private struct Word {
        let width: CGFloat
        let isMine: Bool
        var isDared = false
    }

    private static func mine(_ width: CGFloat) -> Word {
        Word(width: width, isMine: true)
    }

    private static func partner(_ width: CGFloat, isDared: Bool = false) -> Word {
        Word(width: width, isMine: false, isDared: isDared)
    }

    /// Five rows of words. The ink changes where a sentence ends, as it does on the
    /// real page.
    private static let rows: [[Word]] = [
        [mine(34), mine(20), mine(44), mine(28), partner(32)],
        [partner(24), partner(42, isDared: true), partner(20), mine(36), mine(24)],
        [mine(40), mine(22), partner(34), partner(28), partner(26)],
        [partner(30), partner(44), mine(24), mine(38), mine(18)],
        [partner(36), partner(26), partner(30)],
    ]

    private static let totalWidth: CGFloat = rows.joined().reduce(0) { $0 + $1.width }

    /// Where the last word of the story ends, for the flower.
    static let endOfStory: CGPoint = {
        let row = rows.count - 1
        let spacing = StoryChainHubScene.wordSpacing * CGFloat(rows[row].count - 1)
        let width = rows[row].reduce(0) { $0 + $1.width } + spacing
        return CGPoint(
            x: StoryChainHubScene.margin + width,
            y: StoryChainHubScene.firstBaseline + StoryChainHubScene.rowHeight * CGFloat(row)
        )
    }()

    var body: some View {
        Canvas { context, _ in draw(in: &context) }
    }

    private func draw(in context: inout GraphicsContext) {
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        var written: CGFloat = 0
        var tip: (point: CGPoint, color: Color)?
        for (rowIndex, row) in Self.rows.enumerated() {
            let baseline = StoryChainHubScene.firstBaseline + StoryChainHubScene.rowHeight * CGFloat(rowIndex)
            var x = StoryChainHubScene.margin
            for (wordIndex, word) in row.enumerated() {
                let start = written / Self.totalWidth
                let amount = min(max((progress - start) / (word.width / Self.totalWidth), 0), 1)
                written += word.width
                defer { x += word.width + StoryChainHubScene.wordSpacing }
                guard amount > 0 else { continue }
                let ink = word.isMine ? StoryChainPageStyle.mineInk : StoryChainPageStyle.partnerInk
                let seed = rowIndex * 7 + wordIndex
                let path = Self.handwriting(x: x, baseline: baseline, width: word.width, seed: seed)
                    .trimmedPath(from: 0, to: amount)
                context.stroke(path, with: .color(ink), style: style)
                if word.isDared {
                    var underline = Path()
                    underline.move(to: CGPoint(x: x, y: baseline + 4))
                    underline.addLine(to: CGPoint(x: x + word.width * amount, y: baseline + 4))
                    context.stroke(
                        underline,
                        with: .color(.paeoniaInkGold),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                }
                if amount < 1, progress < 1, let point = path.currentPoint {
                    tip = (point, ink)
                }
            }
        }
        if let tip {
            let glow = CGRect(x: tip.point.x - 4, y: tip.point.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: glow), with: .color(tip.color.opacity(0.35)))
            let dot = CGRect(x: tip.point.x - 1.8, y: tip.point.y - 1.8, width: 3.6, height: 3.6)
            context.fill(Path(ellipseIn: dot), with: .color(tip.color))
        }
    }

    /// One word in a quick joined hand: small arches at x-height, with an odd tall
    /// loop for a letter like l or h. `seed` makes each word a little different.
    private static func handwriting(x: CGFloat, baseline: CGFloat, width: CGFloat, seed: Int) -> Path {
        let xHeight: CGFloat = 5
        let letter: CGFloat = 5
        let count = max(2, Int(width / letter))
        let step = width / CGFloat(count)
        var path = Path()
        path.move(to: CGPoint(x: x, y: baseline - 1))
        for index in 0..<count {
            let isTall = (index * 5 + seed * 3) % 7 == 2
            let wobble = 0.8 + 0.25 * sin(Double(index * 3 + seed))
            let height = xHeight * CGFloat(wobble) * (isTall ? 2.1 : 1)
            let left = x + step * CGFloat(index)
            // A tall letter goes up to the right and comes back down to the left of
            // where it went up, which crosses the stroke and makes a loop.
            path.addCurve(
                to: CGPoint(x: left + step, y: baseline),
                control1: CGPoint(x: left + step * (isTall ? 1.6 : 0.1), y: baseline - height * 1.3),
                control2: CGPoint(x: left - step * (isTall ? 0.7 : -0.6), y: baseline - height * 1.3)
            )
        }
        return path
    }
}

#if DEBUG
#Preview {
    StoryChainHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
