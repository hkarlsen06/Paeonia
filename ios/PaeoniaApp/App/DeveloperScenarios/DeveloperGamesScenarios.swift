#if DEBUG
  import Foundation
  import PencilKit
  import SwiftUI

  /// Games scenarios. They run the real hub, setup, and Draw & Guess screens on
  /// in-memory dependencies, so the screens can be reached in any phase without
  /// a partner, a network, or the Convex backend.
  ///
  /// The cache holds a fixed server state. The pending operations are in memory,
  /// so a move made here (picking a word, a guess, "Show me") changes the screen
  /// the way it does on a phone that is offline.
  @MainActor
  enum DeveloperGamesScenarioFactory {
    /// A scenario's fixed server state, or nil for setup before anyone chose.
    static func state(for scenario: DeveloperScenario) -> RemoteDrawAndGuessState {
      lobbyState(for: scenario)
        ?? roundState(for: scenario)
        ?? revealScenarioState(for: scenario)
        ?? DeveloperGamesFixture.state(settings: DeveloperGamesFixture.settings(), game: nil)
    }

    /// The setup and hub scenarios, before a drawing is on screen.
    private static func lobbyState(for scenario: DeveloperScenario) -> RemoteDrawAndGuessState? {
      typealias Fixture = DeveloperGamesFixture
      let mine = Fixture.settings()
      switch scenario {
      case .gamesSetup:
        return Fixture.state(settings: nil, game: nil)
      case .gamesPartnerPicked:
        return Fixture.state(settings: Fixture.settings(by: Fixture.partner), game: nil)
      case .gamesHubYourTurn, .drawChooseWord:
        return Fixture.state(
          settings: mine,
          game: Fixture.game(state: .choosingWord, turn: Fixture.me, roundID: nil),
          choices: Fixture.choices
        )
      case .gamesHubWaiting, .drawWaitingForGuess, .gamesHubBoardGames:
        return Fixture.state(
          settings: mine,
          game: Fixture.game(state: .guessing, turn: Fixture.partner),
          round: Fixture.round(
            state: .guessing,
            drawer: Fixture.me,
            hasDrawing: true,
            attempts: [("cat", false), ("hat", false)],
            guesserHasSeenIt: true
          )
        )
      case .gamesHubPartnerHere, .drawGuessingReplay:
        return Fixture.state(
          settings: mine,
          game: Fixture.game(state: .guessing, turn: Fixture.me),
          round: Fixture.round(state: .guessing, drawer: Fixture.partner, hasDrawing: true),
          partnerIsHere: scenario == .gamesHubPartnerHere
        )
      default:
        return nil
      }
    }

    /// The scenarios with a round in progress: guessing, waiting, or drawing.
    private static func roundState(for scenario: DeveloperScenario) -> RemoteDrawAndGuessState? {
      typealias Fixture = DeveloperGamesFixture
      let mine = Fixture.settings()
      switch scenario {
      case .drawGuessingLongWord:
        return Fixture.state(
          settings: mine,
          game: Fixture.game(state: .guessing, turn: Fixture.me),
          round: Fixture.round(
            state: .guessing,
            drawer: Fixture.partner,
            word: "counterrevolutionary",
            hasDrawing: true
          )
        )
      case .drawWaitingForWord:
        return Fixture.state(
          settings: mine,
          game: Fixture.game(state: .choosingWord, turn: Fixture.partner, roundID: nil)
        )
      case .drawDrawing, .drawSavedOffline:
        return Fixture.state(
          settings: mine,
          game: Fixture.game(state: .drawing, turn: Fixture.partner),
          round: Fixture.round(state: .drawing, drawer: Fixture.me),
          partnerIsHere: true
        )
      case .drawWaitingForDrawing, .drawWatchingLive:
        return Fixture.state(
          settings: mine,
          game: Fixture.game(state: .drawing, turn: Fixture.me),
          round: Fixture.round(state: .drawing, drawer: Fixture.partner),
          partnerIsHere: true
        )
      default:
        return nil
      }
    }

    /// The scenarios that show a finished round.
    private static func revealScenarioState(for scenario: DeveloperScenario) -> RemoteDrawAndGuessState? {
      typealias Fixture = DeveloperGamesFixture
      switch scenario {
      case .drawRevealSolved, .drawRevealLoading:
        return revealState(.solved, drawer: Fixture.partner)
      case .drawRevealBonuses:
        // A fast first-try solve that is also the guesser's best so far.
        return revealState(
          .solved,
          drawer: Fixture.partner,
          attempts: [("umbrella", true)],
          bonuses: .init(speed: 2, firstTry: 1, personalBest: true)
        )
      case .drawRevealMissed:
        return revealState(.missed, drawer: Fixture.partner)
      case .drawRevealAsDrawer:
        return revealState(
          .solved,
          drawer: Fixture.me,
          attempts: [("cat", false), ("hat", false), ("umbrella", true)],
          bonuses: .init(hints: 2, reaction: .laugh)
        )
      case .drawRevealPartnerDrawing:
        // Robin solved the last drawing and has already started the next one.
        return Fixture.state(
          settings: Fixture.settings(),
          game: Fixture.game(state: .drawing, turn: Fixture.me, roundID: Fixture.nextRoundID),
          round: Fixture.round(id: Fixture.nextRoundID, state: .drawing, drawer: Fixture.partner),
          recentRounds: [
            Fixture.round(
              state: .solved,
              drawer: Fixture.me,
              hasDrawing: true,
              attempts: [("cat", false), ("hat", false), ("umbrella", true)],
              solveMs: 18_400,
              speedBonus: 1
            ),
          ],
          partnerIsHere: true
        )
      default:
        return nil
      }
    }

    /// What a solved round earned besides the word's points.
    nonisolated private struct Bonuses {
      var speed = 1
      var firstTry = 0
      var hints = 0
      var personalBest = false
      var reaction: DrawAndGuessReaction?
    }

    private static func revealState(
      _ state: DrawAndGuessRoundState,
      drawer: UUID,
      attempts: [(text: String, correct: Bool)] = [],
      bonuses: Bonuses = Bonuses()
    ) -> RemoteDrawAndGuessState {
      typealias Fixture = DeveloperGamesFixture
      let nextDrawer = drawer == Fixture.me ? Fixture.partner : Fixture.me
      return Fixture.state(
        settings: Fixture.settings(),
        game: Fixture.game(state: .choosingWord, turn: nextDrawer),
        round: Fixture.round(
          state: state,
          drawer: drawer,
          hasDrawing: true,
          attempts: attempts,
          solveMs: state == .solved ? 18_400 : nil,
          speedBonus: state == .solved && bonuses.hints == 0 ? bonuses.speed : 0,
          firstTryBonus: state == .solved ? bonuses.firstTry : 0,
          hintsUsed: state == .solved ? bonuses.hints : 0,
          personalBest: state == .solved && bonuses.personalBest,
          reaction: bonuses.reaction
        ),
        choices: nextDrawer == Fixture.me ? Fixture.choices : nil
      )
    }

    /// The dependencies for one scenario. The cache starts with its state.
    static func dependencies(for scenario: DeveloperScenario) -> GamesDependencies {
      // The partner's drawing is already on the phone, so a reveal shows it from the first
      // frame. The loading scenario has to download it, and the download never finishes.
      let isLoading = scenario == .drawRevealLoading
      let drawingStore = seededDrawingStore(isLoading: isLoading)
      let drawState = state(for: scenario)
      let cache = InMemoryGamesCache(
        state: drawState,
        overview: DeveloperMindMeldScenarioFactory.overview(for: scenario, drawAndGuess: drawState)
          ?? DeveloperBoardGamesFixture.overview(for: scenario, drawAndGuess: drawState),
        ownerUserID: DeveloperGamesFixture.me,
        hasSeenSettings: scenario != .gamesPartnerPicked
      )
      let storyChainCache = InMemoryStoryChainCache(
        state: DeveloperStoryChainScenarios.state(for: scenario),
        ownerUserID: DeveloperGamesFixture.me
      )
      // Each built game sets its own dependency fields on this value, so the hub
      // scenarios show its card next to Draw & Guess.
      var dependencies = GamesDependencies(
        gateway: DeveloperGamesGateway(historyIsEmpty: scenario == .drawHistoryEmpty),
        cache: cache,
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: DeveloperScenarioOperationProvider(),
        drawingStore: drawingStore,
        drawingTransfer: DeveloperGameDrawingTransfer(stallsDownloads: isLoading),
        makeLive: { coupleID in makeLive(for: scenario, coupleID: coupleID) },
        now: { DeveloperGamesFixture.now },
        storyChainGateway: DeveloperStoryChainGateway(scenario: scenario),
        storyChainCache: storyChainCache,
        makeStoryChainLive: { coupleID in
          DeveloperStoryChainScenarios.makeLive(for: scenario, coupleID: coupleID, cache: storyChainCache)
        },
        mindMeldGateway: DeveloperMindMeldGateway(historyIsEmpty: scenario == .mindMeldHistoryEmpty),
        mindMeldCache: DeveloperMindMeldScenarioFactory.cache(for: scenario),
        makeMindMeldLive: { coupleID in DeveloperMindMeldScenarioFactory.makeLive(for: scenario, coupleID: coupleID) },
        consensioGateway: DeveloperConsensioGateway(),
        consensioCache: DeveloperConsensioScenarioFactory.cache(for: scenario),
        makeConsensioLive: { DeveloperConsensioScenarioFactory.makeLive(for: scenario, coupleID: $0) },
        boardGamesGateway: DeveloperBoardGamesGateway(),
        boardGamesCache: DeveloperBoardGamesFixture.cache(for: scenario),
        memoryPhotos: DeveloperBoardPhotoProvider()
      )
      ExquisiteCorpseDeveloperScenarioFactory.configure(&dependencies, for: scenario)
      return DeveloperGuessMySpotScenarioFactory.configured(dependencies, for: scenario)
    }

    private static func seededDrawingStore(isLoading: Bool) -> InMemoryGameDrawingStore {
      let drawingStore = InMemoryGameDrawingStore()
      if !isLoading {
        drawingStore.saveDownloadedDrawing(
          DeveloperGamesFixture.umbrella().dataRepresentation(),
          mediaAssetID: DeveloperGamesFixture.assetID
        )
      }
      return drawingStore
    }

    static func gamesViewModel(for scenario: DeveloperScenario) -> GamesViewModel {
      GamesViewModel(dependencies: dependencies(for: scenario))
    }

    /// The live room, with the partner already in it when the scenario calls for
    /// it. No relay is involved: the partner's messages are fed in directly.
    private static func makeLive(for scenario: DeveloperScenario, coupleID: UUID) -> WidgetLiveDrawing? {
      let connection = WidgetLiveConnection(coupleID: coupleID, ticketProvider: { _ in nil })
      let live = WidgetLiveDrawing(connection: connection, role: .watching)
      switch scenario {
      case .drawDrawing, .drawSavedOffline:
        simulatePartner(on: connection, role: .watching, canvas: nil)
      case .drawWaitingForWord:
        simulatePartner(on: connection, role: .choosing, canvas: nil)
      case .drawWatchingLive, .drawRevealPartnerDrawing:
        simulatePartner(on: connection, role: .drawing, canvas: DeveloperGamesFixture.umbrella())
      default:
        break
      }
      return live
    }

    private static func simulatePartner(
      on connection: WidgetLiveConnection,
      role: WidgetLivePresence.Role,
      canvas: PKDrawing?
    ) {
      connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
      connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role.rawValue))
      if let canvas {
        connection.onMessage?(WidgetLiveMessage(
          type: .ops,
          side: Double(GameCanvas.canonicalSide),
          upserts: canvas.dataRepresentation().base64EncodedString(),
          snapshot: true
        ))
      }
    }
  }

  /// Every call succeeds and changes nothing. The screens already show a move the
  /// moment it is saved in the pending operations.
  struct DeveloperGamesGateway: DrawAndGuessGateway {
    /// "Our drawings" answers with no rounds and empty records.
    var historyIsEmpty = false

    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) throws -> RemoteGameSettings {
      RemoteGameSettings(
        coupleID: DeveloperScenarioFixture.coupleID,
        playStyle: playStyle,
        language: language,
        updatedByUserID: DeveloperGamesFixture.me,
        createdAt: DeveloperGamesFixture.now,
        updatedAt: DeveloperGamesFixture.now
      )
    }

    func ensureDrawAndGuessGame() throws -> RemoteEnsureGameResult {
      RemoteEnsureGameResult(gameID: DeveloperGamesFixture.gameID, created: false)
    }

    func loadDrawAndGuess() throws -> RemoteDrawAndGuessState {
      // The cache is the scenario's state. Failing keeps the cache as it is.
      throw URLError(.notConnectedToInternet)
    }

    func loadDrawAndGuessRound(roundID _: UUID) throws -> RemoteDrawAndGuessRound? {
      throw URLError(.notConnectedToInternet)
    }

    func pickWord(_ pick: GamePickWordPayload, operation _: SyncClientOperation) throws -> RemotePickedWord {
      RemotePickedWord(
        roundID: pick.roundID,
        roundNumber: 1,
        difficulty: pick.choice,
        word: pick.word,
        points: pick.points
      )
    }

    func submitDrawing(
      roundID: UUID,
      mediaAssetID _: UUID,
      operation _: SyncClientOperation
    ) throws -> RemoteSubmitDrawingResult {
      RemoteSubmitDrawingResult(roundID: roundID, roundState: .guessing, drawingSubmittedAt: DeveloperGamesFixture.now)
    }

    func markRoundSeen(roundID _: UUID) throws -> RemoteMarkSeenResult {
      RemoteMarkSeenResult(guesserFirstSeenAt: DeveloperGamesFixture.now)
    }

    func submitGuess( // swiftlint:disable:this function_parameter_count
        roundID _: UUID,
        guess _: String,
        speedBonus _: Int?,
        solveMs _: Int?,
        hintsUsed _: Int?,
        operation _: SyncClientOperation
    ) throws -> RemoteGuessResult {
      throw URLError(.notConnectedToInternet)
    }

    func giveUp(roundID: UUID, operation _: SyncClientOperation) throws -> RemoteGiveUpResult {
      RemoteGiveUpResult(roundID: roundID, roundState: .missed)
    }

    func setRoundReaction(roundID: UUID, reaction: DrawAndGuessReaction?) throws -> RemoteReactionResult {
      RemoteReactionResult(roundID: roundID, guesserReaction: reaction)
    }

    func markRoundResultSeen(roundID: UUID) throws -> RemoteResultSeenResult {
      RemoteResultSeenResult(roundID: roundID, resultSeenAt: DeveloperGamesFixture.now)
    }

    func sendInvite(_: GameKind) throws -> RemoteInviteResult {
      RemoteInviteResult(sentAt: DeveloperGamesFixture.now)
    }

    func setPresence(_: GameKind, isPresent _: Bool) throws {}

    // swiftlint:disable:next async_without_await
    func loadOverview() async throws -> RemoteGamesOverview {
      // The cache is the scenario's overview. Failing keeps the cache as it is.
      throw URLError(.notConnectedToInternet)
    }

    func loadDrawAndGuessHistory(
      starredOnly: Bool,
      beforeRoundNumber: Int?,
      limit: Int
    ) throws -> RemoteDrawAndGuessHistoryPage {
      guard !historyIsEmpty else { return RemoteDrawAndGuessHistoryPage(rounds: [], nextBeforeRoundNumber: nil) }
      return DeveloperGamesFixture.historyPage(starredOnly: starredOnly, before: beforeRoundNumber, limit: limit)
    }

    func loadDrawAndGuessRecords() throws -> RemoteDrawAndGuessRecords {
      historyIsEmpty ? DeveloperGamesFixture.emptyRecords : DeveloperGamesFixture.records
    }

    func setRoundStar(roundID: UUID, starred: Bool) throws -> RemoteRoundStarResult {
      RemoteRoundStarResult(roundID: roundID, starred: starred)
    }
  }

  /// The partner's drawing for every download: the fixture umbrella. A stalled
  /// download waits until the screen goes away.
  struct DeveloperGameDrawingTransfer: GameDrawingTransferring {
    var stallsDownloads = false

    func uploadDrawing(
      _: Data,
      parent _: GameUploadParent,
      coupleID _: UUID,
      reserveOperation _: SyncClientOperation,
      finalizeOperation _: SyncClientOperation
    ) throws -> UUID {
      DeveloperGamesFixture.assetID
    }

    func downloadDrawing(mediaAssetID _: UUID) async throws -> Data {
      if stallsDownloads {
        try await Task.sleep(for: .seconds(86_400))
      }
      return await MainActor.run { DeveloperGamesFixture.umbrella().dataRepresentation() }
    }
  }

  /// A Draw & Guess phase on its own screen.
  @MainActor
  struct DeveloperGamesScenarioView: View {
    let scenario: DeveloperScenario
    @State private var viewModel: DrawAndGuessViewModel
    @State private var isReady = false

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      let viewModel = DrawAndGuessViewModel(
        dependencies: DeveloperGamesScenarioFactory.dependencies(for: scenario),
        participants: DeveloperGamesFixture.participants
      )
      // The scenario host lets the viewer see the replay play once.
      _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
      NavigationStack {
        if isReady {
          DrawAndGuessScreen(viewModel: viewModel)
        } else {
          Color.paeoniaBackgroundPrimary
        }
      }
      .task {
        await seed()
        isReady = true
      }
    }

    /// Puts the scenario's unsent move in the queue before the screen reads it.
    private func seed() async {
      guard scenario == .drawSavedOffline else { return }
      let drawing = DeveloperGamesFixture.umbrella()
      let payload = GameSubmitDrawingPayload(
        gameID: DeveloperGamesFixture.gameID,
        roundID: DeveloperGamesFixture.roundID,
        coupleID: DeveloperScenarioFixture.coupleID,
        drawingData: drawing.dataRepresentation(),
        reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
        finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
      )
      guard let data = try? JSONEncoder().encode(payload) else { return }
      try? await viewModel.dependencies.pendingOperationStore.enqueue(
        PendingSyncOperationRequest(
          ownerUserID: DeveloperGamesFixture.me,
          operation: SyncClientOperation(clientID: UUID(), clientSequence: 3),
          operationKind: .submitGameDrawing,
          idempotencyScope: "game-drawing:developer",
          requestData: data
        )
      )
    }
  }
#endif
