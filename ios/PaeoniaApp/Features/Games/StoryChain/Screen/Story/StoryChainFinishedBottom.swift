import SwiftUI

/// The end of a finished story: the flower, then how long the story is. Both
/// appear on the reveal's schedule (see `StoryChainRevealTimeline`). They take
/// their place from the start, so nothing jumps when they fade in.
struct StoryChainFinishedBottom: View {
    let finished: StoryChainFinishedStory
    let reveal: StoryChainRevealTimeline
    /// The server knows the story is finished, so it takes a reaction. A title still queued on
    /// this phone leaves the story unfinished there.
    var canReact = true

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            StoryChainOrnament(isShown: reveal.ornamentShown)
            StoryChainStatsLine(lineCount: finished.lineCount, dareCount: finished.dareCount)
                .opacity(reveal.statsShown ? 1 : 0)
                .offset(y: reveal.statsShown ? 0 : PaeoniaSpacing.space8)
            if reveal.statsShown, canReact {
                ReactionSection(target: .storyChainStory(finished.storyID), alignment: .center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("storyChain.finished")
    }
}

/// "14 lines" and, when dare words were used, "3 dare words".
struct StoryChainStatsLine: View {
    let lineCount: Int
    let dareCount: Int

    var body: some View {
        Text(verbatim: parts.joined(separator: " \u{00B7} "))
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("storyChain.stats")
    }

    private var parts: [String] {
        var parts = [String(localized: .storyChainFinishedLines(lineCount))]
        if dareCount > 0 {
            parts.append(String(localized: .storyChainFinishedDares(dareCount)))
        }
        return parts
    }
}
