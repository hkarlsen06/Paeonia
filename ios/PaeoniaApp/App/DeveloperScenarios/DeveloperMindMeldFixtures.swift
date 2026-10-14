#if DEBUG
  import Foundation

  /// Deterministic Mind Meld games for the scenarios. Alex is the signed-in person
  /// and Robin is the partner. Every date counts from `DeveloperGamesFixture.now`,
  /// so the screens look the same on every launch.
  enum DeveloperMindMeldFixture {
    typealias Pair = (mine: String, theirs: String)

    static let me = DeveloperGamesFixture.me
    static let partner = DeveloperGamesFixture.partner
    static let now = DeveloperGamesFixture.now

    /// The couple's game in play. The one before it is `currentGameNumber - 1`.
    static let currentGameNumber = 5

    /// Ten pairs that never meld. The four-round scenarios use the first three.
    static let trail: [Pair] = [
      ("ocean", "sushi"), ("salt", "fish"), ("sea", "net"), ("boat", "catch"), ("pier", "hook"),
      ("lake", "rod"), ("wave", "bait"), ("tide", "worm"), ("shore", "sand"), ("dock", "sail"),
    ]

    /// The couple's numbers while game 5 is in play: two melds, fewest 3 rounds, four finished games.
    static let base = RemoteMindMeldStats(melds: 2, fewestRounds: 3, games: 4)
    static let noMelds = RemoteMindMeldStats(melds: 0, fewestRounds: nil, games: 0)

    // MARK: Ids

    static func gameID(_ number: Int) -> UUID {
      id("aaaaaaaa", number)
    }

    static var currentGameID: UUID {
      gameID(currentGameNumber)
    }

    static func roundID(game: Int, round: Int) -> UUID {
      id("bbbbbbbb", game * 100 + round)
    }

    private static func id(_ prefix: String, _ number: Int) -> UUID {
      UUID(uuidString: String(format: "\(prefix)-1000-4000-8000-%012ld", number)) ?? UUID()
    }

    // MARK: Rounds and games

    /// A revealed round. `seen: false` is a reveal this person has not looked at yet.
    static func revealed(
      _ number: Int,
      _ pair: Pair,
      outcome: MindMeldOutcome = .miss,
      seen: Bool = true,
      countedBy: UUID? = nil,
      game: Int = currentGameNumber
    ) -> RemoteMindMeldRound {
      let at = time(of: number)
      return RemoteMindMeldRound(
        id: roundID(game: game, round: number),
        roundNumber: number,
        state: .revealed,
        outcome: outcome,
        countedByUserID: countedBy,
        myWord: pair.mine,
        myLockedAt: at,
        partnerLocked: true,
        partnerLockedAt: at,
        partnerWord: pair.theirs,
        revealedAt: at,
        myRevealSeenAt: seen ? at : nil
      )
    }

    /// The first `count` pairs of the trail, all revealed and seen.
    static func revealedRounds(_ count: Int, game: Int = currentGameNumber) -> [RemoteMindMeldRound] {
      trail.prefix(count).enumerated().map { index, pair in
        revealed(index + 1, pair, game: game)
      }
    }

    /// The round people can still write in. `mine` is a word the server already has.
    static func open(
      _ number: Int,
      mine: String? = nil,
      partnerLocked: Bool = false,
      game: Int = currentGameNumber
    ) -> RemoteMindMeldRound {
      let at = time(of: number)
      return RemoteMindMeldRound(
        id: roundID(game: game, round: number),
        roundNumber: number,
        state: .open,
        outcome: nil,
        countedByUserID: nil,
        myWord: mine,
        myLockedAt: mine == nil ? nil : at,
        partnerLocked: partnerLocked,
        partnerLockedAt: partnerLocked ? at : nil,
        partnerWord: nil,
        revealedAt: nil,
        myRevealSeenAt: nil
      )
    }

    /// Later rounds are newer, a few minutes apart.
    private static func time(of round: Int) -> Date {
      now.addingTimeInterval(-Double(12 - round) * 240)
    }

    static func game(
      _ number: Int = currentGameNumber,
      state: MindMeldGameState = .playing,
      rounds: [RemoteMindMeldRound],
      reason: MindMeldEndReason? = nil,
      endedBy: UUID? = nil,
      endSeen: Bool = false,
      meldNumber: Int? = nil,
      isRecord: Bool = false
    ) -> RemoteMindMeldGame {
      RemoteMindMeldGame(
        id: gameID(number),
        gameNumber: number,
        state: state,
        endReason: reason,
        endedByUserID: endedBy,
        endedAt: state == .playing ? nil : now.addingTimeInterval(-300),
        maxRounds: 10,
        myEndSeenAt: endSeen ? now.addingTimeInterval(-120) : nil,
        meldNumber: meldNumber,
        isRecord: isRecord,
        createdByUserID: me,
        createdAt: now.addingTimeInterval(-3_600),
        updatedAt: now.addingTimeInterval(-60),
        version: 9,
        rounds: rounds
      )
    }

    static func state(
      current: RemoteMindMeldGame?,
      previous: RemoteMindMeldGame? = nil,
      stats: RemoteMindMeldStats = base
    ) -> RemoteMindMeldState {
      RemoteMindMeldState(
        userID: me,
        partnerUserID: partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        current: current,
        previous: previous,
        stats: stats
      )
    }

    /// A game in play with `rounds`.
    static func playing(_ rounds: [RemoteMindMeldRound], stats: RemoteMindMeldStats = base) -> RemoteMindMeldState {
      state(current: game(rounds: rounds), stats: stats)
    }

    // MARK: History

    /// Finished games, newest first: a four-round meld, a game started over, a game
    /// that got away, a meld that counted a near miss, and a five-round meld.
    static func historyGames() -> [RemoteMindMeldHistoryGame] {
      [
        historyGame(5, .melded, meldNumber: 3, pairs: Array(trail.prefix(3)) + [("boat", "boat")]),
        historyGame(4, .ended, reason: .restart, pairs: [("rain", "umbrella"), ("storm", "cloud")]),
        historyGame(3, .ended, reason: .rounds, pairs: trail),
        historyGame(
          2, .melded, meldNumber: 2, countsLastRound: true,
          pairs: [("coffee", "morning"), ("cup", "mug"), ("tea", "teas")]
        ),
        historyGame(
          1, .melded, meldNumber: 1,
          pairs: [("sun", "moon"), ("sky", "night"), ("star", "dark"), ("lamp", "candle"), ("light", "light")]
        ),
      ]
    }

    static let historyStats = RemoteMindMeldStats(melds: 3, fewestRounds: 3, games: 5)

    /// The server's answer for a page: games before the cursor.
    static func historyPage(before: Int?, limit: Int) -> RemoteMindMeldHistoryPage {
      let matching = historyGames().filter { game in
        before.map { game.gameNumber < $0 } ?? true
      }
      let page = Array(matching.prefix(limit))
      return RemoteMindMeldHistoryPage(
        games: page,
        nextBeforeGameNumber: matching.count > limit ? page.last?.gameNumber : nil,
        stats: historyStats
      )
    }

    static let emptyHistoryPage = RemoteMindMeldHistoryPage(games: [], nextBeforeGameNumber: nil, stats: noMelds)

    private static func historyGame(
      _ number: Int,
      _ state: MindMeldGameState,
      reason: MindMeldEndReason? = nil,
      meldNumber: Int? = nil,
      countsLastRound: Bool = false,
      pairs: [Pair]
    ) -> RemoteMindMeldHistoryGame {
      // Each game ended a few days before the next one.
      let endedAt = now.addingTimeInterval(-Double(currentGameNumber - number) * 3 * 86_400 - 86_400)
      return RemoteMindMeldHistoryGame(
        id: gameID(number),
        gameNumber: number,
        state: state,
        endReason: reason,
        endedByUserID: reason == .restart ? partner : nil,
        createdAt: endedAt.addingTimeInterval(-1_800),
        endedAt: endedAt,
        meldNumber: meldNumber,
        rounds: pairs.enumerated().map { index, pair in
          let isLast = index == pairs.count - 1
          let melds = state == .melded && isLast
          return RemoteMindMeldHistoryRound(
            roundNumber: index + 1,
            myWord: pair.mine,
            partnerWord: pair.theirs,
            outcome: melds ? (countsLastRound ? .near : .match) : .miss,
            countedByUserID: melds && countsLastRound ? partner : nil
          )
        }
      )
    }
  }
#endif
