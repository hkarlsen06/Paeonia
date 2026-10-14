import SwiftUI

/// When each letter of the title appears. Pure, so tests read the numbers.
///
/// Letters start 30 ms apart and each one sharpens over 0.25 s. A long title
/// compresses the gap so the last letter starts within `maxSpan`.
nonisolated enum StoryChainTitleTiming {
    static let letterGap: TimeInterval = 0.030
    static let letterDuration: TimeInterval = 0.25
    static let maxSpan: TimeInterval = 0.5
    /// The time `progress` 1 stands for, long enough for the longest title.
    static let totalDuration: TimeInterval = maxSpan + letterDuration
    /// The most the blur of a letter that is still arriving reaches, in points.
    static let blur: CGFloat = 8

    /// The time between two letter starts.
    static func gap(letterCount: Int) -> TimeInterval {
        guard letterCount > 1 else { return 0 }
        return min(letterGap, maxSpan / Double(letterCount - 1))
    }

    /// How far one letter has come, from 0 (hidden) to 1 (sharp).
    static func letterProgress(index: Int, letterCount: Int, elapsed: TimeInterval) -> Double {
        guard letterCount > 0 else { return 1 }
        let start = gap(letterCount: letterCount) * Double(max(index, 0))
        let linear = min(max((elapsed - start) / letterDuration, 0), 1)
        return 1 - pow(1 - linear, 2)
    }

    /// The elapsed time that a progress value from 0 to 1 stands for.
    static func elapsed(forProgress progress: Double) -> TimeInterval {
        min(max(progress, 0), 1) * totalDuration
    }
}

/// Draws the title letter by letter, from blur to sharp. `progress` runs from 0
/// to 1, and the timeline moves it with a linear animation.
nonisolated struct StoryChainTitleRenderer: TextRenderer {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Room for the blur of a letter that is still arriving.
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var letters: [Text.Layout.RunSlice] = []
        for line in layout {
            for run in line {
                letters.append(contentsOf: run)
            }
        }
        let elapsed = StoryChainTitleTiming.elapsed(forProgress: progress)
        for (index, letter) in letters.enumerated() {
            let reached = StoryChainTitleTiming.letterProgress(
                index: index,
                letterCount: letters.count,
                elapsed: elapsed
            )
            guard reached > 0 else { continue }
            // Close enough to sharp counts as sharp, so a finished title is not layered.
            guard reached < 0.999 else {
                ctx.draw(letter)
                continue
            }
            var faded = ctx
            faded.opacity = reached
            faded.addFilter(.blur(radius: StoryChainTitleTiming.blur * (1 - reached)))
            faded.draw(letter)
        }
    }
}

/// The name of a finished story, in the serif, centered. It writes itself in
/// letter by letter as `progress` goes from 0 to 1. The title takes its place on
/// the page from the start, so nothing jumps when it appears.
struct StoryChainTitleText: View {
    let title: String
    /// How much of the title has written itself in, from 0 to 1.
    var progress: Double = 1

    var body: some View {
        Text(verbatim: title)
            .font(StoryChainPageStyle.titleFont)
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .textRenderer(StoryChainTitleRenderer(progress: progress))
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview {
    StoryChainTitleText(title: "The lighthouse that moved")
        .padding()
        .background(.paeoniaBackgroundSecondary)
}
#endif
