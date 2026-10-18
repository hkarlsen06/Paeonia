import Foundation

/// When each beat of the finished-story reveal happens, in seconds after it starts.
nonisolated struct StoryChainRevealSchedule: Equatable, Sendable {
    /// The bottom fades out and the page scrolls to the top.
    var scrollTop: TimeInterval = 0.0
    /// The title starts to write itself in, once the page has scrolled up.
    var title: TimeInterval = 0.50
    /// How long the title takes to write itself in.
    var titleDuration: TimeInterval = StoryChainTitleTiming.totalDuration
    /// The last letter of the title lands: the petals burst from it with the
    /// success haptic.
    var bloom: TimeInterval = 1.20
    /// The byline signs the title once the petals have spread off it.
    var byline: TimeInterval = 1.55
    /// The flower at the end of the story scales in, without a sound. A long
    /// story's end is off screen at this point.
    var ornament: TimeInterval = 1.60
    /// The line count and the dare word count.
    var stats: TimeInterval = 1.75
    /// The star and the button.
    var actions: TimeInterval = 1.85

    static let standard = Self()
    /// Every beat at once, so tests run the whole script without waiting.
    static let instant = Self(
        scrollTop: 0, title: 0, titleDuration: 0, bloom: 0, byline: 0, ornament: 0, stats: 0, actions: 0
    )
}

/// The haptics and sounds of the reveal, injected so tests can record them.
struct StoryChainRevealHaptics {
    var selection: @MainActor () -> Void
    var answerRevealed: @MainActor () -> Void

    static let live = Self(
        selection: {
            PaeoniaHaptics.selection()
            GameSound.page.play()
        },
        answerRevealed: {
            PaeoniaHaptics.answerRevealed()
            GameSound.chime.play()
        }
    )
}

nonisolated enum StoryChainRevealEvent: Equatable, Sendable {
    case scrollTop
    case title
    case bloom
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
            StoryChainRevealStep(at: schedule.bloom, event: .bloom),
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
