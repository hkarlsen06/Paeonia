import Foundation
import SwiftUI
import Testing
@testable import PaeoniaApp

/// The stake text rules the shared board game shell applies.
@MainActor
struct BoardGameShellTests {
    // MARK: Stake

    @Test func stakeIsCutAtSixtyCharacters() {
        let clamped = BoardGameStake.clamp(String(repeating: "a", count: 75))
        #expect(clamped.text == String(repeating: "a", count: 60))
        #expect(clamped.didOverflow)
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
}
