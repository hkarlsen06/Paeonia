#if DEBUG
  import Foundation
  import SwiftUI

  @MainActor
  struct DeveloperPairedScenarioHost: View {
    @State private var selection: MainTab
    @State private var deepLink: PaeoniaDeepLink?
    @State private var dailyChallengeViewModel: DailyChallengeViewModel
    @State private var milestoneViewModel: RelationshipMilestoneViewModel
    @State private var memoriesViewModel: MemoriesViewModel
    @State private var gamesViewModel: GamesViewModel
    private let locationViewModel: LocationMapViewModel
    private let scenario: DeveloperScenario

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      let operationProvider = DeveloperScenarioOperationProvider()
      let pendingOperationStore: any PendingSyncOperationPersisting =
        scenario == .questionsOfflineQueued
        ? DeveloperOfflineDailyOperationStore()
        : InMemoryPendingSyncOperationRepository()
      let dailyService = DeveloperDailyChallengeService(
        mode: .mode(for: scenario), pendingOperationStore: pendingOperationStore)
      _selection = State(initialValue: Self.initialTab(for: scenario))
      _deepLink = State(
        initialValue: Self.opensAnswerFlow(scenario)
          ? .dailyToday(coupleDayID: DeveloperScenarioDailyFixture.coupleDayID)
          : nil
      )

      _dailyChallengeViewModel = State(
        initialValue: DailyChallengeViewModel(
          service: dailyService,
          operationProvider: operationProvider,
          draftStore: DeveloperScenarioDailyDraftStore(),
          mediaDraftStore: DeveloperScenarioMediaDraftStore(),
          pendingOperationStore: pendingOperationStore,
          snapshotCache: DeveloperScenarioSnapshotCache(),
          now: { DeveloperScenarioFixture.now }
        )
      )
      _milestoneViewModel = State(
        initialValue: RelationshipMilestoneViewModel(
          dataService: RelationshipStartedOnDataService(
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
          ),
          operationProvider: operationProvider
        )
      )
      _memoriesViewModel = State(
        initialValue: Self.makeMemoriesViewModel(scenario: scenario, operationProvider: operationProvider)
      )
      _gamesViewModel = State(initialValue: DeveloperGamesScenarioFactory.gamesViewModel(for: scenario))
      locationViewModel = Self.makeLocationViewModel(operationProvider: operationProvider)
    }

    /// Scenarios that show the answer flow on its own, for today's question.
    private static func opensAnswerFlow(_ scenario: DeveloperScenario) -> Bool {
      scenario == .questionAnswerFlow || scenario == .questionPartnerAnswersMeanwhile
    }

    private static func makeMemoriesViewModel(
      scenario: DeveloperScenario,
      operationProvider: DeveloperScenarioOperationProvider
    ) -> MemoriesViewModel {
      MemoriesViewModel(
        memoryService: DeveloperScenarioMemoryDataService(records: memoryRecords(for: scenario)),
        operationProvider: operationProvider,
        mediaUploader: nil,
        mediaImageCache: nil
      )
    }

    private static func memoryRecords(for scenario: DeveloperScenario) -> [MemoryRecord] {
      switch scenario {
      case .memoriesPopulated:
        return DeveloperScenarioFixture.memoryRecords()
      case .memoriesCards:
        return DeveloperMemoryCardFixture.records()
      case .memoriesMapTab:
        DeveloperMemoriesMapFixture.seedPhotos()
        return DeveloperMemoriesMapFixture.records(withPlaces: true)
      default:
        return []
      }
    }

    private static func initialTab(for scenario: DeveloperScenario) -> MainTab {
      switch scenario {
      case .questions, .questionsPartial, .questionsRevealed, .questionsEmpty,
        .questionsLoading, .questionsError, .questionsHistory, .questionAnswerFlow,
        .questionPartnerAnswersMeanwhile:
        .questions
      case .memoriesEmpty, .memoriesPopulated, .memoriesCards, .memoriesMapTab:
        .memories
      case .gamesSetup, .gamesPartnerPicked, .gamesHubYourTurn, .gamesHubWaiting, .gamesHubReveal,
        .gamesHubPartnerHere, .exquisiteCorpseHubYourTurn, .exquisiteCorpseHubPartnerDrawing,
        .exquisiteCorpseHubReveal, .exquisiteCorpseHubNotStarted, .gamesHubBoardGames:
        .games
      default:
        .home
      }
    }

    /// PROTOTYPE: the Home map's other states, by name, for screenshots.
    private static var protoMapState: CoupleMapState? {
      switch UserDefaults.standard.string(forKey: "proto.home.mapState") {
      case "loading": .loading
      case "currentUnknown": .currentUnknown
      case "locatingCurrent": .locatingCurrent
      case "currentLocationMissing": .currentLocationMissing
      case "sharingPaused": .sharingPaused(until: .now.addingTimeInterval(3 * 3_600))
      case "locationAccessOff": .locationAccessOff
      case "waitingForPartnerLocation": .waitingForPartnerLocation
      case "partnerNotSharing": .partnerUnknown(.notSharing)
      case "relationshipEnded": .partnerUnknown(.relationshipEnded)
      case "unavailable": .partnerUnknown(.unknown("prototype"))
      default: nil
      }
    }

    private static func makeLocationViewModel(
      operationProvider: DeveloperScenarioOperationProvider
    ) -> LocationMapViewModel {
      LocationMapViewModel(
        visibilityStore: InMemoryLocationVisibilityRepository(),
        ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: operationProvider,
        locationCapture: DeveloperScenarioLocationCapture()
      )
    }

    @ViewBuilder
    var body: some View {
      if Self.opensAnswerFlow(scenario) {
        DailyChallengeAnswerFlow(viewModel: dailyChallengeViewModel)
          .task {
            await dailyChallengeViewModel.configure(
              participants: DailyChallengeParticipants(
                currentUserID: DeveloperScenarioFixture.currentUserID,
                currentDisplayName: "Alex",
                partnerUserID: DeveloperScenarioFixture.partnerUserID,
                partnerDisplayName: "Robin"
              )
            )
            if UserDefaults.standard.bool(forKey: "paeonia-answer-seeded"),
              let question = dailyChallengeViewModel.snapshot.todayQuestion,
              question.answerKinds.contains(.photo)
            {
              await dailyChallengeViewModel.stagePhoto(
                DeveloperGuessMySpotScenarioFactory.photoData(.guessMySpotScenarioLake), for: question.id
              )
            }
          }
      } else {
        MainTabView(
          tabs: [.home, .questions, .games, .memories],
          identity: MainTabIdentity(
            currentUserID: DeveloperScenarioFixture.currentUserID,
            currentDisplayName: "Alex",
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            partnerName: PartnerName(accountName: "Robin", nickname: nil),
            pairID: scenario.firstStepsProgress == nil ? nil : DeveloperLocalFlowIDs.pairID,
            coupleID: DeveloperScenarioFixture.coupleID,
            relationshipStartedOn: "2025-09-14",
            accessNotice: scenario.accessNotice
          ),
          // PROTOTYPE: a live map for the Home map layout, or the state named by
          // `-proto.home.mapState`.
          locationMapState: Self.protoMapState ?? .ready(
            current: LocationPoint(latitude: 59.9139, longitude: 10.7522, capturedAt: .now.addingTimeInterval(-60)),
            partner: LocationPoint(latitude: 59.9142, longitude: 10.7530, capturedAt: .now.addingTimeInterval(-7_200)),
            partnerWasStaleAtLastRefresh: false
          ),
          locationViewModel: locationViewModel,
          selection: $selection,
          widgetDrawingPresented: .constant(false),
          deepLink: $deepLink,
          dependencies: RootFeatureDependencies(
            dailyChallengeViewModel: dailyChallengeViewModel,
            milestoneViewModel: milestoneViewModel,
            memoriesViewModel: memoriesViewModel,
            gamesViewModel: gamesViewModel
          ),
          // Past the first day with a saved card, for the `home-first-steps` scenarios.
          pairingCelebrationStore: DeveloperLocalFlowCelebrationStore(firstSteps: scenario.firstStepsProgress)
        )
      }
    }
  }

  @MainActor
  private final class DeveloperScenarioDailyDraftStore: DailyChallengeDraftStoring {
    private var storage: [UUID: [UUID: DailyAnswerDraft]] = [:]

    func drafts(for userID: UUID) -> [UUID: DailyAnswerDraft] {
      storage[userID] ?? [:]
    }

    func setDraft(_ draft: DailyAnswerDraft, for instanceID: UUID, userID: UUID) {
      storage[userID, default: [:]][instanceID] = draft.hasContent ? draft : nil
    }

    func clearDraft(for instanceID: UUID, userID: UUID) {
      storage[userID]?[instanceID] = nil
    }
  }

  private final class DeveloperScenarioMediaDraftStore:
    DailyAnswerMediaDraftStoring,
    @unchecked Sendable
  {
    private let lock = NSLock()
    private var storage: [UUID: Data] = [:]

    func writeStagedMedia(_ data: Data, instanceID: UUID) throws {
      lock.withLock { storage[instanceID] = data }
    }

    func stagedMediaData(instanceID: UUID) -> Data? {
      lock.withLock { storage[instanceID] }
    }

    func removeStagedMedia(instanceID: UUID) {
      lock.withLock { storage[instanceID] = nil }
    }

    func clearAll() {
      lock.withLock { storage.removeAll() }
    }
  }

  private struct DeveloperScenarioSnapshotCache: DailyChallengeSnapshotCaching {
    func load(ownerUserID _: UUID) -> DailyChallengeRemoteSnapshotRow? { nil }
    func save(_: DailyChallengeRemoteSnapshotRow, ownerUserID _: UUID) {}
    func clearAll() {}
  }

  @MainActor
  private final class DeveloperScenarioLocationCapture: ForegroundLocationCapturing {
    // swiftlint:disable:next async_without_await
    func captureCurrentLocation() async throws -> LocationPoint {
      throw ForegroundLocationCaptureError.unavailable
    }
  }
#endif
