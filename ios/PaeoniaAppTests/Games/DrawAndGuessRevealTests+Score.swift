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
        isConfirmed: Bool = true,
        duration: TimeInterval? = 18
    ) -> DrawAndGuessReveal {
        let solved = outcome == .iSolvedIt || outcome == .partnerSolvedIt
        return DrawAndGuessReveal(
            outcome: outcome,
            word: "umbrella",
            difficulty: .medium,
            wordPoints: 2,
            speedBonus: bonus,
            firstTryBonus: firstTry,
            hintsUsed: 0,
            personalBest: false,
            solveDuration: duration,
            pointsForMe: solved ? 2 + (outcome == .iSolvedIt ? bonus + firstTry : 0) : 0,
            pointsForCouple: solved ? 2 : 0,
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
        #expect(mine.lines.map(\.kind) == [.word, .speedBonus])
        #expect(partner.before == 3 && partner.after == 5)
        #expect(partner.lines.map(\.kind) == [.drawing])
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
        #expect(mine.added == 2 && mine.lines.map(\.kind) == [.drawing])
        #expect(partner.added == 3 && partner.lines.map(\.kind) == [.word, .speedBonus])
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

    @Test func theFirstTryBonusAddsItsOwnLineToTheGuessersColumnOnly() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(bonus: 2, firstTry: 1),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: true
        ))

        guard case let .against(mine, partner) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(mine.lines.map(\.kind) == [.word, .speedBonus, .firstTry])
        #expect(mine.lines.map(\.points) == [2, 2, 1])
        #expect(mine.before == 3 && mine.after == 8)
        // The drawer gets the word's points only.
        #expect(partner.lines.map(\.kind) == [.drawing])
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
        #expect(mine.lines.map(\.kind) == [.word, .speedBonus, .firstTry])
    }

    @Test func aMissedRoundHasNoScorePanel() {
        let missed = reveal(outcome: .iGaveUp, bonus: 0)

        #expect(DrawAndGuessRevealScore.make(reveal: missed, score: .together(total: 3), iAmGuesser: true) == nil)
    }
}
