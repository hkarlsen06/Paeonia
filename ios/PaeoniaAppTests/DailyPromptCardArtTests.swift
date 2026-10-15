import Foundation
import Testing
@testable import PaeoniaApp

struct DailyPromptCardArtTests {
    private func state(
        _ kind: DailyChallengeCardState.Kind,
        answered: Int = 0,
        total: Int = 2,
        partnerAnswered: Bool = false
    ) -> DailyChallengeCardState {
        DailyChallengeCardState(
            kind: kind,
            answeredCount: answered,
            totalCount: total,
            hasPartnerAnswersForToday: partnerAnswered
        )
    }

    @Test func heroShapeWhileThereIsSomethingToDoOrLoading() {
        #expect(DailyPromptCardArt(state(.loading)).shape == .hero)
        #expect(DailyPromptCardArt(state(.noChallenge, total: 0)).shape == .hero)
        #expect(DailyPromptCardArt(state(.active(prompt: "Q"))).shape == .hero)
    }

    @Test func compactShapeOnceComplete() {
        #expect(DailyPromptCardArt(state(.complete, answered: 2)).shape == .compact)
    }

    @Test func sealTakesThePartnersColorOnceTheyHaveAnswered() {
        #expect(DailyPromptCardArt(state(.active(prompt: "Q"))).seal == .pink)
        #expect(DailyPromptCardArt(state(.active(prompt: "Q"), partnerAnswered: true)).seal == .lavender)
        let waitingQuestion = DailyChallengeCardState(
            kind: .noChallenge,
            answeredCount: 0,
            totalCount: 0,
            hasAnswerablePartnerQuestions: true
        )
        #expect(DailyPromptCardArt(waitingQuestion).seal == .lavender)
    }

    @Test func glowsOnlyWhileThereIsSomethingToDo() {
        #expect(DailyPromptCardArt(state(.active(prompt: "Q"))).glows)
        #expect(DailyPromptCardArt(state(.noChallenge, total: 0)).glows)
        #expect(!DailyPromptCardArt(state(.loading)).glows)
        #expect(!DailyPromptCardArt(state(.complete, answered: 2)).glows)
    }

    @Test func progressBadgeOnlyForActiveQuestions() {
        #expect(DailyPromptCardArt(state(.active(prompt: "Q"), answered: 1)).showsProgressBadge)
        #expect(!DailyPromptCardArt(state(.active(prompt: "Q"), total: 0)).showsProgressBadge)
        #expect(!DailyPromptCardArt(state(.loading)).showsProgressBadge)
        #expect(!DailyPromptCardArt(state(.noChallenge, total: 0)).showsProgressBadge)
        #expect(!DailyPromptCardArt(state(.complete, answered: 2)).showsProgressBadge)
    }

    // MARK: Hold

    @Test func holdKeepsTheActivePictureAfterTheLastAnswer() {
        var hold = DailyPromptCardHold()
        let active = state(.active(prompt: "Q"), answered: 1)
        hold.observe(active)
        let complete = state(.complete, answered: 2)
        hold.observe(complete)

        #expect(hold.isHolding(for: complete))
        let shown = hold.shownState(for: complete)
        #expect(shown.kind == .active(prompt: "Q"))
        #expect(shown.answeredCount == 2)
        #expect(DailyPromptCardArt(shown).shape == .hero)
    }

    @Test func releaseShowsTheCompleteState() {
        var hold = DailyPromptCardHold()
        hold.observe(state(.active(prompt: "Q"), answered: 1))
        let complete = state(.complete, answered: 2)
        hold.observe(complete)
        hold.release()

        #expect(!hold.isHolding(for: complete))
        #expect(hold.shownState(for: complete) == complete)
    }

    @Test func noHoldWhenTheCardFirstShowsComplete() {
        var hold = DailyPromptCardHold()
        let complete = state(.complete, answered: 2)
        hold.observe(state(.loading))
        hold.observe(complete)

        #expect(!hold.isHolding(for: complete))
        #expect(hold.shownState(for: complete) == complete)
    }

    @Test func newDayDropsTheHold() {
        var hold = DailyPromptCardHold()
        hold.observe(state(.active(prompt: "Q"), answered: 1))
        hold.observe(state(.noChallenge, total: 0))
        let complete = state(.complete, answered: 2)

        #expect(!hold.isHolding(for: complete))
    }

    @Test func noHoldWhileTheStateIsNotComplete() {
        var hold = DailyPromptCardHold()
        let active = state(.active(prompt: "Q"))
        hold.observe(active)

        #expect(!hold.isHolding(for: active))
        #expect(hold.shownState(for: active) == active)
    }
}
