import SwiftUI

/// Keys the card's load. The card shows only once the games and topics have loaded,
/// which wait for the cold-launch intro, so its own reads wait for it too.
private struct FirstStepsLoadKey: Hashable {
    var pairID: UUID?
    var userID: UUID?
    var introComplete: Bool
}

/// Home's "Things to try together" card after the first day: which rows are done, read
/// from the tabs' own view models, and where each row goes.
extension MainTabView {
    /// The card Home shows, or nil to hide it.
    var firstSteps: HomeFirstSteps? {
        HomeFirstSteps.card(progress: firstStepsModel.progress, observed: observedFirstSteps)
    }

    /// Loads the pair's saved card and ticks each row for good the first time it is seen done.
    func followingFirstSteps(on content: some View) -> some View {
        content
            .task(id: firstStepsLoadKey) {
                guard firstStepsLoadKey.introComplete else { return }
                await firstStepsModel.load(pairID: identity.pairID, ownerUserID: identity.currentUserID)
            }
            .onChange(of: observedDoneFirstSteps, initial: true) { _, doneSteps in
                firstStepsModel.record(doneSteps)
            }
    }

    func openFirstStep(_ step: HomeFirstStep) {
        switch step {
        case .game:
            selection.wrappedValue = .games
        case .memory:
            selection.wrappedValue = .memories
        case .countdown:
            // What a date reminder opens: the timeline, where the person adds a countdown.
            coupleDatesViewModel.requestTimeline()
        case .story:
            storiesViewModel.requestComposer()
        case .topic:
            openTopics()
        }
    }

    func closeFirstSteps() {
        firstStepsModel.close()
    }

    private var firstStepsLoadKey: FirstStepsLoadKey {
        FirstStepsLoadKey(
            pairID: identity.pairID,
            userID: identity.currentUserID,
            introComplete: launchIntroComplete
        )
    }

    /// Empty until the saved card has loaded, so rows already done when it loads change
    /// this value and get saved.
    private var observedDoneFirstSteps: Set<HomeFirstStep> {
        guard firstStepsModel.progress != nil else { return [] }
        return Set(observedFirstSteps.filter(\.value).keys)
    }

    /// Each row whose view model has loaded, true when it is done. A row still loading is
    /// left out, so the card waits for it.
    private var observedFirstSteps: [HomeFirstStep: Bool] {
        var observed: [HomeFirstStep: Bool] = [:]
        if gamesViewModel.screen == .hub {
            observed[.game] = !gamesViewModel.lastPlayed.isEmpty
        }
        if let hasOwnMemory = firstStepsModel.hasOwnMemory {
            observed[.memory] = hasOwnMemory
        }
        if coupleDatesViewModel.hasLoaded {
            observed[.countdown] = !coupleDatesViewModel.dates.countdowns.isEmpty
        }
        if storiesViewModel.hasLoaded, let userID = identity.currentUserID {
            observed[.story] = storiesViewModel.stories.contains { $0.authorUserID == userID }
        }
        if topicsViewModel.hasLoadedOverview {
            // Counted for this person: a question in "waiting for partner" or "together" has their answer.
            observed[.topic] = topicsViewModel.overview.contains { $0.waitingForPartnerCount + $0.togetherCount > 0 }
        }
        return observed
    }
}
