#if DEBUG
  import Foundation
  import SwiftUI

  /// Interactive, entirely local app journey driven through the production root.
  /// External systems are replaced, while routing and feature views stay real.
  @MainActor
  struct DeveloperLocalFlowHost: View {
    let seed: DeveloperLocalFlowSeed

    @State private var deepLink: PaeoniaDeepLink?
    @State private var pendingInviteCode: String?
    @State private var environment: DeveloperLocalFlowEnvironment

    init(seed: DeveloperLocalFlowSeed, homeLaunch: DeveloperHomeLaunchTiming? = nil, gameConversation: Bool = false) {
      self.seed = seed
      _environment = State(
        initialValue: DeveloperLocalFlowEnvironment(
          seed: seed, homeLaunch: homeLaunch, gameConversation: gameConversation))
    }

    var body: some View {
      RootView(
        deepLink: $deepLink,
        pendingJoinInviteCode: $pendingInviteCode,
        viewModel: environment.rootViewModel,
        locationViewModel: environment.locationViewModel,
        appleSignInProvider: environment.appleSignInProvider,
        widgetCanvasService: environment.widgetCanvasService,
        widgetCanvasSync: NoOpWidgetCanvasSync(),
        pushAuthorization: DeveloperScenarioPushAuthorization(denied: false),
        pushPermissionPrimerStore: DeveloperLocalFlowPrimerStore(),
        locationSharingPrimerStore: DeveloperLocalFlowLocationPrimerStore(),
        widgetPushRegistration: NoOpWidgetPushRegistration(),
        partnerAvatarSharing: DeveloperLocalFlowPartnerAvatarSharing(),
        featureDependencies: environment.featureDependencies,
        allowsSystemIntegrations: false
      )
      .task(id: environment.rootViewModel.state) {
        guard environment.rootViewModel.state == .paired else { return }
        await environment.prepareHomeLaunch()
      }
    }
  }

  nonisolated enum DeveloperLocalFlowSeed: String, Sendable {
    case fresh
    case onboarding
    case paywall
    case pairing
    case paired
  }

  @MainActor
  private final class DeveloperLocalFlowEnvironment {
    let rootViewModel: RootViewModel
    let locationViewModel: LocationMapViewModel
    let appleSignInProvider = DeveloperLocalFlowAppleSignInProvider()
    let widgetCanvasService: DeveloperWidgetCanvasService
    let featureDependencies: RootFeatureDependencies
    private let homeLaunch: DeveloperHomeLaunchTiming?
    private let visibilityStore = InMemoryLocationVisibilityRepository()
    private let ownLocationStore = InMemoryOwnLocationSnapshotRepository()

    // This is the single Debug composition boundary for the full local app graph.
    // swiftlint:disable:next function_body_length
    init(seed: DeveloperLocalFlowSeed, homeLaunch: DeveloperHomeLaunchTiming?, gameConversation: Bool) {
      self.homeLaunch = homeLaunch
      let store = DeveloperLocalFlowStore(seed: seed)
      let authService = DeveloperLocalFlowAuthService(store: store)
      let accessService = DeveloperLocalFlowAccessService(store: store)
      let pairingService = DeveloperLocalFlowPairingService(store: store)
      let operationProvider = DeveloperScenarioOperationProvider()
      let inviteStore = DeveloperScenarioInviteStore()
      let pendingOperationStore = InMemoryPendingSyncOperationRepository()
      let gameFlow = gameConversation ? DeveloperGameConversationFlow(pending: pendingOperationStore) : nil
      let accessSnapshotStore = InMemoryAccessSyncSnapshotRepository()
      let storeKitService = DeveloperScenarioStoreKitService()
      let widgetCanvasService = DeveloperWidgetCanvasService()
      self.widgetCanvasService = widgetCanvasService
      // The first drawing's "not sent yet" markers: the welcome flow's before sign-in,
      // and the widget's, which the invite screen sends from. Every local flow starts
      // without them.
      let welcomePendingUploads = WidgetPendingUploadStore(
        defaults: DeveloperInviterFixture.defaults,
        key: WelcomeDrawingStorage.pendingUploadKey
      )
      welcomePendingUploads.clearAll()
      let pendingUploads = WidgetPendingUploadStore(defaults: DeveloperInviterFixture.defaults)
      pendingUploads.clearAll()
      let firstDayStartedOnQueue = FirstDayStartedOnQueue(
        pendingOperationStore: pendingOperationStore,
        operationProvider: operationProvider
      )

      let syncService: any PaeoniaSyncing
      if let gameFlow { syncService = gameFlow.sync } else { syncService = DeveloperLocalFlowSyncService() }
      rootViewModel = RootViewModel(
        syncService: syncService,
        authService: authService,
        accessRouteService: accessService,
        accessSnapshotStore: accessSnapshotStore,
        inviteStore: inviteStore,
        pairingCelebrationStore: DeveloperLocalFlowCelebrationStore(
          firstSteps: homeLaunch != nil ? HomeFirstStepsProgress(isClosed: true)
            : seed == .paired ? HomeFirstStepsProgress(doneSteps: [.game, .topic]) : nil
        ),
        systemSideEffects: NoOpRootSystemSideEffects(),
        welcomeFlow: WelcomeFlowModel(
          store: InMemoryWelcomeFlowStore(),
          funnel: NoOpWelcomeFunnelRecorder(),
          canvas: DeveloperWidgetCanvasService(),
          pendingUploads: welcomePendingUploads,
          widgetCanvas: widgetCanvasService,
          widgetPendingUploads: pendingUploads,
          startDateQueue: firstDayStartedOnQueue
        )
      )

      locationViewModel = LocationMapViewModel(
        visibilityStore: visibilityStore,
        ownLocationStore: ownLocationStore,
        pendingOperationStore: pendingOperationStore,
        operationProvider: operationProvider,
        locationCapture: DeveloperLocalFlowLocationCapture()
      )

      let paywallViewModel = PaywallViewModel(
        userID: DeveloperScenarioFixture.currentUserID.uuidString,
        storeKitService: storeKitService,
        pairingService: pairingService,
        operationProvider: operationProvider
      )
      let pairingViewModel = PairingInviteViewModel(
        userID: DeveloperScenarioFixture.currentUserID.uuidString,
        pairingService: pairingService,
        operationProvider: operationProvider,
        inviteStore: inviteStore,
        now: { DeveloperScenarioFixture.now }
      )
      let dailyViewModel = DailyChallengeViewModel(
        service: DeveloperDailyChallengeService(
          mode: homeLaunch == nil ? .unanswered : .homeLaunch,
          pendingOperationStore: pendingOperationStore,
          initialLoadDelay: homeLaunch?.question ?? .zero
        ),
        operationProvider: operationProvider,
        draftStore: DeveloperLocalFlowDailyDraftStore(),
        mediaDraftStore: DeveloperLocalFlowMediaDraftStore(),
        pendingOperationStore: pendingOperationStore,
        snapshotCache: DeveloperLocalFlowSnapshotCache(),
        chatService: gameFlow?.chat,
        now: { DeveloperScenarioFixture.now }
      )
      let milestoneViewModel = RelationshipMilestoneViewModel(
        dataService: DeveloperDelayedStartedOnService(
          base: RelationshipStartedOnDataService(
            accessSnapshotStore: accessSnapshotStore,
            pendingOperationStore: pendingOperationStore
          ),
          delay: homeLaunch?.calendar ?? .zero
        ),
        operationProvider: operationProvider
      )
      let memoriesViewModel = MemoriesViewModel(
        memoryService: DeveloperScenarioMemoryDataService(
          records: DeveloperScenarioFixture.memoryRecords()),
        operationProvider: operationProvider,
        mediaUploader: nil,
        mediaImageCache: nil
      )
      let settingsViewModel = SettingsViewModel(
        preferences: DeveloperNotificationPreferences(),
        authorization: DeveloperScenarioPushAuthorization(denied: false),
        pairingService: pairingService,
        operationProvider: operationProvider,
        userID: DeveloperScenarioFixture.currentUserID.uuidString,
        storeKitService: storeKitService,
        loadAccessSnapshot: { DeveloperScenarioFixture.subscriptionSnapshot }
      )
      let widgetDrawingViewModel = WidgetDrawingViewModel(
        authorName: "Alex",
        service: widgetCanvasService,
        uploader: NoOpWidgetCanvasUpload()
      )
      let widgetHistoryViewModel = WidgetDrawingHistoryViewModel(
        gateway: NoOpWidgetCanvasGateway(),
        identity: WidgetSyncIdentity(
          currentUserID: DeveloperScenarioFixture.currentUserID,
          currentDisplayName: "Alex",
          partnerDisplayName: "Robin"
        )
      )

      featureDependencies = RootFeatureDependencies(
        paywallViewModel: paywallViewModel,
        paywallPresentationOverride: Self.paywallOverride(store: store),
        pairingInviteViewModel: pairingViewModel,
        inviterFirstDayModel: DeveloperInviterFixture.firstDayModel(
          answered: false,
          canvas: widgetCanvasService,
          pendingUploads: pendingUploads
        ),
        pairingJoinViewModel: PairingJoinViewModel(
          pairingService: pairingService,
          operationProvider: operationProvider
        ),
        dailyChallengeViewModel: dailyViewModel,
        milestoneViewModel: milestoneViewModel,
        memoriesViewModel: memoriesViewModel,
        gamesViewModel: gameFlow?.games,
        settingsViewModel: settingsViewModel,
        settingsPrivacyService: nil,
        settingsPrivacyOperationProvider: operationProvider,
        widgetDrawingViewModel: widgetDrawingViewModel,
        widgetHistoryViewModel: widgetHistoryViewModel,
        widgetHistoryThumbnailLoader: NoOpWidgetRevisionThumbnailLoader()
      )
    }

    func prepareHomeLaunch() async {
      guard let homeLaunch else { return }
      do {
        try await Task.sleep(for: homeLaunch.location)
        try await homeLaunch.seedMap(visibility: visibilityStore, ownLocation: ownLocationStore)
      } catch { }
    }

    private static func paywallOverride(
      store: DeveloperLocalFlowStore
    ) -> PaywallPresentationOverride {
      let trial = PaeoniaFreeTrial(value: 14, unit: .day)
      return PaywallPresentationOverride(
        presentation: { billingPeriod in
          PaywallPresentation(
            billingPeriod: billingPeriod,
            product: nil,
            freeTrial: trial,
            isPurchasing: false,
            isLoading: false,
            price: PaywallPrice(
              amount: billingPeriod == .monthly ? 49 : 399,
              format: .currency(code: "NOK")
            )
          )
        },
        purchaseIsEnabled: true,
        onPurchase: {
          await store.grantEntitlement()
          return true
        }
      )
    }
  }

#endif
