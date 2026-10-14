import Foundation

/// One line of the story, written by one partner. The page draws it as part of
/// the paragraph.
nonisolated struct StoryChainPageLine: Identifiable, Equatable, Sendable {
    let id: UUID
    /// The place in the story, counted from 1. Paeonia's opening has no number.
    var number: Int
    var text: String
    var isMine: Bool
    /// The word this line had to use. The page underlines it in gold.
    var usedDare: String?
    var authorName: String
    var createdAt: Date
}

/// The partner's draft while they type. The page shows it after the last line,
/// faded, with a blinking caret.
nonisolated struct StoryChainGhost: Equatable, Sendable {
    var text: String
    /// The draft is set to be the last line of the story.
    var isLast: Bool
}

/// Everything the page needs to draw a story. The screen builds it from its own
/// models, so the page does not depend on the network types.
nonisolated struct StoryChainPageContent: Equatable, Sendable {
    /// Paeonia's opening line. It belongs to nobody and has no line number.
    var opening: String?
    var lines: [StoryChainPageLine]
    var ghost: StoryChainGhost?
    /// A line that writes itself in word by word. Set it when the line should
    /// start to appear, and clear it after `onArrivalFinished`.
    var arrivingLineID: UUID?
    /// The speed of the write-in. The partner's line uses `.partner`, and a line
    /// I just sent uses `.mine`.
    var arrivalPace: StoryChainArrivalTiming = .partner
}
