#if DEBUG
  import Foundation
  import SwiftUI

  /// Finished rounds and records for the "Our drawings" scenarios. Alex is the
  /// signed-in person and Robin is the partner. Every round holds the fixture
  /// umbrella, which the scenario's drawing store already has.
  nonisolated extension DeveloperGamesFixture {
    nonisolated private struct HistoryEntry {
      let word: String
      let drawerIsMe: Bool
      let solveMs: Int?
      let tries: Int
    }

    private static let historyWords = [
      HistoryEntry(word: "umbrella", drawerIsMe: false, solveMs: 18_400, tries: 3),
      HistoryEntry(word: "pizza", drawerIsMe: true, solveMs: 9_200, tries: 1),
      HistoryEntry(word: "the dog at your mom's house", drawerIsMe: false, solveMs: 64_000, tries: 2),
      HistoryEntry(word: "volcano", drawerIsMe: true, solveMs: nil, tries: 4),
      HistoryEntry(word: "cat", drawerIsMe: false, solveMs: 7_500, tries: 1),
      HistoryEntry(word: "fjord", drawerIsMe: true, solveMs: 31_000, tries: 1),
      HistoryEntry(word: "bicycle", drawerIsMe: false, solveMs: 12_800, tries: 2),
      HistoryEntry(word: "brown cheese", drawerIsMe: true, solveMs: 22_000, tries: 1),
      HistoryEntry(word: "rainbow", drawerIsMe: false, solveMs: 41_000, tries: 3),
      HistoryEntry(word: "sailboat", drawerIsMe: true, solveMs: 15_900, tries: 1),
      HistoryEntry(word: "hedgehog", drawerIsMe: false, solveMs: 27_300, tries: 2),
      HistoryEntry(word: "lighthouse", drawerIsMe: true, solveMs: 52_000, tries: 5),
    ]

    /// The id of history round `number`.
    static func historyRoundID(_ number: Int) -> UUID {
      UUID(uuidString: String(format: "eeeeeeee-0000-4000-8000-%012d", number)) ?? UUID()
    }

    /// The rounds this person has starred: 11, 8 and 5.
    static let historyStarredRoundIDs: Set<UUID> = Set([11, 8, 5].map(historyRoundID))

    /// The favorites of the "Our drawings" scenarios: the starred rounds.
    @MainActor
    static func favoritesStore() -> FavoritesStore {
      FavoritesStore.preloaded(
        ownerUserID: me,
        favorites: historyStarredRoundIDs.map { FavoriteRef(target: .gameRound($0), createdAt: now) }
      )
    }

    /// Newest first, round 12 down to round 1.
    static func historyRounds() -> [RemoteDrawAndGuessHistoryRound] {
      historyWords.enumerated().map { index, entry in
        let number = historyWords.count - index
        let drawer = entry.drawerIsMe ? me : partner
        let guesser = entry.drawerIsMe ? partner : me
        let solved = entry.solveMs != nil
        return RemoteDrawAndGuessHistoryRound(
          id: historyRoundID(number),
          roundNumber: number,
          drawerUserID: drawer,
          guesserUserID: guesser,
          word: entry.word,
          difficulty: .medium,
          points: 2,
          state: solved ? .solved : .missed,
          drawingMediaAssetID: assetID,
          solveMs: entry.solveMs,
          speedBonus: 0,
          firstTryBonus: solved && entry.tries == 1 ? 1 : 0,
          hintsUsed: 0,
          attemptCount: entry.tries,
          personalBest: false,
          startedAt: now.addingTimeInterval(-Double(index + 1) * 86_400 - 600),
          endedAt: now.addingTimeInterval(-Double(index + 1) * 86_400)
        )
      }
    }

    /// The server's answer for a page: rounds before the cursor, optionally only
    /// the starred ones.
    static func historyPage(starredOnly: Bool, before: Int?, limit: Int) -> RemoteDrawAndGuessHistoryPage {
      historyPage(
        from: historyRounds(),
        starred: historyStarredRoundIDs,
        starredOnly: starredOnly,
        before: before,
        limit: limit
      )
    }

    /// The same paging for any list of rounds, newest first. `starred` holds the rounds this
    /// person favorited. The tests use it too.
    static func historyPage(
      from rounds: [RemoteDrawAndGuessHistoryRound],
      starred: Set<UUID> = [],
      starredOnly: Bool,
      before: Int?,
      limit: Int
    ) -> RemoteDrawAndGuessHistoryPage {
      let matching = rounds.filter { round in
        (before.map { round.roundNumber < $0 } ?? true) && (!starredOnly || starred.contains(round.id))
      }
      let page = Array(matching.prefix(limit))
      return RemoteDrawAndGuessHistoryPage(
        rounds: page,
        nextBeforeRoundNumber: matching.count > limit ? page.last?.roundNumber : nil
      )
    }

    static let records = RemoteDrawAndGuessRecords(partners: [
      RemoteDrawAndGuessPlayerRecords(
        userID: me,
        solves: 5,
        firstTrySolves: 2,
        averageSolveMs: 29_000,
        fastestSolveMs: 7_500,
        fastestSolveWord: "cat",
        drawingsSolved: 5
      ),
      RemoteDrawAndGuessPlayerRecords(
        userID: partner,
        solves: 3,
        firstTrySolves: 3,
        averageSolveMs: 15_700,
        fastestSolveMs: 9_200,
        fastestSolveWord: "pizza",
        drawingsSolved: 3
      ),
    ])

    /// Nobody has solved anything yet, so every number is empty.
    static let emptyRecords = RemoteDrawAndGuessRecords(partners: [me, partner].map {
      RemoteDrawAndGuessPlayerRecords(
        userID: $0,
        solves: 0,
        firstTrySolves: 0,
        averageSolveMs: nil,
        fastestSolveMs: nil,
        fastestSolveWord: nil,
        drawingsSolved: 0
      )
    })
  }

  /// "Our drawings" on its own screen, with a stack that opens the detail.
  @MainActor
  struct DeveloperGamesHistoryScenarioView: View {
    @State private var viewModel: GamesViewModel
    @State private var path: [GamesDestination] = []

    init(scenario: DeveloperScenario) {
      let viewModel = DeveloperGamesScenarioFactory.gamesViewModel(for: scenario)
      viewModel.configure(participants: DeveloperGamesFixture.participants)
      _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
      NavigationStack(path: $path) {
        DrawAndGuessHistoryScreen(viewModel: viewModel.drawAndGuess.history)
          .navigationDestination(for: GamesDestination.self) { destination in
            if case let .drawAndGuessHistoryDetail(roundID) = destination {
              DrawAndGuessHistoryDetailHost(history: viewModel.drawAndGuess.history, roundID: roundID)
            }
          }
      }
    }
  }
#endif
