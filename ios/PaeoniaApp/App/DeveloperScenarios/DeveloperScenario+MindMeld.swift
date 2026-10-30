#if DEBUG
  import SwiftUI

  /// Mind Meld scenarios. Each one opens in `DeveloperMindMeldScenarioView`.
  nonisolated extension DeveloperScenario {
    static let mindMeld: [DeveloperScenario] = [
      mindMeldFirstRound, mindMeldWrite, mindMeldWriteAway, mindMeldWriteTyping,
      mindMeldWaiting, mindMeldWaitingOffline,
      mindMeldRevealMiss, mindMeldRevealNear, mindMeldRevealMeld, mindMeldRevealRecord, mindMeldRevealGotAway,
      mindMeldOver, mindMeldPartnerRestarted, mindMeldHistory, mindMeldHistoryEmpty,
    ]

    static let mindMeldFirstRound = mindMeldScreen(
      "mind-meld-first-round", "Mind Meld · first round",
      "Round 1 of a new couple: nobody has locked in and Robin is away, so the invite button shows"
    )
    static let mindMeldWrite = mindMeldScreen(
      "mind-meld-write", "Mind Meld · write, partner locked in",
      "Round 4 with three earlier pairs above the field. Robin is here and has locked in"
    )
    static let mindMeldWriteAway = mindMeldScreen(
      "mind-meld-write-away", "Mind Meld · partner locked in, away",
      "Robin locked in a word and left. The locked wording stays, with no presence ring and an available invite"
    )
    static let mindMeldWriteTyping = mindMeldScreen(
      "mind-meld-write-typing", "Mind Meld · write, partner typing",
      "Round 2 with Robin here and typing. The dots repeat until the screen closes"
    )
    static let mindMeldWaiting = mindMeldScreen(
      "mind-meld-waiting", "Mind Meld · waiting for partner",
      "Your word is locked in for round 3 and Robin is here, typing"
    )
    static let mindMeldWaitingOffline = mindMeldScreen(
      "mind-meld-waiting-offline", "Mind Meld · waiting, saved on the phone",
      "Your word is only queued on the phone and a send failed: saved on this phone, sent later"
    )
    static let mindMeldRevealMiss = mindMeldScreen(
      "mind-meld-reveal-miss", "Mind Meld · reveal, miss",
      "Round 3 revealed with two different words. The button reads Next round"
    )
    static let mindMeldRevealNear = mindMeldScreen(
      "mind-meld-reveal-near", "Mind Meld · reveal, so close",
      "Round 3 is a near miss: So close, with Count it on offer"
    )
    static let mindMeldRevealMeld = mindMeldScreen(
      "mind-meld-reveal-meld", "Mind Meld · reveal, meld", "Round 4 melds. Meld number 3, not a record"
    )
    static let mindMeldRevealRecord = mindMeldScreen(
      "mind-meld-reveal-record", "Mind Meld · reveal, record meld",
      "A meld in round 2 that beats the couple's fewest rounds"
    )
    static let mindMeldRevealGotAway = mindMeldScreen(
      "mind-meld-reveal-got-away", "Mind Meld · reveal, got away", "Round 10 without a match: This one got away"
    )
    static let mindMeldOver = mindMeldScreen(
      "mind-meld-over", "Mind Meld · game over",
      "A melded game whose reveal and ending you have seen: settled, with Play again"
    )
    static let mindMeldPartnerRestarted = mindMeldScreen(
      "mind-meld-partner-restarted", "Mind Meld · partner started over",
      "Robin ended the last game with Start over. Round 1 of the new game shows a note"
    )
    static let mindMeldHistory = mindMeldScreen(
      "mind-meld-history", "Mind Meld · our melds",
      "Records and five finished games: three melds, one got away, one started over. Open one for its trail"
    )
    static let mindMeldHistoryEmpty = mindMeldScreen(
      "mind-meld-history-empty", "Mind Meld · our melds, none yet", "Our melds before the first game has finished"
    )

    private static func mindMeldScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperMindMeldScenarioView(scenario: $0) }
    }
  }
#endif
