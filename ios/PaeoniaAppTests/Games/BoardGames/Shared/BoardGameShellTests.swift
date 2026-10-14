import Foundation
import SwiftUI
import Testing
@testable import PaeoniaApp

/// The decisions behind the shared board game shell: the stake text, the
/// glow, the counts on the result panel and the wide layout.
@MainActor
struct BoardGameShellTests {
    // MARK: Stake

    @Test func stakeUnderTheLimitStaysAsTyped() {
        let clamped = BoardGameStake.clamp("Loser makes coffee")
        #expect(clamped.text == "Loser makes coffee")
        #expect(!clamped.didOverflow)
    }

    @Test func stakeIsCutAtSixtyCharacters() {
        let clamped = BoardGameStake.clamp(String(repeating: "a", count: 75))
        #expect(clamped.text == String(repeating: "a", count: 60))
        #expect(clamped.didOverflow)
    }

    @Test func stakeOfExactlySixtyCharactersIsNotAnOverflow() {
        let clamped = BoardGameStake.clamp(String(repeating: "a", count: 60))
        #expect(BoardGameStake.length(of: clamped.text) == 60)
        #expect(!clamped.didOverflow)
    }

    @Test func stakeLosesLineBreaksAndKeepsTheRest() {
        let clamped = BoardGameStake.clamp("Loser\nmakes\r\ncoffee")
        #expect(clamped.text == "Losermakescoffee")
        #expect(!clamped.didOverflow)
    }

    @Test func stakeCountsUnicodeScalarsLikeTheServer() {
        // One family emoji is one character on screen and seven Unicode scalars.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let clamped = BoardGameStake.clamp(String(repeating: family, count: 10))
        #expect(BoardGameStake.length(of: clamped.text) == 56)
        #expect(clamped.text.count == 8)
        #expect(clamped.didOverflow)
    }

    @Test func committedStakeLosesSpacesAndBlankMeansNone() {
        #expect(BoardGameStake.committed("  Loser makes coffee \n") == "Loser makes coffee")
        #expect(BoardGameStake.committed("   \n ") == nil)
        #expect(BoardGameStake.committed("") == nil)
    }

    // MARK: Glow

    @Test func onlyTheActivePlayerGlows() {
        #expect(BoardGameTurnLabel.yourTurn.glowState(forMe: true) == .breathing)
        #expect(BoardGameTurnLabel.yourTurn.glowState(forMe: false) == .resting)
        #expect(BoardGameTurnLabel.partnerTurn.glowState(forMe: true) == .resting)
        #expect(BoardGameTurnLabel.partnerTurn.glowState(forMe: false) == .breathing)
    }

    @Test func theWinnersGlowStaysLitAndADrawLightsNone() {
        #expect(BoardGameTurnLabel.youWon.glowState(forMe: true) == .steady)
        #expect(BoardGameTurnLabel.youWon.glowState(forMe: false) == .resting)
        #expect(BoardGameTurnLabel.partnerWon.glowState(forMe: false) == .steady)
        #expect(BoardGameTurnLabel.partnerWon.glowState(forMe: true) == .resting)
        #expect(BoardGameTurnLabel.draw.glowState(forMe: true) == .resting)
        #expect(BoardGameTurnLabel.draw.glowState(forMe: false) == .resting)
        // VoiceOver reads the turn on the lit avatar, so a draw has nothing to read.
        #expect(BoardGameTurnLabel.draw.spoken(partnerName: "Robin") == nil)
        #expect(BoardGameTurnLabel.yourTurn.spoken(partnerName: "Robin") != nil)
    }

    @Test func glowPulseStartsDimPeaksHalfwayAndRepeats() {
        let period = BoardGameGlowPulse.period
        #expect(abs(BoardGameGlowPulse.opacity(at: 0) - BoardGameGlowPulse.low) < 0.0001)
        #expect(abs(BoardGameGlowPulse.opacity(at: period / 2) - BoardGameGlowPulse.high) < 0.0001)
        #expect(abs(BoardGameGlowPulse.opacity(at: period) - BoardGameGlowPulse.low) < 0.0001)
        #expect(abs(BoardGameGlowPulse.opacity(at: 5 * period + 0.3) - BoardGameGlowPulse.opacity(at: 0.3)) < 0.0001)
    }

