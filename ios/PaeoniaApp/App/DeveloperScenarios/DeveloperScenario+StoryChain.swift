#if DEBUG
  import SwiftUI

  /// Story Chain scenarios. The game opens in `DeveloperStoryChainScenarioView`
  /// and Our stories in `DeveloperStoryChainHistoryScenarioView`.
  nonisolated extension DeveloperScenario {
    static let storyChain: [DeveloperScenario] = [
      storyChainChoose, storyChainChooseOffline, storyChainWriting, storyChainWritingLast, storyChainWaitingLive,
      storyChainWaitingAway, storyChainSavedOffline, storyChainNaming, storyChainWaitingName, storyChainFinished,
      storyChainWaitingOpening, storyChainHistory, storyChainHistoryEmpty,
    ]

    static let storyChainChoose = storyChainGame(
      "story-chain-choose", "Story Chain · choose an opening",
      "Three opening lines and the choice to write your own first line"
    )
    static let storyChainChooseOffline = storyChainGame(
      "story-chain-choose-offline", "Story Chain · choose an opening, offline",
      "The offline message when no opening lines are on the phone. Your own first line still works"
    )
    static let storyChainWriting = storyChainGame(
      "story-chain-writing", "Story Chain · your turn to write",
      "Robin dared you to use LADDER and is reading along. The last-line switch is available"
    )
    static let storyChainWritingLast = storyChainGame(
      "story-chain-writing-last", "Story Chain · line 20, the last line",
      "Line 20 is always the last, so the switch is locked on. Robin dared you to use TUESDAY"
    )
    static let storyChainWaitingLive = storyChainGame(
      "story-chain-waiting-live", "Story Chain · Robin is typing live",
      "Robin types line 8 letter by letter with two corrections, sends it, and then your turn opens"
    )
    static let storyChainWaitingAway = storyChainGame(
      "story-chain-waiting-away", "Story Chain · waiting for Robin, who is away",
      "Robin has the turn and is not in the game. The page shows the hint and the invite button"
    )
    static let storyChainSavedOffline = storyChainGame(
      "story-chain-saved-offline", "Story Chain · line sent offline",
      "Your line is queued after a failed try, so the page says it is saved on this phone"
    )
    static let storyChainNaming = storyChainGame(
      "story-chain-naming", "Story Chain · name the story", "Robin wrote the last line and you give the story a title"
    )
    static let storyChainWaitingName = storyChainGame(
      "story-chain-waiting-name", "Story Chain · Robin is naming the story",
      "You wrote the last line and Robin is on the naming screen"
    )
    static let storyChainFinished = storyChainGame(
      "story-chain-finished", "Story Chain · the finished story",
      "Robin named your story and you have not seen it yet. The reveal plays, then Continue"
    )
    static let storyChainWaitingOpening = storyChainGame(
      "story-chain-waiting-opening", "Story Chain · Robin picks an opening",
      "The last story just ended and Robin is picking the next opening"
    )
    static let storyChainHistory = storyChainHistoryScreen(
      "story-chain-history", "Story Chain · our stories", "Three finished stories, two starred. Open one to read it"
    )
    static let storyChainHistoryEmpty = storyChainHistoryScreen(
      "story-chain-history-empty", "Story Chain · our stories, none yet",
      "Our stories before the first story has finished"
    )

    private static func storyChainGame(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperStoryChainScenarioView(scenario: $0) }
    }

    private static func storyChainHistoryScreen(
      _ id: String, _ title: String, _ detail: String
    ) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperStoryChainHistoryScenarioView(scenario: $0) }
    }
  }
#endif
