import CoreGraphics
import Foundation

/// When each word of an arriving line appears. Pure, so tests read the numbers.
///
/// A word rises and sharpens over `wordDuration`, and the words start `wordGap`
/// apart. A long line compresses the gap so the whole line takes at most
/// `maxTotal` seconds.
nonisolated struct StoryChainArrivalTiming: Equatable, Sendable {
    var wordDuration: TimeInterval = 0.35
    var wordGap: TimeInterval = 0.045
    var maxTotal: TimeInterval = 1.6
    /// How far below its place a word starts, in points.
    var rise: CGFloat = 4
    /// How blurred a word starts, in points.
    var blur: CGFloat = 6
    /// The fade under Reduce Motion. The page sets it to `PaeoniaMotion.motionDefault`.
    var fadeDuration: TimeInterval = 0.24

    /// A line the partner wrote.
    static let partner = Self()
    /// A line I just sent, a little faster.
    static let mine = Self(wordGap: 0.030)

    /// The time between two word starts, compressed for long lines.
    func gap(wordCount: Int) -> TimeInterval {
        guard wordCount > 1 else { return 0 }
        let room = (maxTotal - wordDuration) / Double(wordCount - 1)
        return max(0, min(wordGap, room))
    }

    /// How long the whole line takes.
    func totalDuration(wordCount: Int, reduceMotion: Bool = false) -> TimeInterval {
        guard wordCount > 0 else { return 0 }
        if reduceMotion { return fadeDuration }
        return wordDuration + gap(wordCount: wordCount) * Double(wordCount - 1)
    }

    /// How far one word has come, from 0 (hidden) to 1 (sharp), eased out.
    func progress(wordIndex: Int, wordCount: Int, elapsed: TimeInterval) -> Double {
        guard wordCount > 0 else { return 1 }
        let index = min(max(wordIndex, 0), wordCount - 1)
        let start = gap(wordCount: wordCount) * Double(index)
        let linear = min(max((elapsed - start) / wordDuration, 0), 1)
        return 1 - pow(1 - linear, 3)
    }

    /// How far the whole line has faded in under Reduce Motion.
    func fadeProgress(elapsed: TimeInterval) -> Double {
        guard fadeDuration > 0 else { return 1 }
        return min(max(elapsed / fadeDuration, 0), 1)
    }
}
