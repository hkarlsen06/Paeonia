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
      let dailyService = DeveloperDailyChallengeService(mode: .mode(for: scenario))
      let pendingOperationStore: any PendingSyncOperationPersisting =
        scenario == .questionsOfflineQueued
        ? DeveloperScenarioOfflineDailyOperationStore()
        : InMemoryPendingSyncOperationRepository()
      _selection = State(initialValue: Self.initialTab(for: scenario))
      _deepLink = State(
        initialValue: scenario == .questionAnswerFlow
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

    private static func makeMemoriesViewModel(
      scenario: DeveloperScenario,
      operationProvider: DeveloperScenarioOperationProvider
    ) -> MemoriesViewModel {
      MemoriesViewModel(
        memoryService: DeveloperScenarioMemoryDataService(
          records: scenario == .memoriesPopulated ? DeveloperScenarioFixture.memoryRecords() : []
        ),
        operationProvider: operationProvider,
        mediaUploader: nil,
        mediaImageCache: nil
      )
    }

    private static func initialTab(for scenario: DeveloperScenario) -> MainTab {
      switch scenario {
      case .questions, .questionsPartial, .questionsRevealed, .questionsEmpty,
        .questionsLoading, .questionsError, .questionAnswerFlow:
        .questions
      case .memoriesEmpty, .memoriesPopulated:
        .memories
      case .gamesSetup, .gamesPartnerPicked, .gamesHubYourTurn, .gamesHubWaiting,
        .gamesHubPartnerHere, .exquisiteCorpseHubYourTurn, .exquisiteCorpseHubPartnerDrawing,
        .exquisiteCorpseHubReveal, .exquisiteCorpseHubNotStarted, .gamesHubBoardGames:
        .games
      default:
        .home
      }
    }

    private static func makeLocationViewModel(
      operationProvider: DeveloperScenarioOperationProvider
    ) -> LocationMapViewModel {
      LocationMapViewModel(
        visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
        ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: operationProvider,
        locationCapture: DeveloperScenarioLocationCapture()
      )
    }

    @ViewBuilder
    var body: some View {
      if scenario == .questionAnswerFlow {
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
          }
      } else {
        MainTabView(
          tabs: [.home, .questions, .games, .memories],
          identity: MainTabIdentity(
            currentUserID: DeveloperScenarioFixture.currentUserID,
            currentDisplayName: "Alex",
            currentAuthProvider: .development,
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            partnerDisplayName: "Robin",
            coupleID: DeveloperScenarioFixture.coupleID,
            relationshipStartedOn: "2025-09-14"
          ),
          locationMapState: .partnerUnknown(.notSharing),
          locationViewModel: locationViewModel,
          selection: $selection,
          widgetDrawingPresented: .constant(false),
          deepLink: $deepLink,
          dependencies: RootFeatureDependencies(
            dailyChallengeViewModel: dailyChallengeViewModel,
            milestoneViewModel: milestoneViewModel,
            memoriesViewModel: memoriesViewModel,
            gamesViewModel: gamesViewModel
          )
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
