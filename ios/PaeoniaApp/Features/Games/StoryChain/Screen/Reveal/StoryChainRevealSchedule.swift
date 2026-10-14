import Foundation

/// When each beat of the finished-story reveal happens, in seconds after it starts.
nonisolated struct StoryChainRevealSchedule: Equatable, Sendable {
    /// The bottom fades out and the page scrolls to the top.
    var scrollTop: TimeInterval = 0.0
    /// The title starts to write itself in.
    var title: TimeInterval = 0.40
    /// How long the title takes to write itself in.
    var titleDuration: TimeInterval = StoryChainTitleTiming.totalDuration
    var byline: TimeInterval = 1.10
    /// The ornament scales in and the petals burst.
    var ornament: TimeInterval = 1.30
    /// The line count and the dare word count.
    var stats: TimeInterval = 1.80
    /// The star and the button.
    var actions: TimeInterval = 2.10

    static let standard = Self()
    /// Every beat at once, so tests run the whole script without waiting.
    static let instant = Self(
        scrollTop: 0, title: 0, titleDuration: 0, byline: 0, ornament: 0, stats: 0, actions: 0
    )
}

/// The haptics of the reveal, injected so tests can record them.
struct StoryChainRevealHaptics {
    var selection: @MainActor () -> Void
    var answerRevealed: @MainActor () -> Void

    static let live = Self(
        selection: { PaeoniaHaptics.selection() },
        answerRevealed: { PaeoniaHaptics.answerRevealed() }
    )
}

nonisolated enum StoryChainRevealEvent: Equatable, Sendable {
    case scrollTop
    case title
    case byline
    case ornament
    case stats
    case actions
}

nonisolated struct StoryChainRevealStep: Equatable, Sendable {
    let at: TimeInterval
    let event: StoryChainRevealEvent
}

/// The beats of the reveal, in order.
nonisolated enum StoryChainRevealScript {
    static func steps(schedule: StoryChainRevealSchedule) -> [StoryChainRevealStep] {
        let steps = [
            StoryChainRevealStep(at: schedule.scrollTop, event: .scrollTop),
            StoryChainRevealStep(at: schedule.title, event: .title),
            StoryChainRevealStep(at: schedule.byline, event: .byline),
            StoryChainRevealStep(at: schedule.ornament, event: .ornament),
            StoryChainRevealStep(at: schedule.stats, event: .stats),
            StoryChainRevealStep(at: schedule.actions, event: .actions),
        ]
        // Stable by time, so beats at the same moment keep the order above.
        return steps.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }
}