    @Test func glowPulseStaysBetweenItsBounds() {
        for step in 0..<100 {
            let opacity = BoardGameGlowPulse.opacity(at: Double(step) * 0.07)
            #expect(opacity >= BoardGameGlowPulse.low - 0.0001)
            #expect(opacity <= BoardGameGlowPulse.high + 0.0001)
        }
    }

    // MARK: Result counts

    private func result(
        winner: BoardGameWinner,
        playStyle: GamePlayStyle = .against,
        myWins: Int = 4,
        partnerWins: Int = 3,
        gamesFinished: Int = 13
    ) -> BoardGameResultContent {
        BoardGameResultContent(
            winner: winner,
            playStyle: playStyle,
            stake: nil,
            myWins: myWins,
            partnerWins: partnerWins,
            gamesFinished: gamesFinished,
            isMissedEnding: false
        )
    }

    @Test func myWinsCountUpWhenIWon() {
        let content = result(winner: .me)
        #expect(content.myCount == BoardGameCount(before: 3, after: 4))
        #expect(content.partnerCount == BoardGameCount(before: 3, after: 3))
        #expect(content.countsUp)
    }

    @Test func partnersWinsCountUpWhenTheyWon() {
        let content = result(winner: .partner)
        #expect(content.myCount == BoardGameCount(before: 4, after: 4))
        #expect(content.partnerCount == BoardGameCount(before: 2, after: 3))
    }

    @Test func aDrawAgainstEachOtherCountsNothing() {
        let content = result(winner: .draw)
        #expect(content.myCount.added == 0)
        #expect(content.partnerCount.added == 0)
        #expect(!content.countsUp)
    }

    @Test func aFirstWinCountsFromZero() {
        let content = result(winner: .me, myWins: 1, partnerWins: 0)
        #expect(content.myCount == BoardGameCount(before: 0, after: 1))
    }

    @Test func togetherCountsTheCouplesGamesEvenAfterADraw() {
        let content = result(winner: .draw, playStyle: .together)
        #expect(content.gamesCount == BoardGameCount(before: 12, after: 13))
        #expect(content.countsUp)
        #expect(content.score == .together(games: 13))
    }

    @Test func againstEachOtherScoreIsTheTalliesAfterTheGame() {
        let content = result(winner: .me)
        #expect(content.score == .against(mine: 4, partner: 3))
    }

    // MARK: Layout

    @Test func wideNeedsSevenHundredPointsAndALandscapeShape() {
        #expect(BoardGameMetrics.isWide(CGSize(width: 844, height: 390)))
        #expect(BoardGameMetrics.isWide(CGSize(width: 700, height: 699)))
        #expect(!BoardGameMetrics.isWide(CGSize(width: 699, height: 400)))
        #expect(!BoardGameMetrics.isWide(CGSize(width: 800, height: 900)))
        #expect(!BoardGameMetrics.isWide(CGSize(width: 700, height: 700)))
    }

    @Test func wideBoardNeverPassesItsCapOrTheScreenHeight() {
        let tabletLandscape = CGSize(width: 1_366, height: 1_024)
        #expect(BoardGameMetrics.wideBoardSide(in: tabletLandscape) == BoardGameMetrics.maxWideBoard)
        // 1024 wide leaves 532 beside the 420 point column, the gap and the padding.
        #expect(BoardGameMetrics.wideBoardSide(in: CGSize(width: 1_024, height: 768)) == 532)
        // A landscape phone is limited by its height less 24 points above and below.
        #expect(BoardGameMetrics.wideBoardSide(in: CGSize(width: 844, height: 390)) == 342)
    }
}
