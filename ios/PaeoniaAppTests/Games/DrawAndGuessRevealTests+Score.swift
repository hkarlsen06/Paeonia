import Foundation
import Testing
@testable import PaeoniaApp

/// The score panel the reveal shows after the animation.
@MainActor
struct DrawAndGuessRevealScoreTests {
    private func reveal(
        outcome: DrawAndGuessReveal.Outcome = .iSolvedIt,
        bonus: Int = 1,
        firstTry: Int = 0,
        isConfirmed: Bool = true
    ) -> DrawAndGuessReveal {
        let solved = outcome == .iSolvedIt || outcome == .partnerSolvedIt
        return DrawAndGuessReveal(
            outcome: outcome,
            word: "umbrella",
            wordPoints: 2,
            speedBonus: bonus,
            firstTryBonus: firstTry,
            pointsForMe: solved ? 2 + (outcome == .iSolvedIt ? bonus + firstTry : 0) : 0,
            attempts: [],
            isConfirmed: isConfirmed
        )
    }

    @Test func theGuesserGetsTheWordAndTheBonusAndTheDrawerGetsTheWord() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: true
        ))

        guard case let .against(mine, partner) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(mine.before == 5 && mine.after == 8)
        #expect(partner.before == 3 && partner.after == 5)
        #expect(!score.isEstimate)
        #expect(score.largestGain == 3)
    }

    @Test func theDrawerSeesTheBonusInThePartnersColumn() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(outcome: .partnerSolvedIt),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: false
        ))

        guard case let .against(mine, partner) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(mine.added == 2)
        #expect(partner.added == 3)
    }

    @Test func togetherCountsTheCouplesTotalByTheWordOnly() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(),
            score: .together(total: 13),
            iAmGuesser: true
        ))

        guard case let .together(column) = score.style else {
            Issue.record("Expected the together style")
            return
        }
        #expect(column.before == 11 && column.after == 13)
    }

    @Test func theFirstTryBonusGoesToTheGuessersColumnOnly() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(bonus: 2, firstTry: 1),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: true
        ))

        guard case let .against(mine, partner) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(mine.before == 3 && mine.after == 8)
        // The drawer gets the word's points only.
        #expect(partner.added == 2)
    }

    @Test func aResultOnlyOnThePhoneAddsToTheTotalsWithTheBonusesThePhonePromised() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(bonus: 2, firstTry: 1, isConfirmed: false),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: true
        ))

        guard case let .against(mine, _) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(score.isEstimate)
        #expect(mine.before == 8 && mine.after == 13)
    }

    @Test func aMissedRoundHasNoScorePanel() {
        let missed = reveal(outcome: .iGaveUp, bonus: 0)

        #expect(DrawAndGuessRevealScore.make(reveal: missed, score: .together(total: 3), iAmGuesser: true) == nil)
    }
}
