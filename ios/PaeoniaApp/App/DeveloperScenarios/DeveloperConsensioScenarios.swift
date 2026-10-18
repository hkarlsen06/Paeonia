#if DEBUG
  import Foundation
  import SwiftUI

  /// Fixed Consensio states for the developer scenarios. The pending operations
  /// are in memory, so a move made here changes the screen the way it does on a
  /// phone that is offline.
  @MainActor
  enum DeveloperConsensioScenarioFactory {
    typealias Fixture = DeveloperGamesFixture

    nonisolated static let gameID = UUID(uuidString: "C0C0C0C0-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let roundID = UUID(uuidString: "C0C0C0C0-0000-4000-8000-000000000002") ?? UUID()

    static let choices = [
      topic("camping", "Camping", "Never again", "Book it now"),
      topic("spicy_food", "Spicy food", "Mild, thanks", "The hotter the better"),
      topic("mornings", "Mornings", "Up with the sun", "Five more minutes"),
    ]

    private static func topic(_ id: String, _ subject: String, _ left: String, _ right: String)
      -> RemoteConsensioTopic {
      RemoteConsensioTopic(topicID: id, language: .en, subject: subject, leftEnd: left, rightEnd: right)
    }

    static func game(
      turn: UUID,
      choices: [RemoteConsensioTopic] = [],
      points: Int = 23,
      rounds: Int = 6
    ) -> RemoteConsensioGame {
      RemoteConsensioGame(
        id: gameID,
        turnUserID: turn,
        turnStartedAt: Fixture.now,
        choices: choices,
        sharedPoints: points,
        roundCount: rounds,
        version: 7,
        createdByUserID: Fixture.me,
        createdAt: Fixture.now,
        updatedAt: Fixture.now
      )
    }

    static func round(
      id: UUID = roundID,
      number: Int = 6,
      placer: UUID,
      topic: RemoteConsensioTopic = choices[1],
      spot: Int?,
      guess: Int? = nil,
      seen: Bool = false
    ) -> RemoteConsensioRound {
      let distance = spot.flatMap { spot in guess.map { abs($0 - spot) } }
      return RemoteConsensioRound(
        id: id,
        roundNumber: number,
        placerUserID: placer,
        guesserUserID: placer == Fixture.me ? Fixture.partner : Fixture.me,
        topicID: topic.topicID,
        language: topic.language,
        subject: topic.subject,
        leftEnd: topic.leftEnd,
        rightEnd: topic.rightEnd,
        spot: spot,
        placedAt: Fixture.now.addingTimeInterval(-3_600),
        guess: guess,
        distance: distance,
        points: distance.map(ConsensioRules.points(distance:)),
        guessedAt: guess == nil ? nil : Fixture.now.addingTimeInterval(-60),
        myRevealSeenAt: seen ? Fixture.now : nil
      )
    }

    static func state(game: RemoteConsensioGame?, current: RemoteConsensioRound? = nil) -> RemoteConsensioState {
      RemoteConsensioState(
        userID: Fixture.me,
        partnerUserID: Fixture.partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        dataEpoch: "",
        game: game,
        currentRound: current,
        previousRound: nil
      )
    }

    /// A reveal: the round is guessed, and the points are in the total already.
    private static func reveal(placer: UUID, spot: Int, guess: Int) -> RemoteConsensioState {
      let points = ConsensioRules.points(distance: abs(spot - guess))
      let nextPlacer = placer == Fixture.me ? Fixture.partner : Fixture.me
      return state(
        game: game(turn: nextPlacer, choices: nextPlacer == Fixture.me ? choices : [], points: 23 + points),
        current: round(placer: placer, spot: spot, guess: guess)
      )
    }

    static func state(for scenario: DeveloperScenario) -> RemoteConsensioState? {
      turnState(for: scenario) ?? revealState(for: scenario) ?? hubState(for: scenario)
    }

    private static func turnState(for scenario: DeveloperScenario) -> RemoteConsensioState? {
      switch scenario {
      case .consensioFirstTurn:
        return state(game: game(turn: Fixture.me, choices: choices, points: 0, rounds: 0))
      case .consensioOwnTopic, .consensioPlace:
        return state(
          game: game(turn: Fixture.me, choices: choices),
          current: round(placer: Fixture.partner, topic: choices[2], spot: 30, guess: 36, seen: true)
        )
      case .consensioWaitChoosing:
        return state(
          game: game(turn: Fixture.partner),
          current: round(placer: Fixture.me, spot: 64, guess: 60, seen: true)
        )
      case .consensioWaitLive, .consensioWaitLater:
        return state(game: game(turn: Fixture.partner), current: round(placer: Fixture.me, topic: choices[0], spot: 72))
      case .consensioGuess, .consensioRevealHeld:
        return state(game: game(turn: Fixture.me, choices: choices), current: round(placer: Fixture.partner, spot: nil))
      default:
        return nil
      }
    }

    private static func revealState(for scenario: DeveloperScenario) -> RemoteConsensioState? {
      switch scenario {
      case .consensioRevealSpotOn:
        return reveal(placer: Fixture.partner, spot: 81, guess: 79)
      case .consensioRevealClose:
        return reveal(placer: Fixture.partner, spot: 70, guess: 56)
      case .consensioRevealFar:
        return reveal(placer: Fixture.partner, spot: 82, guess: 41)
      case .consensioRevealPlacer:
        return reveal(placer: Fixture.me, spot: 72, guess: 66)
      default:
        return nil
      }
    }

    private static func hubState(for scenario: DeveloperScenario) -> RemoteConsensioState? {
      switch scenario {
      case .consensioHistory:
        return state(game: game(turn: Fixture.me, choices: choices, points: 31, rounds: 12))
      case .gamesHubYourTurn:
        return state(
          game: game(turn: Fixture.me, choices: choices),
          current: round(placer: Fixture.partner, spot: nil)
        )
      case .gamesHubWaiting:
        return state(game: game(turn: Fixture.partner), current: round(placer: Fixture.me, spot: 72))
      default:
        // The other hub scenarios show the card of a couple that has not played yet.
        return scenario.rawValue.hasPrefix("games-hub") ? state(game: nil) : nil
      }
    }

    static func historyPage() -> RemoteConsensioHistoryPage {
      let spots = [
        (72, 70), (20, 34), (55, 52), (90, 61), (12, 15), (40, 47),
        (66, 66), (8, 30), (50, 44), (85, 80), (30, 18), (61, 59),
      ]
      let topics = choices + [topic("own", "Your mom's waffles", "Not again", "Every Sunday")]
      let rounds = spots.enumerated().map { index, pair in
        round(
          id: UUID(),
          number: 12 - index,
          placer: index.isMultiple(of: 2) ? Fixture.partner : Fixture.me,
          topic: topics[index % topics.count],
          spot: pair.0,
          guess: pair.1,
          seen: true
        )
      }
      return RemoteConsensioHistoryPage(
        rounds: rounds,
        nextBeforeRoundNumber: nil,
        records: RemoteConsensioRecords(
          sharedPoints: 31,
          mine: RemoteConsensioGuesserRecord(guesses: 6, spotOns: 2, averageDistance: 9),
          partner: RemoteConsensioGuesserRecord(guesses: 6, spotOns: 1, averageDistance: 11)
        )
      )
    }

    static func cache(for scenario: DeveloperScenario) -> InMemoryConsensioCache {
      InMemoryConsensioCache(
        state: state(for: scenario),
        history: scenario == .consensioHistory ? historyPage() : nil,
        ownerUserID: Fixture.me
      )
    }

    // MARK: Live room

    /// The role Robin's phone says it is in, or nil when he is away.
    private static func partnerRole(in scenario: DeveloperScenario) -> WidgetLivePresence.Role? {
      switch scenario {
      case .consensioWaitChoosing: .choosing
      case .consensioWaitLive: .watching
      case .consensioGuess, .consensioPlace, .consensioOwnTopic: .present
      default: nil
      }
    }

    /// The live room, with Robin already in it when the scenario calls for it. No
    /// relay is involved: his messages are fed in directly. While he guesses, his
    /// pin sweeps toward the real spot and back.
    static func makeLive(for scenario: DeveloperScenario, coupleID: UUID) -> WidgetLiveDrawing? {
      let connection = WidgetLiveConnection(coupleID: coupleID, ticketProvider: { _ in nil })
      let live = WidgetLiveDrawing(
        connection: connection,
        role: .present,
        presence: WidgetLivePresence(countsLatestHelloOnly: true)
      )
      guard let role = partnerRole(in: scenario) else { return live }
      let sweeps = scenario == .consensioWaitLive
      Task { @MainActor [weak live] in
        var step = 0
        while let live {
          if live.partnerActivity == .away {
            connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
            connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role.rawValue))
          }
          if sweeps {
            // 30 to 80 and back, about two seconds each way.
            let phase = step % 60
            let position = 30 + (phase < 30 ? phase : 60 - phase) * 50 / 30
            let message = ConsensioLiveMessage(roundID: roundID, position: position, touching: true)
            let envelope = GameLiveEnvelope(game: ConsensioLiveMessage.game, message: message)
            if let data = try? JSONEncoder().encode(envelope) {
              live.connection.onGameData?(data)
            }
            step += 1
            try? await Task.sleep(for: .milliseconds(70))
          } else {
            try? await Task.sleep(for: .seconds(2))
          }
        }
      }
      return live
    }
  }

  // The protocol is async, and this stand-in answers at once.
  // swiftlint:disable async_without_await

  /// Every write succeeds and changes nothing, so a move shows the way it does
  /// offline. Reads of the game fail, so the cache stays as the scenario set it.
  struct DeveloperConsensioGateway: ConsensioGateway {
    struct Offline: Error {}

    func loadConsensio() async throws -> RemoteConsensioState {
      throw Offline()
    }

    func ensureConsensioGame() async throws -> RemoteConsensioEnsureResult {
      RemoteConsensioEnsureResult(gameID: DeveloperConsensioScenarioFactory.gameID, created: false)
    }

    func placeConsensioSpot(
      roundID _: UUID,
      roundNumber _: Int,
      topic _: ConsensioTopicChoice,
      spot _: Int,
      operation _: SyncClientOperation
    ) async throws -> RemoteConsensioRound {
      throw Offline()
    }

    func guessConsensioSpot(roundID _: UUID, guess _: Int, operation _: SyncClientOperation) async throws
      -> RemoteConsensioRound {
      throw Offline()
    }

    func markConsensioRevealSeen(roundID: UUID) async throws -> RemoteConsensioRevealSeenResult {
      RemoteConsensioRevealSeenResult(roundID: roundID, revealSeenAt: DeveloperGamesFixture.now)
    }

    func loadConsensioHistory(beforeRoundNumber _: Int?, limit _: Int) async throws -> RemoteConsensioHistoryPage {
      await MainActor.run { DeveloperConsensioScenarioFactory.historyPage() }
    }
  }
  // swiftlint:enable async_without_await

  /// A Consensio phase on its own screen, or "What we know".
  @MainActor
  struct DeveloperConsensioScenarioView: View {
    let scenario: DeveloperScenario
    @State private var hub: ConsensioHubModel
    @State private var isReady = false

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      let dependencies = DeveloperGamesScenarioFactory.dependencies(for: scenario)
      let game = ConsensioViewModel(dependencies: dependencies, participants: DeveloperGamesFixture.participants)
      let hub = ConsensioHubModel(dependencies: dependencies, game: game)
      hub.configure(participants: DeveloperGamesFixture.participants)
      _hub = State(initialValue: hub)
    }

    var body: some View {
      NavigationStack {
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
      .task {
        await seed()
        isReady = true
        await arrange()
      }
    }

    @ViewBuilder
    private var root: some View {
      if scenario == .consensioHistory {
        ConsensioHistoryScreen(viewModel: hub.history)
      } else {
        ConsensioScreen(viewModel: hub.game)
      }
    }

    /// Puts the held guess in the queue, with one failed send, before the screen reads it.
    private func seed() async {
      guard scenario == .consensioRevealHeld else { return }
      let payload = ConsensioGuessPayload(
        roundID: DeveloperConsensioScenarioFactory.roundID,
        guess: 58,
        createdAt: DeveloperGamesFixture.now
      )
      guard let data = try? JSONEncoder().encode(payload) else { return }
      let store = hub.game.dependencies.pendingOperationStore
      let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
      try? await store.enqueue(
        PendingSyncOperationRequest(
          ownerUserID: DeveloperGamesFixture.me,
          operation: operation,
          operationKind: .guessConsensioSpot,
          idempotencyScope: "consensio-guess:developer",
          requestData: data
        )
      )
      try? await store.markSending(clientOperationID: operation.id, at: DeveloperGamesFixture.now)
      try? await store.markRetryableFailure(
        clientOperationID: operation.id,
        errorDescription: "Retry later",
        nextRetryAt: nil,
        at: DeveloperGamesFixture.now
      )
    }

    /// Opens the part of the topic screen the scenario names, once the screen has read its state.
    private func arrange() async {
      try? await Task.sleep(for: .milliseconds(400))
      let game = hub.game
      switch scenario {
      case .consensioOwnTopic:
        game.openOwnTopic()
      case .consensioPlace:
        game.select(.catalog(DeveloperConsensioScenarioFactory.choices[0]))
        game.startPlacing()
      default:
        break
      }
    }
  }
#endif
