#if DEBUG
  import Foundation

  /// The board games a scenario can play.
  nonisolated enum DeveloperBoardGame: Sendable {
    case connectFour
    case dotsAndBoxes
    case ultimateTicTacToe

    var kind: GameKind {
      switch self {
      case .connectFour: .connectFour
      case .dotsAndBoxes: .dotsAndBoxes
      case .ultimateTicTacToe: .ultimateTicTacToe
      }
    }
  }

  /// One board game as a scenario's server holds it, and how far this phone has
  /// shown it. Alex is the signed-in person and Robin is the partner. Alex moves
  /// first unless `iStart` is false.
  nonisolated struct DeveloperBoardGameSetup: Sendable {
    struct Tallies: Sendable {
      var mine: Int
      var partner: Int
      var draws: Int

      var finished: Int { mine + partner + draws }
    }

    /// The finished game that a rematch replaced.
    struct Ending: Sendable {
      var moves: [Int]
      var iStarted: Bool
      var stake: String?
    }

    /// The rules' answer for a list of moves.
    struct Replayed: Equatable, Sendable {
      var next: BoardPlayer
      var outcome: BoardOutcome?
    }

    var game: DeveloperBoardGame
    var moves: [Int]
    var iStart = true
    var gameNumber = 9
    var stake: String?
    var hasPhoto = false
    var partnerIsHere = false
    /// The server's tallies. A finished game is already in them.
    var tallies = Tallies(mine: 4, partner: 3, draws: 1)
    /// With a previous game, this phone stopped inside it, and the screen shows
    /// that ending first.
    var previous: Ending?
    /// A move of Alex's that waits on this phone after a try that failed. The
    /// board shows it on top of `moves`.
    var queuedMove: Int?
    /// How many moves of the board this phone has not shown yet, counted from the
    /// last one. They play when the screen opens. Nil means this phone has no
    /// record of showing the game.
    var unseenMoves: Int? = 0

    var kind: GameKind { game.kind }

    var firstUserID: UUID {
      iStart ? DeveloperGamesFixture.me : DeveloperGamesFixture.partner
    }

    func user(_ player: BoardPlayer) -> UUID {
      (player == .one) == iStart ? DeveloperGamesFixture.me : DeveloperGamesFixture.partner
    }

    /// Replays `moves` with the game's rules. Nil when a move is illegal.
    func replayed(_ moves: [Int]) -> Replayed? {
      switch game {
      case .connectFour: Self.replayed(ConnectFourBoard.self, moves)
      case .dotsAndBoxes: Self.replayed(DotsAndBoxesBoard.self, moves)
      case .ultimateTicTacToe: Self.replayed(UltimateTicTacToeBoard.self, moves)
      }
    }

    private static func replayed<Board: BoardGameRules>(_: Board.Type, _ moves: [Int]) -> Replayed? {
      Board.replay(moves).map { Replayed(next: $0.next, outcome: $0.outcome) }
    }

    /// The game as the server shows it to Alex.
    func remoteGame() -> RemoteBoardGame {
      let rules = replayed(moves)
      let outcome = rules?.outcome
      let now = DeveloperScenarioFixture.now
      var turn: UUID?
      if outcome == nil {
        turn = rules.map { user($0.next) } ?? firstUserID
      }
      return RemoteBoardGame(
        id: DeveloperBoardGamesFixture.gameID(for: game),
        kind: kind,
        gameNumber: gameNumber,
        status: outcome == nil ? .playing : .finished,
        version: (gameNumber - 1) * 60 + moves.count + 1,
        firstUserID: firstUserID,
        moves: moves,
        turnUserID: turn,
        winnerUserID: outcome?.winner.map(user),
        winLine: outcome?.line ?? [],
        stake: stake,
        stakeByUserID: stake == nil ? nil : firstUserID,
        photoMediaAssetID: hasPhoto ? DeveloperBoardGamesFixture.photoAssetID : nil,
        myWins: tallies.mine,
        partnerWins: tallies.partner,
        draws: tallies.draws,
        gamesFinished: tallies.finished,
        previous: previousEnding(),
        startedAt: now.addingTimeInterval(-3_600),
        finishedAt: outcome == nil ? nil : now.addingTimeInterval(-120),
        turnStartedAt: now.addingTimeInterval(-600),
        updatedAt: now.addingTimeInterval(-120)
      )
    }

    private func previousEnding() -> RemoteBoardGameEnding? {
      guard let previous, let outcome = replayed(previous.moves)?.outcome else { return nil }
      let first = previous.iStarted ? DeveloperGamesFixture.me : DeveloperGamesFixture.partner
      let second = previous.iStarted ? DeveloperGamesFixture.partner : DeveloperGamesFixture.me
      return RemoteBoardGameEnding(
        gameNumber: gameNumber - 1,
        firstUserID: first,
        moves: previous.moves,
        winnerUserID: outcome.winner.map { $0 == .one ? first : second },
        winLine: outcome.line,
        stake: previous.stake,
        photoMediaAssetID: nil,
        finishedAt: DeveloperScenarioFixture.now.addingTimeInterval(-300)
      )
    }

    /// What the phone remembers of showing the game.
    var shown: BoardGameShownPosition? {
      guard let unseenMoves else { return nil }
      if let previous {
        return BoardGameShownPosition(
          gameNumber: gameNumber - 1,
          moveCount: max(0, previous.moves.count - unseenMoves)
        )
      }
      let onBoard = moves.count + (queuedMove == nil ? 0 : 1)
      return BoardGameShownPosition(gameNumber: gameNumber, moveCount: max(0, onBoard - unseenMoves))
    }

    /// The queue entry for `queuedMove`.
    func queuedPayload() -> BoardGameMovePayload? {
      guard let queuedMove else { return nil }
      let game = remoteGame()
      return BoardGameMovePayload(
        kind: kind,
        gameID: game.id,
        gameNumber: gameNumber,
        expectedVersion: game.version,
        move: queuedMove,
        stake: nil,
        createdAt: DeveloperScenarioFixture.now
      )
    }
  }

  /// The board games of each scenario, and the cache and overview that hold them.
  enum DeveloperBoardGamesFixture {
    nonisolated static let photoAssetID =
      UUID(uuidString: "cccccccc-0000-4000-8000-0000000000b1") ?? UUID()

    nonisolated static func gameID(for game: DeveloperBoardGame) -> UUID {
      switch game {
      case .connectFour: UUID(uuidString: "ffffffff-0000-4000-8000-000000000001") ?? UUID()
      case .dotsAndBoxes: UUID(uuidString: "ffffffff-0000-4000-8000-000000000002") ?? UUID()
      case .ultimateTicTacToe: UUID(uuidString: "ffffffff-0000-4000-8000-000000000003") ?? UUID()
      }
    }

    // MARK: Scenarios

    private typealias Setup = DeveloperBoardGameSetup
    private typealias Moves = DeveloperBoardGamesMoves
    private static let coffee = "Loser makes coffee"

    /// The games the server holds for a scenario. Other scenarios hold none, so
    /// the hub shows each board game's card as "Start a game".
    static func setups(for scenario: DeveloperScenario) -> [DeveloperBoardGameSetup] {
      if scenario == .gamesHubBoardGames {
        return hubSetups
      }
      return setupByScenario[scenario].map { [$0] } ?? []
    }

    private static let connectFourYourTurn = Setup(
      game: .connectFour, moves: Moves.connectFourMidGame, stake: coffee, partnerIsHere: true
    )

    private static let setupByScenario: [DeveloperScenario: Setup] = [
      .connectFourYourTurn: connectFourYourTurn,
      .boardGameMarkEditor: connectFourYourTurn,
      .connectFourPartnerTurn: Setup(
        game: .connectFour, moves: Moves.connectFourMidGame, iStart: false, stake: coffee
      ),
      .connectFourPartnerMove: Setup(
        game: .connectFour, moves: Moves.connectFourMidGame, stake: coffee, partnerIsHere: true, unseenMoves: 1
      ),
      .connectFourWon: Setup(
        game: .connectFour,
        moves: Moves.connectFourWin,
        stake: "Winner picks the movie",
        partnerIsHere: true,
        tallies: .init(mine: 5, partner: 3, draws: 1),
        unseenMoves: 1
      ),
      .connectFourFirstMove: Setup(
        game: .connectFour, moves: [], gameNumber: 1, tallies: .init(mine: 0, partner: 0, draws: 0)
      ),
      // Robin won game 9 with a column of four and started game 10 with a first disc.
      .connectFourMissedEnding: Setup(
        game: .connectFour,
        moves: [3],
        iStart: false,
        gameNumber: 10,
        tallies: .init(mine: 4, partner: 4, draws: 1),
        previous: .init(moves: Moves.connectFourLostGame, iStarted: true, stake: "Loser does the dishes"),
        unseenMoves: 1
      ),
      .connectFourOffline: Setup(game: .connectFour, moves: Moves.connectFourMidGame, queuedMove: 5),
      .dotsAndBoxesPhoto: Setup(
        game: .dotsAndBoxes, moves: Moves.dotsAndBoxesMidGame, hasPhoto: true, partnerIsHere: true
      ),
      .dotsAndBoxesExtraTurn: Setup(
        game: .dotsAndBoxes, moves: Moves.dotsAndBoxesExtraTurn, hasPhoto: true, partnerIsHere: true
      ),
      .dotsAndBoxesWonPhoto: Setup(
        game: .dotsAndBoxes,
        moves: Moves.dotsAndBoxesGame,
        stake: "Winner picks dinner",
        hasPhoto: true,
        partnerIsHere: true,
        tallies: .init(mine: 5, partner: 3, draws: 1),
        unseenMoves: 1
      ),
      .dotsAndBoxesPlain: Setup(game: .dotsAndBoxes, moves: Moves.dotsAndBoxesMidGame, partnerIsHere: true),
      .ultimateTicTacToeForced: Setup(
        game: .ultimateTicTacToe, moves: Moves.ultimateTicTacToeForced, partnerIsHere: true
      ),
      .ultimateTicTacToeFree: Setup(
        game: .ultimateTicTacToe, moves: Moves.ultimateTicTacToeFree, partnerIsHere: true
      ),
      .ultimateTicTacToePartnerMove: Setup(
        game: .ultimateTicTacToe, moves: Moves.ultimateTicTacToeForced, partnerIsHere: true, unseenMoves: 1
      ),
      .ultimateTicTacToeWon: Setup(
        game: .ultimateTicTacToe,
        moves: Moves.ultimateTicTacToeGame,
        stake: coffee,
        partnerIsHere: true,
        tallies: .init(mine: 5, partner: 3, draws: 1),
        unseenMoves: 1
      ),
    ]

    /// Alex to move, Robin to move with Robin in the game, and a game Robin won.
    private static let hubSetups = [
      Setup(game: .connectFour, moves: Moves.connectFourMidGame, stake: coffee),
      Setup(game: .dotsAndBoxes, moves: Moves.dotsAndBoxesPartnerTurn, partnerIsHere: true),
      Setup(
        game: .ultimateTicTacToe,
        moves: Moves.ultimateTicTacToeGame,
        iStart: false,
        tallies: .init(mine: 3, partner: 4, draws: 1)
      ),
    ]

    // MARK: Cache

    static func boardGames(for scenario: DeveloperScenario) -> RemoteBoardGames {
      RemoteBoardGames(
        userID: DeveloperGamesFixture.me,
        partnerUserID: DeveloperGamesFixture.partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        games: setups(for: scenario).map { $0.remoteGame() }
      )
    }

    static func cache(for scenario: DeveloperScenario) -> InMemoryBoardGamesCache {
      InMemoryBoardGamesCache(state: boardGames(for: scenario), ownerUserID: DeveloperGamesFixture.me)
    }

    /// The overview for a board game scenario: the Draw & Guess one, plus a
    /// heartbeat for each game the partner has open. Other scenarios keep the
    /// overview their Draw & Guess state implies, so this returns nil.
    static func overview(
      for scenario: DeveloperScenario,
      drawAndGuess state: RemoteDrawAndGuessState
    ) -> RemoteGamesOverview? {
      let setups = setups(for: scenario)
      guard !setups.isEmpty else { return nil }
      let base = RemoteGamesOverview(drawAndGuess: state)
      let here = setups.filter(\.partnerIsHere).map {
        RemoteGamePresence(
          kind: $0.kind,
          myLastSeenAt: nil,
          partnerLastSeenAt: DeveloperGamesFixture.now.addingTimeInterval(-10),
          lastInviteAt: nil
        )
      }
      return RemoteGamesOverview(
        userID: base.userID,
        partnerUserID: base.partnerUserID,
        coupleID: base.coupleID,
        settings: base.settings,
        presence: base.presence + here
      )
    }
  }

  extension DeveloperScenario {
    /// The board game this scenario opens full screen. Nil for every other
    /// scenario, including the hub.
    @MainActor var boardGame: DeveloperBoardGame? {
      guard self != .gamesHubBoardGames else { return nil }
      return DeveloperBoardGamesFixture.setups(for: self).first?.game
    }
  }
#endif
