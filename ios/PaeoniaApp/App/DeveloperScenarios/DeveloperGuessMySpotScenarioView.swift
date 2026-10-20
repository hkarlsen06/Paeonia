#if DEBUG
  import Foundation
  import SwiftUI

  /// One round of "Our places".
  private struct Place {
    let name: String
    let spot: GuessMySpotCoordinate
    let day: String
    let guess: GuessMySpotCoordinate
  }

  extension DeveloperGuessMySpotScenarioFactory {
    static func history() -> RemoteGuessMySpotHistory {
      let rounds = historyPlaces.enumerated().map { index, place in
        var entry = round(
          id: UUID(),
          number: 12 - index,
          sender: index.isMultiple(of: 2) ? Fixture.partner : Fixture.me,
          photo: index.isMultiple(of: 2) ? lakeAssetID : harborAssetID,
          spot: place.spot,
          place: place.name,
          takenOn: place.day,
          guess: place.guess,
          seen: true
        )
        // Alex may delete the photos Alex sent.
        entry.canDelete = entry.senderUserID == Fixture.me
        return entry
      }
      return RemoteGuessMySpotHistory(
        rounds: rounds,
        records: RemoteGuessMySpotRecords(
          sharedPoints: 48_210,
          myPoints: 25_180,
          partnerPoints: 23_030,
          mine: RemoteGuessMySpotGuesserRecord(guesses: 6, closestM: 240, averageM: 118_000),
          partner: RemoteGuessMySpotGuesserRecord(guesses: 6, closestM: 1_200, averageM: 96_000)
        )
      )
    }

    private static let historyPlaces: [Place] = [
      Place(name: "Bergen, Norway", spot: bergen, day: "2025-07-14",
            guess: Spot(latitude: 60.39, longitude: 5.34)),
      Place(name: "Gjende, Norway", spot: lake, day: "2024-08-03",
            guess: Spot(latitude: 61.2, longitude: 8.9)),
      Place(name: "Oslo, Norway", spot: Spot(latitude: 59.9139, longitude: 10.7522), day: "2025-03-02",
            guess: Spot(latitude: 59.92, longitude: 10.73)),
      Place(name: "Tromsø, Norway", spot: Spot(latitude: 69.6492, longitude: 18.9553), day: "2024-12-20",
            guess: Spot(latitude: 68.8, longitude: 16.5)),
      Place(name: "Copenhagen, Denmark", spot: Spot(latitude: 55.6761, longitude: 12.5683), day: "2025-05-09",
            guess: Spot(latitude: 55.6, longitude: 12.9)),
      Place(name: "Lisbon, Portugal", spot: Spot(latitude: 38.7223, longitude: -9.1393), day: "2024-04-18",
            guess: Spot(latitude: 40.4168, longitude: -3.7038)),
      Place(name: "Rome, Italy", spot: Spot(latitude: 41.9028, longitude: 12.4964), day: "2023-09-11",
            guess: Spot(latitude: 41.89, longitude: 12.48)),
      Place(name: "Stavanger, Norway", spot: Spot(latitude: 58.97, longitude: 5.7331), day: "2025-06-01",
            guess: Spot(latitude: 59.4, longitude: 5.3)),
      Place(name: "Edinburgh, United Kingdom", spot: Spot(latitude: 55.9533, longitude: -3.1883),
            day: "2024-10-27",
            guess: Spot(latitude: 51.5, longitude: -0.12)),
      Place(name: "Trondheim, Norway", spot: Spot(latitude: 63.4305, longitude: 10.3951), day: "2025-01-15",
            guess: Spot(latitude: 63.43, longitude: 10.4)),
      Place(name: "Berlin, Germany", spot: Spot(latitude: 52.52, longitude: 13.405), day: "2023-12-02",
            guess: Spot(latitude: 52.4, longitude: 13.1)),
      Place(name: "Ålesund, Norway", spot: Spot(latitude: 62.4722, longitude: 6.1495), day: "2025-08-22",
            guess: Spot(latitude: 62.0, longitude: 6.8)),
    ]
  }

  /// Serves the two scenario photos by their asset ids, and the board games photo otherwise.
  nonisolated struct DeveloperGuessMySpotPhotoProvider: MemoryMediaImageProviding {
    let fallback: (any MemoryMediaImageProviding)?

    func imageData(for mediaAssetID: UUID?) async -> Data? {
      switch mediaAssetID {
      case DeveloperGuessMySpotScenarioFactory.harborAssetID:
        await MainActor.run { DeveloperGuessMySpotScenarioFactory.photoData(.guessMySpotScenarioHarbor) }
      case DeveloperGuessMySpotScenarioFactory.lakeAssetID:
        await MainActor.run { DeveloperGuessMySpotScenarioFactory.photoData(.guessMySpotScenarioLake) }
      default:
        await fallback?.imageData(for: mediaAssetID)
      }
    }
  }

  // The protocol is async, and this stand-in answers at once.
  // swiftlint:disable async_without_await

  /// Every write fails like an offline phone and changes nothing, so a move shows
  /// the way it does offline. Reads of the game fail, so the cache stays as the
  /// scenario set it.
  struct DeveloperGuessMySpotGateway: GuessMySpotGateway {
    struct Offline: Error {}

    func loadGuessMySpot() async throws -> RemoteGuessMySpotState {
      throw Offline()
    }

    func ensureGuessMySpotGame() async throws -> RemoteGuessMySpotEnsureResult {
      RemoteGuessMySpotEnsureResult(gameID: DeveloperGuessMySpotScenarioFactory.gameID, created: false)
    }

    func uploadGuessMySpotPhoto( // swiftlint:disable:this function_parameter_count
      _: Data,
      width _: Int,
      height _: Int,
      roundID _: UUID,
      coupleID _: UUID,
      reserve _: SyncClientOperation,
      finalize _: SyncClientOperation
    ) async throws -> UUID {
      throw Offline()
    }

    func sendGuessMySpotPhoto(
      _: GuessMySpotSendDetails,
      mediaAssetID _: UUID,
      operation _: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
      throw Offline()
    }

    func submitGuessMySpotGuess(
      roundID _: UUID,
      guess _: GuessMySpotCoordinate,
      operation _: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
      throw Offline()
    }

    func markGuessMySpotRevealSeen(roundID: UUID) async throws -> RemoteGuessMySpotRevealSeenResult {
      RemoteGuessMySpotRevealSeenResult(roundID: roundID, revealSeenAt: DeveloperGamesFixture.now)
    }

    func loadGuessMySpotHistory() async throws -> RemoteGuessMySpotHistory {
      await MainActor.run { DeveloperGuessMySpotScenarioFactory.history() }
    }

    func deleteGuessMySpotRound(roundID: UUID, operation _: SyncClientOperation) async throws
      -> RemoteGuessMySpotDeleteResult {
      RemoteGuessMySpotDeleteResult(roundID: roundID, deletedAt: DeveloperGamesFixture.now)
    }
  }
  // swiftlint:enable async_without_await

  /// A Guess my spot phase on its own screen, or "Our places".
  @MainActor
  struct DeveloperGuessMySpotScenarioView: View {
    let scenario: DeveloperScenario
    @State private var hub: GuessMySpotHubModel
    @State private var isReady = false

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      let dependencies = DeveloperGamesScenarioFactory.dependencies(for: scenario)
      let game = GuessMySpotViewModel(dependencies: dependencies, participants: DeveloperGamesFixture.participants)
      let hub = GuessMySpotHubModel(dependencies: dependencies, game: game)
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
      if scenario == .guessMySpotHistory {
        GuessMySpotHistoryScreen(viewModel: hub.history)
      } else {
        GuessMySpotScreen(viewModel: hub.game)
      }
    }

    /// Puts the held guess in the queue, with one failed send, before the screen reads it.
    private func seed() async {
      guard scenario == .guessMySpotRevealHeld else { return }
      let payload = GuessMySpotGuessPayload(
        roundID: DeveloperGuessMySpotScenarioFactory.roundID,
        guess: GuessMySpotCoordinate(latitude: 61.1, longitude: 8.2),
        createdAt: DeveloperGamesFixture.now
      )
      guard let data = try? JSONEncoder().encode(payload) else { return }
      let store = hub.game.dependencies.pendingOperationStore
      let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
      try? await store.enqueue(
        PendingSyncOperationRequest(
          ownerUserID: DeveloperGamesFixture.me,
          operation: operation,
          operationKind: .guessMySpotGuess,
          idempotencyScope: "guess-my-spot-guess:developer",
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

    /// Opens the check the scenario names, once the screen has read its state.
    private func arrange() async {
      try? await Task.sleep(for: .milliseconds(400))
      switch scenario {
      case .guessMySpotCheckFound:
        hub.game.draft = DeveloperGuessMySpotScenarioFactory.draft(spot: DeveloperGuessMySpotScenarioFactory.bergen)
      case .guessMySpotCheckMissing:
        hub.game.draftStartArea = await hub.game.dependencies.guessMySpotHomeArea.homeArea(
          ownerUserID: DeveloperGamesFixture.me,
          coupleID: nil
        )
        hub.game.draft = DeveloperGuessMySpotScenarioFactory.draft(spot: nil)
      default:
        if DeveloperGuessMySpotScenarioFactory.stagedReveals.contains(scenario) {
          await playStagedReveal()
        }
      }
    }

    /// Drops the guess pin on the guess screen, as if Alex tapped, then lets the
    /// server's answer arrive. The guess map shows the whole world, so the reveal
    /// opens on the guess at about 300 km across.
    private func playStagedReveal() async {
      guard let revealed = DeveloperGuessMySpotScenarioFactory.revealed(for: scenario),
            let guess = revealed.currentRound?.guess
      else { return }
      let game = hub.game
      game.dropGuess(at: guess)
      try? await Task.sleep(for: .seconds(2))
      await game.dependencies.guessMySpotCache.saveState(revealed, ownerUserID: DeveloperGamesFixture.me)
      await game.reload()
    }
  }
  /// "Our places" from the Memories tab, with the memory fixtures and the Guess my spot
  /// rounds of "Our guesses".
  struct DeveloperMemoriesMapWithGameScenarioView: View {
    @State private var memories: MemoriesViewModel
    @State private var rounds: GuessMySpotHistoryViewModel

    init() {
      DeveloperMemoriesMapFixture.seedPhotos()
      DeveloperGuessMySpotScenarioFactory.seedPhotosForMemoriesMap()
      _memories = State(initialValue: MemoriesViewModel(
        memoryService: DeveloperScenarioMemoryDataService(
          records: DeveloperMemoriesMapFixture.records(withPlaces: true)
        ),
        operationProvider: DeveloperScenarioOperationProvider(),
        mediaUploader: nil,
        mediaImageCache: nil
      ))
      let rounds = GuessMySpotHistoryViewModel(
        dependencies: DeveloperGamesScenarioFactory.dependencies(for: .guessMySpotHistory),
        participants: DeveloperGamesFixture.participants
      )
      _rounds = State(initialValue: rounds)
    }

    var body: some View {
      NavigationStack {
        if memories.hasLoadedOnce {
          MemoriesMapScreen(
            viewModel: memories,
            currentUserID: DeveloperScenarioFixture.currentUserID,
            gameRounds: rounds
          )
        }
      }
      .task {
        await memories.configure(
          currentUserID: DeveloperScenarioFixture.currentUserID,
          coupleID: DeveloperScenarioFixture.coupleID
        )
      }
    }
  }

  extension DeveloperGuessMySpotScenarioFactory {
    /// The two scenario photos in the shared media cache, where the memory map's pins read them.
    static func seedPhotosForMemoriesMap() {
      let directory = MemoryMediaImageDiskCache.defaultDirectoryURL()
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let photos: [(UUID, ImageResource)] = [
        (harborAssetID, .guessMySpotScenarioHarbor),
        (lakeAssetID, .guessMySpotScenarioLake),
      ]
      for (assetID, resource) in photos {
        let file = directory.appendingPathComponent(assetID.uuidString.lowercased())
        try? photoData(resource).write(to: file, options: .atomic)
      }
    }
  }
#endif
