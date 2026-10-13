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
      case .gamesHubWaiting, .drawWaitingForGuess:
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
      case .drawRevealSolved, .drawSavePrompt, .drawRevealLoading:
        return revealState(
          .solved,
          drawer: Fixture.partner,
          saveResponse: scenario == .drawSavePrompt ? nil : .notNow
        )
      case .drawRevealMissed:
        return revealState(.missed, drawer: Fixture.partner, saveResponse: .notNow)
      case .drawRevealAsDrawer:
        return revealState(
          .solved,
          drawer: Fixture.me,
          attempts: [("cat", false), ("hat", false), ("umbrella", true)]
        )
      case .drawRevealPartnerDrawing:
        // Robin solved the last drawing and has already started the next one.
        return Fixture.state(
          settings: mine,
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
        return Fixture.state(settings: mine, game: nil)
      }
    }

    private static func revealState(
      _ state: DrawAndGuessRoundState,
      drawer: UUID,
      attempts: [(text: String, correct: Bool)] = [],
      saveResponse: DrawAndGuessSaveResponse? = nil
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
          speedBonus: state == .solved ? 1 : 0,
          mySaveResponse: saveResponse
        ),
        choices: nextDrawer == Fixture.me ? Fixture.choices : nil
      )
    }

    /// The dependencies for one scenario. The cache starts with its state.
    static func dependencies(for scenario: DeveloperScenario) -> GamesDependencies {
      // The partner's drawing is already on the phone, so a reveal shows it from the first
      // frame. The loading scenario has to download it, and the download never finishes.
      let isLoading = scenario == .drawRevealLoading
      let drawingStore = InMemoryGameDrawingStore()
      if !isLoading {
        drawingStore.saveDownloadedDrawing(
          DeveloperGamesFixture.umbrella().dataRepresentation(),
          mediaAssetID: DeveloperGamesFixture.assetID
        )
      }
      let cache = InMemoryGamesCache(
        state: state(for: scenario),
        ownerUserID: DeveloperGamesFixture.me,
        hasSeenSettings: scenario != .gamesPartnerPicked
      )
      return GamesDependencies(
        gateway: DeveloperGamesGateway(),
        cache: cache,
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: DeveloperScenarioOperationProvider(),
        drawingStore: drawingStore,
        drawingTransfer: DeveloperGameDrawingTransfer(stallsDownloads: isLoading),
        makeLive: { coupleID in makeLive(for: scenario, coupleID: coupleID) },
        now: { DeveloperGamesFixture.now }
      )
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
          side: Double(DrawAndGuessCanvas.canonicalSide),
          upserts: canvas.dataRepresentation().base64EncodedString(),
          snapshot: true
        ))
      }
    }
  }

  /// Every call succeeds and changes nothing. The screens already show a move the
  /// moment it is saved in the pending operations.
  struct DeveloperGamesGateway: GamesGateway {
    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings {
      RemoteGameSettings(
        coupleID: DeveloperScenarioFixture.coupleID,
        playStyle: playStyle,
        language: language,
        updatedByUserID: DeveloperGamesFixture.me,
        createdAt: DeveloperGamesFixture.now,
        updatedAt: DeveloperGamesFixture.now
      )
    }

    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult {
      RemoteEnsureGameResult(gameID: DeveloperGamesFixture.gameID, created: false)
    }

    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState {
      // The cache is the scenario's state. Failing keeps the cache as it is.
      throw URLError(.notConnectedToInternet)
    }

    func loadDrawAndGuessRound(roundID _: UUID) async throws -> RemoteDrawAndGuessRound? {
      throw URLError(.notConnectedToInternet)
    }

    func pickWord(_ pick: GamePickWordPayload, operation _: SyncClientOperation) async throws -> RemotePickedWord {
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
    ) async throws -> RemoteSubmitDrawingResult {
      RemoteSubmitDrawingResult(roundID: roundID, roundState: .guessing, drawingSubmittedAt: DeveloperGamesFixture.now)
    }

    func markRoundSeen(roundID _: UUID) async throws -> RemoteMarkSeenResult {
      RemoteMarkSeenResult(guesserFirstSeenAt: DeveloperGamesFixture.now)
    }

    func submitGuess(
        roundID _: UUID,
        guess _: String,
        speedBonus _: Bool?,
        solveMs _: Int?,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessResult {
      throw URLError(.notConnectedToInternet)
    }

    func giveUp(roundID: UUID, operation _: SyncClientOperation) async throws -> RemoteGiveUpResult {
      RemoteGiveUpResult(roundID: roundID, roundState: .missed)
    }

    func respondSavePrompt(roundID _: UUID) async throws {}

    func saveRoundToMemories(
      roundID _: UUID,
      memoryID: UUID,
      mediaAssetID _: UUID,
      memoryDate _: String
    ) async throws -> RemoteSaveRoundResult {
      RemoteSaveRoundResult(memoryID: memoryID, created: true)
    }

    func sendInvite() async throws -> RemoteInviteResult {
      RemoteInviteResult(sentAt: DeveloperGamesFixture.now)
    }

    func setPresence(_: Bool) async throws {}
  }

  /// The partner's drawing for every download: the fixture umbrella. A stalled
  /// download waits until the screen goes away.
  struct DeveloperGameDrawingTransfer: GameDrawingTransferring {
    var stallsDownloads = false

    func uploadDrawing(
      _: Data,
      gameID _: UUID,
      roundID _: UUID,
      coupleID _: UUID,
      reserveOperation _: SyncClientOperation,
      finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
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
