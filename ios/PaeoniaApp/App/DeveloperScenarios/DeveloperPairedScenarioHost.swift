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
    private let locationViewModel: LocationMapViewModel

    init(scenario: DeveloperScenario) {
      let operationProvider = DeveloperScenarioOperationProvider()
      let dailyService = DeveloperDailyChallengeService(mode: .mode(for: scenario))
      let pendingOperationStore: any PendingSyncOperationPersisting =
        scenario == .questionsOfflineQueued
        ? DeveloperScenarioOfflineDailyOperationStore()
        : InMemoryPendingSyncOperationRepository()
      let memoryRecords =
        scenario == .memoriesPopulated
        ? DeveloperScenarioFixture.memoryRecords()
        : []

      switch scenario {
      case .questions, .questionsPartial, .questionsRevealed, .questionsEmpty,
        .questionsLoading, .questionsError, .questionAnswerFlow:
        _selection = State(initialValue: .questions)
      case .memoriesEmpty, .memoriesPopulated:
        _selection = State(initialValue: .memories)
      default:
        _selection = State(initialValue: .home)
      }
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
          snapshotCache: DeveloperScenarioSnapshotCache()
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
        initialValue: MemoriesViewModel(
          memoryService: DeveloperScenarioMemoryDataService(records: memoryRecords),
          operationProvider: operationProvider,
          mediaUploader: nil,
          mediaImageCache: nil
        )
      )
      locationViewModel = LocationMapViewModel(
        visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
        ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: operationProvider,
        locationCapture: DeveloperScenarioLocationCapture()
      )
    }

    var body: some View {
      MainTabView(
        tabs: [.home, .questions, .memories],
        currentUserID: DeveloperScenarioFixture.currentUserID,
        currentDisplayName: "Alex",
        currentProfilePhotoAssetID: nil,
        currentCustomProfilePhotoAssetID: nil,
        currentProviderProfilePhotoAssetID: nil,
        currentAuthProvider: .development,
        partnerUserID: DeveloperScenarioFixture.partnerUserID,
        partnerDisplayName: "Robin",
        partnerProfilePhotoAssetID: nil,
        authorName: "Alex",
        coupleID: DeveloperScenarioFixture.coupleID,
        relationshipStartedOn: "2025-09-14",
        locationMapState: .partnerUnknown(.notSharing),
        locationViewModel: locationViewModel,
        selection: $selection,
        widgetDrawingPresented: .constant(false),
        deepLink: $deepLink,
        onOpenWidgetDrawing: {},
        dailyChallengeViewModel: dailyChallengeViewModel,
        milestoneViewModel: milestoneViewModel,
        memoriesViewModel: memoriesViewModel
      )
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
    func captureCurrentLocation() async throws -> LocationPoint {
      throw ForegroundLocationCaptureError.unavailable
    }
  }
#endif
