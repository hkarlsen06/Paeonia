import Foundation

/// A row on the "Things to try together" card that Home shows after the first day. The
/// order here is the order of the rows.
nonisolated enum HomeFirstStep: String, Codable, CaseIterable, Sendable {
    /// Either partner opened a game.
    case game
    /// This person saved a memory.
    case memory
    /// The couple has a countdown.
    case countdown
    /// This person posted a story.
    case story
    /// This person answered a question in a topic.
    case topic
}

/// What this phone remembers about one pair's card. A row stays ticked once it was seen
/// done, so deleting the memory or skipping the topic question later does not untick it.
nonisolated struct HomeFirstStepsProgress: Codable, Equatable, Sendable {
    var doneSteps: Set<HomeFirstStep> = []
    /// The person closed the card. It never shows again for this pair.
    var isClosed = false
}

/// The card's rows as Home shows them.
nonisolated struct HomeFirstSteps: Equatable, Sendable {
    let doneSteps: Set<HomeFirstStep>

    var doneCount: Int { doneSteps.count }
    var totalCount: Int { HomeFirstStep.allCases.count }

    func isDone(_ step: HomeFirstStep) -> Bool {
        doneSteps.contains(step)
    }

    /// The card for a pair, or nil when Home hides it: no saved progress (the first day is
    /// not over), closed, every row done, or a row whose state has not loaded yet.
    /// `observed` holds a row once the app has loaded what it needs to know, true when done.
    /// Waiting for every row keeps a done row from showing as not done first.
    static func card(progress: HomeFirstStepsProgress?, observed: [HomeFirstStep: Bool]) -> HomeFirstSteps? {
        guard let progress, !progress.isClosed else { return nil }
        var done = progress.doneSteps
        for step in HomeFirstStep.allCases where !done.contains(step) {
            guard let isDone = observed[step] else { return nil }
            if isDone { done.insert(step) }
        }
        guard done.count < HomeFirstStep.allCases.count else { return nil }
        return HomeFirstSteps(doneSteps: done)
    }
}
