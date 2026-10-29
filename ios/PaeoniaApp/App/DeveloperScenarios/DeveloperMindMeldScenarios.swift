#if DEBUG
  import Foundation
  import SwiftUI

  /// Mind Meld scenarios. They run the real Mind Meld screens on in-memory
  /// dependencies, so every phase can be reached without a partner, a network or
  /// the Convex backend. The cache holds a fixed server state, and a move made
  /// here (locking in a word, "Next round") changes the screen the way it does on
  /// a phone that is offline. Fixtures are in `DeveloperMindMeldFixtures.swift`.
  @MainActor
  enum DeveloperMindMeldScenarioFactory {
    typealias Fixture = DeveloperMindMeldFixture

    /// A scenario's fixed server state. Nil when the scenario has no Mind Meld game,
    /// so the hub shows no Mind Meld card.
    static func state(for scenario: DeveloperScenario) -> RemoteMindMeldState? {
      openRoundState(for: scenario) ?? revealState(for: scenario) ?? finishedState(for: scenario)
    }

    /// A round that still needs a word, from either person.
    private static func openRoundState(for scenario: DeveloperScenario) -> RemoteMindMeldState? {
      switch scenario {
      case .mindMeldFirstRound:
        return Fixture.state(current: Fixture.game(1, rounds: [Fixture.open(1, game: 1)]), stats: Fixture.noMelds)
      case .mindMeldWrite, .mindMeldWriteAway:
        return Fixture.playing(Fixture.revealedRounds(3) + [Fixture.open(4, partnerLocked: true)])
      case .mindMeldWriteTyping, .gamesHubPartnerHere:
        return Fixture.playing(Fixture.revealedRounds(1) + [Fixture.open(2)])
      case .gamesHubYourTurn:
        return Fixture.playing(Fixture.revealedRounds(1) + [Fixture.open(2, partnerLocked: true)])
      case .mindMeldWaiting, .gamesHubWaiting:
        return Fixture.playing(Fixture.revealedRounds(2) + [Fixture.open(3, mine: "sea")])
      case .mindMeldWaitingOffline:
        // The word is only in the pending queue (`DeveloperMindMeldScenarioView.seed`).
        return Fixture.playing(Fixture.revealedRounds(2) + [Fixture.open(3)])
      default:
        return nil
      }
    }

    /// A round just revealed without a meld, and the game goes on.
    private static func revealState(for scenario: DeveloperScenario) -> RemoteMindMeldState? {
      switch scenario {
      case .mindMeldRevealMiss:
        return Fixture.playing(
          Fixture.revealedRounds(2) + [Fixture.revealed(3, Fixture.trail[2], seen: false), Fixture.open(4)]
        )
      case .mindMeldRevealNear:
        return Fixture.playing(
          Fixture.revealedRounds(2) + [
            Fixture.revealed(3, ("net", "nets"), outcome: .near, seen: false),
            Fixture.open(4),
          ]
        )
      case .mindMeldPartnerRestarted:
        // Robin ended game 4 while Alex was in its round 3. Alex has not seen that yet.
        let earlier = Fixture.currentGameNumber - 1
        let previous = Fixture.game(
          earlier,
          state: .ended,
          rounds: Fixture.revealedRounds(2, game: earlier) + [Fixture.open(3, game: earlier)],
          reason: .restart,
          endedBy: Fixture.partner
        )
        return Fixture.state(current: Fixture.game(rounds: [Fixture.open(1)]), previous: previous)
      default:
        return nil
      }
    }

    /// A game that is over: melded, or out of rounds.
    private static func finishedState(for scenario: DeveloperScenario) -> RemoteMindMeldState? {
      switch scenario {
      case .mindMeldRevealMeld:
        return melded(
          Fixture.revealedRounds(3) + [Fixture.revealed(4, ("boat", "boat"), outcome: .match, seen: false)],
          meldNumber: 3,
          stats: RemoteMindMeldStats(melds: 3, fewestRounds: 3, games: 5)
        )
      case .mindMeldRevealRecord:
        return melded(
          Fixture.revealedRounds(1) + [Fixture.revealed(2, ("fish", "fish"), outcome: .match, seen: false)],
          meldNumber: 3,
          isRecord: true,
          stats: RemoteMindMeldStats(melds: 3, fewestRounds: 2, games: 5)
        )
      case .mindMeldRevealGotAway:
        return Fixture.state(
          current: Fixture.game(
            state: .ended,
            rounds: Fixture.revealedRounds(9) + [Fixture.revealed(10, Fixture.trail[9], seen: false)],
            reason: .rounds
          ),
          stats: RemoteMindMeldStats(melds: 2, fewestRounds: 3, games: 5)
        )
      case .mindMeldOver:
        return melded(
          Fixture.revealedRounds(3) + [Fixture.revealed(4, ("boat", "boat"), outcome: .match)],
          meldNumber: 3,
          endSeen: true,
          stats: RemoteMindMeldStats(melds: 3, fewestRounds: 3, games: 5)
        )
      default:
        return nil
      }
    }

    private static func melded(
      _ rounds: [RemoteMindMeldRound],
      meldNumber: Int,
      isRecord: Bool = false,
      endSeen: Bool = false,
      stats: RemoteMindMeldStats
    ) -> RemoteMindMeldState {
      Fixture.state(
        current: Fixture.game(
          state: .melded,
          rounds: rounds,
          endSeen: endSeen,
          meldNumber: meldNumber,
          isRecord: isRecord
        ),
        stats: stats
      )
    }

    // MARK: Dependencies

    static func cache(for scenario: DeveloperScenario) -> InMemoryMindMeldCache {
      InMemoryMindMeldCache(state: state(for: scenario), ownerUserID: Fixture.me)
    }

    /// The shared overview for the hub scenario where Robin is in both games. Draw &
    /// Guess comes first in the list, as the server sends it, so it stays first.
    /// Nil for every other scenario, which keeps the overview its Draw & Guess state implies.
    static func overview(
      for scenario: DeveloperScenario,
      drawAndGuess state: RemoteDrawAndGuessState
    ) -> RemoteGamesOverview? {
      guard scenario == .gamesHubPartnerHere else { return nil }
      let base = RemoteGamesOverview(drawAndGuess: state)
      return RemoteGamesOverview(
        userID: base.userID,
        partnerUserID: base.partnerUserID,
        coupleID: base.coupleID,
        settings: base.settings,
        presence: base.presence + [
          RemoteGamePresence(
            kind: .mindMeld,
            myPresent: false,
            partnerPresent: true,
            lastInviteAt: nil
          ),
        ]
      )
    }

    // MARK: Live room

    private static func partnerIsHere(in scenario: DeveloperScenario) -> Bool {
      switch scenario {
      case .mindMeldWrite, .mindMeldWriteTyping, .mindMeldWaiting, .mindMeldPartnerRestarted, .gamesHubPartnerHere:
        true
      default:
        false
      }
    }

    private static func partnerIsTyping(in scenario: DeveloperScenario) -> Bool {
      scenario == .mindMeldWriteTyping || scenario == .mindMeldWaiting
    }

    /// The live room, with Robin already in it when the scenario calls for it. No
    /// relay is involved: his messages are fed in directly.
    static func makeLive(for scenario: DeveloperScenario, coupleID: UUID) -> WidgetLiveDrawing? {
      let connection = WidgetLiveConnection(coupleID: coupleID, ticketProvider: { _ in nil })
      let live = WidgetLiveDrawing(
        connection: connection,
        role: .present,
        presence: WidgetLivePresence(countsLatestHelloOnly: true)
      )
      guard partnerIsHere(in: scenario) else { return live }
      join(connection)
      let typingRound = partnerIsTyping(in: scenario) ? state(for: scenario)?.current?.openRound?.roundNumber : nil
      keepPartnerHere(in: live, typingRound: typingRound)
      return live
    }

    /// The relay's welcome, then Robin's hello with the role `present`.
    private static func join(_ connection: WidgetLiveConnection) {
      connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
      connection.onMessage?(
        WidgetLiveMessage(type: .hello, from: "partner", role: WidgetLivePresence.Role.present.rawValue)
      )
    }

    /// Closing the screen stops the room, which drops Robin, so he joins again. The
    /// typing message repeats because the view model forgets it after a few seconds.
    /// The loop ends once the room is gone.
    private static func keepPartnerHere(in live: WidgetLiveDrawing, typingRound: Int?) {
      let typing = typingRound.flatMap { round in
        try? JSONEncoder().encode(
          GameLiveEnvelope(
            game: MindMeldLiveMessage.game,
            message: MindMeldLiveMessage(roundNumber: round, isTyping: true)
          )
        )
      }
      Task { @MainActor [weak live] in
        while let live {
          if live.partnerActivity == .away {
            join(live.connection)
          }
          if let typing {
            live.connection.onGameData?(typing)
          }
          try? await Task.sleep(for: .seconds(2))
        }
      }
    }
  }

  // The protocol is async, and this stand-in answers at once.
  // swiftlint:disable async_without_await

  /// Every call succeeds and changes nothing. The screens already show a move the
  /// moment it is saved in the pending operations. Reads fail, so the cache stays
  /// as the scenario set it.
  struct DeveloperMindMeldGateway: MindMeldGateway {
    /// "Our melds" answers with no games.
    var historyIsEmpty = false

    func loadMindMeld() async throws -> RemoteMindMeldState {
      throw URLError(.notConnectedToInternet)
    }

    func startMindMeldGame() async throws -> RemoteMindMeldStartResult {
      await MainActor.run { RemoteMindMeldStartResult(gameID: DeveloperMindMeldFixture.currentGameID, created: false) }
    }

    func lockMindMeldWord(
      roundID: UUID,
      word _: String,
      operation _: SyncClientOperation
    ) async throws -> RemoteMindMeldLockResult {
      RemoteMindMeldLockResult(
        roundID: roundID,
        roundState: .open,
        outcome: nil,
        gameState: .playing,
        lockedAt: DeveloperGamesFixture.now
      )
    }

    func countMindMeldRound(roundID: UUID) async throws -> RemoteMindMeldCountResult {
      await MainActor.run {
        RemoteMindMeldCountResult(roundID: roundID, gameID: DeveloperMindMeldFixture.currentGameID, gameState: .melded)
      }
    }

    func markMindMeldRevealSeen(roundID: UUID) async throws -> RemoteMindMeldRevealSeenResult {
      RemoteMindMeldRevealSeenResult(roundID: roundID, revealSeenAt: DeveloperGamesFixture.now)
    }

    func markMindMeldEndSeen(gameID: UUID) async throws -> RemoteMindMeldEndSeenResult {
      RemoteMindMeldEndSeenResult(gameID: gameID, endSeenAt: DeveloperGamesFixture.now)
    }

    func restartMindMeld(gameID: UUID) async throws -> RemoteMindMeldStartResult {
      RemoteMindMeldStartResult(gameID: gameID, created: true)
    }

    func loadMindMeldHistory(beforeGameNumber: Int?, limit: Int) async throws -> RemoteMindMeldHistoryPage {
      await MainActor.run { [historyIsEmpty] in
        historyIsEmpty
          ? DeveloperMindMeldFixture.emptyHistoryPage
          : DeveloperMindMeldFixture.historyPage(before: beforeGameNumber, limit: limit)
      }
    }
  }
  // swiftlint:enable async_without_await

  /// A Mind Meld phase on its own screen, or "Our melds". A stack opens the pushed
  /// screens, such as a finished game's trail.
  @MainActor
  struct DeveloperMindMeldScenarioView: View {
    let scenario: DeveloperScenario
    @State private var hub: MindMeldHubModel
    @State private var isReady = false
    @State private var path: [GamesDestination] = []

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      let dependencies = DeveloperGamesScenarioFactory.dependencies(for: scenario)
      let game = MindMeldViewModel(dependencies: dependencies, participants: DeveloperGamesFixture.participants)
      let hub = MindMeldHubModel(dependencies: dependencies, game: game)
      hub.configure(participants: DeveloperGamesFixture.participants)
      _hub = State(initialValue: hub)
    }

    var body: some View {
      NavigationStack(path: $path) {
        if isReady {
          root
            .navigationDestination(for: GamesDestination.self) { destination in
              if let screen = hub.screen(for: destination) {
                screen
              }
            }
        } else {
          Color.paeoniaBackgroundPrimary
        }
      }
      .dismissesKeyboardOnPush(path)
      .task {
        await seed()
        isReady = true
      }
    }

    @ViewBuilder
    private var root: some View {
      switch scenario {
      case .mindMeldHistory, .mindMeldHistoryEmpty:
        MindMeldHistoryScreen(viewModel: hub.history)
      default:
        MindMeldScreen(viewModel: hub.game)
      }
    }

    /// Puts the scenario's unsent move in the queue before the screen reads it. The
    /// word is locked in on the phone, and one send has failed, so the offline line shows.
    private func seed() async {
      guard scenario == .mindMeldWaitingOffline,
        let game = DeveloperMindMeldScenarioFactory.state(for: scenario)?.current,
        let round = game.openRound
      else { return }
      let payload = MindMeldLockPayload(
        roundID: round.id,
        gameID: game.id,
        word: "sea",
        createdAt: DeveloperGamesFixture.now
      )
      guard let data = try? JSONEncoder().encode(payload) else { return }
      let store = hub.game.dependencies.pendingOperationStore
      let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
      try? await store.enqueue(
        PendingSyncOperationRequest(
          ownerUserID: DeveloperGamesFixture.me,
          operation: operation,
          operationKind: .lockMindMeldWord,
          idempotencyScope: "mind-meld-lock:developer",
          requestData: data
        )
      )
      // The drain stores "Retry later" for a send that could not reach the server.
      try? await store.markSending(clientOperationID: operation.id, at: DeveloperGamesFixture.now)
      try? await store.markRetryableFailure(
        clientOperationID: operation.id,
        errorDescription: "Retry later",
        nextRetryAt: nil,
        at: DeveloperGamesFixture.now
      )
    }
  }
#endif
