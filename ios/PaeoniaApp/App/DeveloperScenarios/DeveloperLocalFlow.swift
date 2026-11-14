#if DEBUG
  import Foundation
  import SwiftUI

  /// Interactive, entirely local app journey driven through the production root.
  /// External systems are replaced, while routing and feature views stay real.
  @MainActor
  struct DeveloperLocalFlowHost: View {
    @State private var deepLink: PaeoniaDeepLink?
    @State private var pendingInviteCode: String?
    @State private var environment: DeveloperLocalFlowEnvironment

    /// `gameConversation` is a game scenario. The Games tab then shows its state, and game
    /// chats work. `launchLink` opens when the flow starts, unless the app was launched with one.
    init(seed: DeveloperLocalFlowSeed, homeLaunch: DeveloperHomeLaunchTiming? = nil,
         gameConversation: DeveloperScenario? = nil, launchLink: String? = nil,
         avatarStories: StoryRingState? = nil, mapTiles: DeveloperHomeMapTiles = .live,
         mail: DeveloperMailSeed = .none) {
      // A link the app was launched with, such as a push tapped while the app was not running.
      _deepLink = State(
        initialValue: (ProcessInfo.processInfo.environment["PAEONIA_LAUNCH_LINK"] ?? launchLink)
          .flatMap(URL.init(string:)).flatMap(PaeoniaDeepLink.init)
      )
      _environment = State(
        initialValue: DeveloperLocalFlowEnvironment(
          seed: seed, homeLaunch: homeLaunch, gameConversation: gameConversation, avatarStories: avatarStories,
          mapTiles: mapTiles, mail: mail))
    }

    var body: some View {
      RootView(
        deepLink: $deepLink,
        pendingJoinInviteCode: $pendingInviteCode,
        viewModel: environment.rootViewModel,
        locationViewModel: environment.locationViewModel,
        appleSignInProvider: environment.appleSignInProvider,
        widgetCanvasSync: NoOpWidgetCanvasSync(),
        pushAuthorization: DeveloperScenarioPushAuthorization(denied: false),
        pushPermissionPrimerStore: DeveloperLocalFlowPrimerStore(),
        locationSharingPrimerStore: DeveloperLocalFlowLocationPrimerStore(),
        widgetPushRegistration: NoOpWidgetPushRegistration(),
        partnerAvatarSharing: DeveloperLocalFlowPartnerAvatarSharing(),
        featureDependencies: environment.featureDependencies,
        allowsSystemIntegrations: false
      )
      .environment(\.profilePhotoImageProvider, DeveloperAvatarPhotoProvider())
      .environment(\.mediaAlternativeEditingService, environment.mediaAlternativeEditingService)
      .overlay(alignment: .topTrailing) {
        if let gameFlow = environment.gameConversationFlow,
           UserDefaults.standard.bool(forKey: "paeonia-game-chat-test-events") {
          VStack(spacing: PaeoniaSpacing.space8) {
            // A sheet covers these buttons, so this one delivers after the chat sheet opens.
            receiveButton("Receive game message later", systemImage: "clock.badge", id: "receiveLater") {
              try? await Task.sleep(for: .seconds(4))
              await gameFlow.receivePartnerMessage()
            }
            receiveButton("Receive game message", systemImage: "envelope.badge.fill", id: "receive") {
              await gameFlow.receivePartnerMessage()
            }
            receiveButton("Partner opens the game chat and types", systemImage: "ellipsis.bubble",
                          id: "partnerInChat") {
              await gameFlow.playPartnerInChat()
            }
          }
          .padding(.trailing, PaeoniaSpacing.space8)
          .padding(.top, 80)
        }
      }
      .task(id: environment.rootViewModel.state) {
        guard environment.rootViewModel.state == .paired else { return }
        await environment.prepareHomeLaunch()
      }
    }

    private func receiveButton(
      _ label: String, systemImage: String, id: String, action: @escaping @MainActor () async -> Void
    ) -> some View {
      Button {
        Task { await action() }
      } label: {
        Image(systemName: systemImage)
          .frame(width: 44, height: 44)
      }
      .foregroundStyle(.paeoniaTextPrimary)
      .background(.paeoniaSurfacePrimary, in: Circle())
      .accessibilityLabel(label)
      .accessibilityIdentifier("developer.gameChat.\(id)")
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
    let featureDependencies: RootFeatureDependencies
    let gameConversationFlow: DeveloperGameConversationFlow?
    let mediaAlternativeEditingService: MediaAlternativeEditingService
    private let homeLaunch: DeveloperHomeLaunchTiming?
    private let visibilityStore = InMemoryLocationVisibilityRepository()
    private let ownLocationStore = InMemoryOwnLocationSnapshotRepository()

    // This is the single Debug composition boundary for the full local app graph.
    // swiftlint:disable:next function_body_length
    init(seed: DeveloperLocalFlowSeed, homeLaunch: DeveloperHomeLaunchTiming?, gameConversation: DeveloperScenario?,
         avatarStories: StoryRingState?, mapTiles: DeveloperHomeMapTiles, mail: DeveloperMailSeed) {
      self.homeLaunch = homeLaunch
      let store = DeveloperLocalFlowStore(seed: seed, avatarScenario: avatarStories != nil)
      let authService = DeveloperLocalFlowAuthService(store: store)
      let accessService = DeveloperLocalFlowAccessService(store: store)
      let pairingService = DeveloperLocalFlowPairingService(store: store)
      let operationProvider = DeveloperScenarioOperationProvider()
      let inviteStore = DeveloperScenarioInviteStore()
      let pendingOperationStore = InMemoryPendingSyncOperationRepository()
      let avatar = avatarStories.map { DeveloperAvatarFixture.storyDependencies($0) }
      mediaAlternativeEditingService = MediaAlternativeEditingService(
        pending: pendingOperationStore,
        cache: MediaAlternativeCacheUpdater(
          chat: InMemoryThreadChatCache(), stories: avatar?.cache ?? DeveloperAvatarStoriesCache(StoriesSnapshot()),
          daily: DeveloperLocalFlowSnapshotCache()
        )
      )
      let gameFlow = gameConversation.map { DeveloperGameConversationFlow(pending: pendingOperationStore, games: $0) }
      gameConversationFlow = gameFlow
      let accessSnapshotStore = InMemoryAccessSyncSnapshotRepository()
      let storeKitService = DeveloperScenarioStoreKitService()
      let widgetCanvasService = DeveloperWidgetCanvasService()
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
      let memoryRecords = ProcessInfo.processInfo.arguments.contains("-paeonia-scenario-first-memory")
        ? [] : DeveloperScenarioFixture.memoryRecords()
      let memoriesViewModel = MemoriesViewModel(
        memoryService: DeveloperScenarioMemoryDataService(records: memoryRecords),
        operationProvider: operationProvider,
        mediaUploader: DeveloperLocalFlowMemoryUploader(),
        mediaImageCache: nil
      )
      let visits = ProcessInfo.processInfo.arguments.contains("-paeonia-scenario-visit-ended")
        ? DeveloperVisitsFixture.planned(from: -5, through: -2, id: DeveloperVisitsFixture.endedVisitID)
        : CoupleVisits()
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
        visitsViewModel: DeveloperVisitsFixture.model(visits),
        settingsViewModel: settingsViewModel,
        avatarStylingModel: AvatarStylingModel(gateway: DeveloperAvatarDecorationGateway(store: store)),
        storiesViewModel: avatar?.viewModel,
        mailViewModel: DeveloperMailFixture.viewModel(mail),
        recapViewModel: seed == .paired ? DeveloperRecapFixture.model(recaps: [DeveloperRecapFixture.localFlow]) : nil,
        homeMapTiles: mapTiles.makeStatus(),
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

  nonisolated struct DeveloperLocalFlowMemoryUploader: MemoryMediaUploading {
    func uploadMedia(
      _: MemoryUploadMedia,
      memoryMediaID: UUID,
      coupleID _: UUID,
      reserveOperation _: SyncClientOperation,
      finalizeOperation _: SyncClientOperation
    ) -> MemoryMediaUploadResult {
      MemoryMediaUploadResult(memoryMediaID: memoryMediaID, mediaAssetID: UUID())
    }
  }

#endif
