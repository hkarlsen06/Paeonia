import Foundation
import Testing
@testable import PaeoniaApp

// swiftlint:disable async_without_await

// swiftlint:disable:next type_body_length
struct PaeoniaAppTests {

    @MainActor
    @Test func appStatesRemainOrdered() {
        #expect(AppState.allCases == [
            .launching,
            .unauthenticated,
            .onboarding,
            .limitedAuthenticated,
            .unpaired,
            .invitePending,
            .paired,
            .pairedPaywalled,
            .entitlementLost,
            .entitlementRestored,
            .relationshipEndedNotice,
            .deletingAccount,
        ])
    }

    @Test func mainTabSwipeOrderUsesVisibleTabOrder() {
        #expect(MainTab.home.tab(offsetBy: 1) == .questions)
        #expect(MainTab.questions.tab(offsetBy: 1) == .memories)
        #expect(MainTab.memories.tab(offsetBy: 1) == .you)

        #expect(MainTab.you.tab(offsetBy: -1) == .memories)
        #expect(MainTab.memories.tab(offsetBy: -1) == .questions)
        #expect(MainTab.questions.tab(offsetBy: -1) == .home)

        #expect(MainTab.home.tab(offsetBy: -1) == nil)
        #expect(MainTab.you.tab(offsetBy: 1) == nil)
    }

    @MainActor
    @Test func startRoutesMissingSessionToSignedOut() async throws {
        let syncService = TestPaeoniaSyncService()
        let authService = AuthServiceSpy()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: authService
        )

        await viewModel.start()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(viewModel.currentSession == nil)
        #expect(await syncService.startCallCount == 0)
    }

    @MainActor
    @Test func startRoutesIncompleteProfileToOnboarding() async {
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .needsOnboarding))
        )

        await viewModel.start()

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)
        #expect(viewModel.currentSession?.timeZoneID == nil)
    }

    @MainActor
    @Test func completedProfileUsesAccessRouteForVisibleState() async {
        let accessRouteService = StaticAccessRouteService(route: .unpaired)
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService
        )

        await viewModel.start()

        #expect(viewModel.authRoute.appState == .limitedAuthenticated)
        #expect(viewModel.state == .unpaired)
        #expect(await accessRouteService.resolveCallCount == 1)
    }

    @MainActor
    @Test func acknowledgingRelationshipEndedMarksNoticeSeenAndResolvesToUnpaired() async {
        let coupleID = UUID()
        let accessRouteService = RelationshipEndedAccessRouteService(coupleID: coupleID)
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService
        )

        await viewModel.start()
        #expect(viewModel.state == .relationshipEndedNotice)

        await viewModel.acknowledgeRelationshipEnded()

        #expect(viewModel.state == .unpaired)
        #expect(viewModel.notice == nil)
        #expect(viewModel.isWorking == false)
        #expect(await accessRouteService.markedCoupleIDs == [coupleID])
    }

    @MainActor
    @Test func acknowledgingRelationshipEndedKeepsNoticeWhenMarkSeenFails() async {
        let accessRouteService = RelationshipEndedAccessRouteService(failsMark: true)
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService
        )

        await viewModel.start()
        #expect(viewModel.state == .relationshipEndedNotice)

        await viewModel.acknowledgeRelationshipEnded()

        #expect(viewModel.state == .relationshipEndedNotice)
        #expect(viewModel.notice == .relationshipEndedAcknowledgeFailed)
        #expect(viewModel.isWorking == false)
    }

    @MainActor
    @Test func localLocationChangeRunsImmediateLocalChangeSync() async {
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .paired)
        )
        await viewModel.start()

    await viewModel.syncAfterLocalLocationChange()

    #expect(await syncService.runOnceReasons == [.localChange])
    }

    @MainActor
    @Test func homePullRefreshRunsManualSync() async {
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .paired),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository()
        )
        await viewModel.start()

        await viewModel.refreshFromHomePull()

        #expect(await syncService.runOnceReasons == [.manualRefresh])
    }

    @MainActor
    @Test func cachedAccessSnapshotCanRecoverAccessRouteAfterSync() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let syncService = TestPaeoniaSyncService()
        let accessSnapshotStore = InMemoryAccessSyncSnapshotRepository()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated),
            accessSnapshotStore: accessSnapshotStore
        )
        await viewModel.start()
        #expect(viewModel.state == .limitedAuthenticated)

        try await accessSnapshotStore.save(
            .testPaired(ownerUserID: ownerUserID, coupleID: coupleID, partnerDisplayName: "Riley")
        )

        await viewModel.refreshAfterForegroundActivation()

        #expect(viewModel.state == .paired)
        #expect(viewModel.currentPartnerDisplayName == "Riley")
        #expect(await syncService.runOnceReasons == [.foreground])
        let configuredSessions = await syncService.configuredSessions
        let latestSession = configuredSessions.last ?? nil
        #expect(latestSession?.activeCoupleID == coupleID)
    }

    @MainActor
    @Test func cachedAccessSnapshotIsFallbackWhenLiveAccessFails() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let accessSnapshotStore = InMemoryAccessSyncSnapshotRepository()
        try await accessSnapshotStore.save(
            .testPaired(ownerUserID: ownerUserID, partnerDisplayName: "Riley")
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: FailingAccessRouteService(),
            accessSnapshotStore: accessSnapshotStore
        )

        await viewModel.start()

        #expect(viewModel.state == .paired)
        #expect(viewModel.currentPartnerDisplayName == "Riley")
    }

    @MainActor
    @Test func completedProfileExposesPartnerDisplayNameFromAccessSnapshot() async {
        let accessRouteService = StaticAccessRouteService(
            resolution: .test(route: .paired, partnerDisplayName: "Riley")
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService
        )

        await viewModel.start()

        #expect(viewModel.state == .paired)
        #expect(viewModel.currentPartnerDisplayName == "Riley")
    }

    @MainActor
    @Test func widgetDrawingRoutePresentsOnlyWhenPaired() async {
        let pairedViewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .paired)
        )
        await pairedViewModel.start()

        // The drawing lives on the Home tab, so opening it from another tab must
        // also bring the user there or the screen would open hidden behind it.
        pairedViewModel.selectMainTab(.you)
        pairedViewModel.openWidgetDrawing()

        #expect(pairedViewModel.presentedDestination == .widgetDrawing)
        #expect(pairedViewModel.selectedMainTab == .home)

        pairedViewModel.dismissPresentedDestination()

        #expect(pairedViewModel.presentedDestination == nil)

        let unpairedViewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .unpaired)
        )
        await unpairedViewModel.start()

        unpairedViewModel.openWidgetDrawing()

        #expect(unpairedViewModel.presentedDestination == nil)
    }

    @MainActor
    @Test func widgetDrawingRouteWaitsForPairedColdLaunch() async {
        let pairedViewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .paired)
        )

        pairedViewModel.selectMainTab(.you)
        pairedViewModel.openWidgetDrawing()

        #expect(pairedViewModel.presentedDestination == nil)

        await pairedViewModel.start()

        #expect(pairedViewModel.presentedDestination == .widgetDrawing)
        #expect(pairedViewModel.selectedMainTab == .home)

        let unpairedViewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .unpaired)
        )

        unpairedViewModel.openWidgetDrawing()
        await unpairedViewModel.start()

        #expect(unpairedViewModel.presentedDestination == nil)
    }

    @MainActor
    @Test func completedProfilePassesPendingInviteToAccessRoute() async {
        let accessRouteService = StaticAccessRouteService(route: .invitePending)
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test())
        )

        await viewModel.start()

        #expect(viewModel.state == .invitePending)
        #expect(await accessRouteService.receivedHasPendingInvite == [true])
    }

    @MainActor
    @Test func pairingRefreshKeepsCurrentPairingStateWhileAccessRouteResolves() async {
        let accessRouteService = BlockingAccessRouteService(
            routes: [.invitePending, .invitePending],
            blockedCallIndex: 2
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test())
        )

        await viewModel.start()
        #expect(viewModel.state == .invitePending)

        let refreshTask = Task { @MainActor in
            await viewModel.refreshAfterPairingChange()
        }

        await accessRouteService.waitForBlockedResolveToStart()
        #expect(viewModel.state == .invitePending)

        await accessRouteService.releaseBlockedResolve()
        await refreshTask.value

        #expect(viewModel.state == .invitePending)
        #expect(await accessRouteService.resolveCallCount == 2)
    }

    @MainActor
    @Test func staleAccessRefreshCannotOverwriteNewerRoute() async {
        let accessRouteService = BlockingAccessRouteService(
            routes: [.invitePending, .invitePending, .paired],
            blockedCallIndex: 2
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test())
        )

        await viewModel.start()
        #expect(viewModel.state == .invitePending)

        let staleRefreshTask = Task { @MainActor in
            await viewModel.refreshAfterPairingChange()
        }
        await accessRouteService.waitForBlockedResolveToStart()

        let latestRefreshTask = Task { @MainActor in
            await viewModel.refreshAfterPairingChange()
        }
        await latestRefreshTask.value
        #expect(viewModel.state == .paired)

        await accessRouteService.releaseBlockedResolve()
        await staleRefreshTask.value

        #expect(viewModel.state == .paired)
        #expect(await accessRouteService.resolveCallCount == 3)
    }

    @MainActor
    @Test func freshLinkIntoPairedRequestsCelebration() async throws {
        let pairID = try #require(UUID(uuidString: "2C7B12FD-4DD2-4900-98B6-5E37B9DFE4DD"))
        let pairingCelebrationStore = TestPairingCelebrationStore()
        let accessRouteService = BlockingAccessRouteService(
            routes: [.invitePending, .paired],
            blockedCallIndex: 0,
            pairID: pairID
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test()),
            pairingCelebrationStore: pairingCelebrationStore
        )

        await viewModel.start()
        #expect(viewModel.state == .invitePending)
        #expect(viewModel.pendingPairingCelebration == false)
        #expect(viewModel.isPairingCelebrationPresented == false)

        await viewModel.refreshAfterPairingChange()
        #expect(viewModel.state == .paired)
        #expect(viewModel.pendingPairingCelebration == true)
        #expect(viewModel.isPairingCelebrationPresented == true)

        viewModel.consumePairingCelebration()
        #expect(viewModel.pendingPairingCelebration == false)
        #expect(viewModel.isPairingCelebrationPresented == true)

        viewModel.dismissPairingCelebration()
        #expect(viewModel.isPairingCelebrationPresented == false)
        #expect(pairingCelebrationStore.hasSeenCelebration(forPairID: pairID) == true)
    }

    @MainActor
    @Test func acceptedInviteShowsCelebrationWhileAccessRouteResolves() async throws {
        let pairID = try #require(UUID(uuidString: "8C01125D-7164-4E19-9742-A8F419B78E77"))
        let pairingCelebrationStore = TestPairingCelebrationStore()
        let accessRouteService = BlockingAccessRouteService(
            routes: [.limitedAuthenticated, .paired],
            blockedCallIndex: 2,
            pairID: pairID
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            pairingCelebrationStore: pairingCelebrationStore
        )

        await viewModel.start()
        #expect(viewModel.state == .limitedAuthenticated)

        let refreshTask = Task { @MainActor in
            await viewModel.refreshAfterInviteAccepted()
        }

        await accessRouteService.waitForBlockedResolveToStart()
        #expect(viewModel.state == .paired)
        #expect(viewModel.pendingPairingCelebration == true)
        #expect(viewModel.isPairingCelebrationPresented == true)

        await accessRouteService.releaseBlockedResolve()
        await refreshTask.value

        #expect(viewModel.state == .paired)
        #expect(viewModel.pendingPairingCelebration == true)
        #expect(viewModel.isPairingCelebrationPresented == true)

        viewModel.dismissPairingCelebration()
        #expect(viewModel.isPairingCelebrationPresented == false)
        #expect(pairingCelebrationStore.hasSeenCelebration(forPairID: pairID) == true)
    }

    @MainActor
    @Test func acceptedInviteDismissedBeforeSnapshotMarksSeenWhenPairIDArrives() async throws {
        let pairID = try #require(UUID(uuidString: "B14D1155-6F4E-4631-8429-12C023D028CB"))
        let pairingCelebrationStore = TestPairingCelebrationStore()
        let accessRouteService = BlockingAccessRouteService(
            routes: [.limitedAuthenticated, .paired],
            blockedCallIndex: 2,
            pairID: pairID
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            pairingCelebrationStore: pairingCelebrationStore
        )

        await viewModel.start()

        let refreshTask = Task { @MainActor in
            await viewModel.refreshAfterInviteAccepted()
        }

        await accessRouteService.waitForBlockedResolveToStart()
        viewModel.dismissPairingCelebration()
        #expect(viewModel.isPairingCelebrationPresented == false)
        #expect(pairingCelebrationStore.hasSeenCelebration(forPairID: pairID) == false)

        await accessRouteService.releaseBlockedResolve()
        await refreshTask.value

        #expect(viewModel.state == .paired)
        #expect(viewModel.isPairingCelebrationPresented == false)
        #expect(pairingCelebrationStore.hasSeenCelebration(forPairID: pairID) == true)
    }

    @MainActor
    @Test func seenPairingCelebrationDoesNotPresentFreshLinkAgain() async throws {
        let pairID = try #require(UUID(uuidString: "E88951E9-41DC-4961-A92D-DC2D5856F558"))
        let pairingCelebrationStore = TestPairingCelebrationStore(seenPairIDs: [pairID])
        let accessRouteService = BlockingAccessRouteService(
            routes: [.invitePending, .paired],
            blockedCallIndex: 0,
            pairID: pairID
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test()),
            pairingCelebrationStore: pairingCelebrationStore
        )

        await viewModel.start()
        await viewModel.refreshAfterPairingChange()

        #expect(viewModel.state == .paired)
        #expect(viewModel.pendingPairingCelebration == false)
        #expect(viewModel.isPairingCelebrationPresented == false)
    }

    @MainActor
    @Test func launchingDirectlyIntoUnseenPairedShowsSettledCelebration() async throws {
        let pairID = try #require(UUID(uuidString: "E6067801-9F27-4982-B8FD-0DFED2F61672"))
        let pairingCelebrationStore = TestPairingCelebrationStore()
        let accessRouteService = StaticAccessRouteService(
            resolution: .test(route: .paired, partnerDisplayName: "Riley", pairID: pairID)
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            pairingCelebrationStore: pairingCelebrationStore
        )

        await viewModel.start()

        #expect(viewModel.state == .paired)
        #expect(viewModel.pendingPairingCelebration == false)
        #expect(viewModel.isPairingCelebrationPresented == true)

        viewModel.dismissPairingCelebration()
        #expect(viewModel.isPairingCelebrationPresented == false)
        #expect(pairingCelebrationStore.hasSeenCelebration(forPairID: pairID) == true)
    }

    @MainActor
    @Test func launchingDirectlyIntoSeenPairedDoesNotShowCelebration() async throws {
        let pairID = try #require(UUID(uuidString: "97C22CEF-03CE-4A20-B817-698EE5A43511"))
        let pairingCelebrationStore = TestPairingCelebrationStore(seenPairIDs: [pairID])
        let accessRouteService = StaticAccessRouteService(
            resolution: .test(route: .paired, partnerDisplayName: "Riley", pairID: pairID)
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            pairingCelebrationStore: pairingCelebrationStore
        )

        await viewModel.start()

        #expect(viewModel.state == .paired)
        #expect(viewModel.pendingPairingCelebration == false)
        #expect(viewModel.isPairingCelebrationPresented == false)
    }

    @MainActor
    @Test func developmentSignInCanCompleteOnboarding() async {
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(),
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.signInForDevelopment()

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.provider == .development)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)

        await viewModel.completeOnboarding(
            displayName: "Test account",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: nil
        )

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(viewModel.currentSession?.profileStatus == .complete)
        #expect(viewModel.currentSession?.timeZoneID == "Europe/Oslo")
        #expect(await syncService.startCallCount == 1)
    }

    @MainActor
    @Test func googleSignInRoutesToOnboarding() async {
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy()
        )

        await viewModel.signInWithGoogle(using: GoogleSignInProviderSpy())

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.provider == .google)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)
    }

    @MainActor
    @Test func cancelledGoogleSignInDoesNotShowFailureNotice() async {
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy()
        )

        await viewModel.start()
        await viewModel.signInWithGoogle(
            using: GoogleSignInProviderSpy(error: GoogleSignInServiceError.userCancelled)
        )

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func signOutClearsSession() async throws {
        let authService = AuthServiceSpy(session: .test(profileStatus: .complete))
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.start()
        await viewModel.signOut()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(try await authService.restoreSession() == nil)
    }

    @MainActor
    @Test func deleteAccountShowsDeletingStateBeforeClearingSession() async throws {
        let authService = BlockingDeleteAuthService()
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.start()
        #expect(viewModel.state == .limitedAuthenticated)

        let deleteTask = Task { @MainActor in
            await viewModel.deleteAccount()
        }

        await authService.waitForDeleteToStart()
        #expect(viewModel.state == .deletingAccount)

        await authService.releaseDelete()
        await deleteTask.value

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(try await authService.restoreSession() == nil)
    }

    @MainActor
    @Test func deleteFailureRestoresPreviousRoute() async {
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            failingOperations: [.requestAccountDeletion]
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.start()
        await viewModel.deleteAccount()

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(viewModel.currentSession?.profileStatus == .complete)
        #expect(viewModel.notice == .deleteAccountFailed)
    }

    @MainActor
    @Test func deleteFailureRestoresResolvedAccessRoute() async {
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            failingOperations: [.requestAccountDeletion]
        )
        let accessRouteService = StaticAccessRouteService(route: .unpaired)
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: authService,
            accessRouteService: accessRouteService
        )

        await viewModel.start()
        #expect(viewModel.state == .unpaired)

        await viewModel.deleteAccount()

        #expect(viewModel.state == .unpaired)
        #expect(viewModel.currentSession?.profileStatus == .complete)
        #expect(viewModel.notice == .deleteAccountFailed)
    }

    @MainActor
    @Test func failedSessionLoadFallsBackToSignedOut() async {
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(failingOperations: [.restoreSession])
        )

        await viewModel.start()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(viewModel.notice == .sessionLoadFailed)
    }

    @MainActor
    @Test func dismissNoticeClearsNotice() async {
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(failingOperations: [.restoreSession])
        )

        await viewModel.start()
        #expect(viewModel.notice == .sessionLoadFailed)

        viewModel.dismissNotice()
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func startRestoresAuthBeforeStartingSync() async {
        let recorder = StartupOrderRecorder()
        let authService = OrderedAuthService(recorder: recorder)
        let syncService = OrderedPaeoniaSyncService(recorder: recorder)
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.start()

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(recorder.events == [.restoreSession, .startSync])
    }
}

private actor TestPaeoniaSyncService: PaeoniaSyncing {
    private(set) var startCallCount = 0
    private(set) var requestedReasons: [SyncRequestReason] = []
    private(set) var runOnceReasons: [SyncRequestReason] = []
    private(set) var configuredSessions: [SyncSession?] = []
    private(set) var resetCallCount = 0

    func configure(session: SyncSession?) {
        configuredSessions.append(session)
    }

    func start() {
        startCallCount += 1
    }

    func requestSync(reason: SyncRequestReason) {
        requestedReasons.append(reason)
    }

    func runOnce(reason: SyncRequestReason) async -> SyncRunResult {
        runOnceReasons.append(reason)
        return SyncRunResult(
            status: .succeeded,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    func stop() {}

    func resetForUserChange() {
        resetCallCount += 1
    }
}

private actor StaticAccessRouteService: AccessRouteServicing {
    private let resolution: AccessRouteResolution
    private(set) var resolveCallCount = 0
    private(set) var receivedHasPendingInvite: [Bool] = []

    init(route: AccessRoute) {
        self.resolution = .test(route: route)
    }

    init(resolution: AccessRouteResolution) {
        self.resolution = resolution
    }

    func resolveAccess(hasPendingInvite: Bool) async throws -> AccessRouteResolution {
        resolveCallCount += 1
        receivedHasPendingInvite.append(hasPendingInvite)
        return resolution
    }

    func markRelationshipEndedNoticeSeen(coupleID _: UUID) async throws {}
}

private enum AccessRouteServiceTestError: Error {
    case unavailable
}

private actor FailingAccessRouteService: AccessRouteServicing {
    func resolveAccess(hasPendingInvite _: Bool) async throws -> AccessRouteResolution {
        throw AccessRouteServiceTestError.unavailable
    }

    func markRelationshipEndedNoticeSeen(coupleID _: UUID) async throws {
        throw AccessRouteServiceTestError.unavailable
    }
}

private actor BlockingAccessRouteService: AccessRouteServicing {
    private let routes: [AccessRoute]
    private let blockedCallIndex: Int
    private let pairID: UUID?
    private var blockedResolveStarted = false
    private var blockedResolveStartedContinuation: CheckedContinuation<Void, Never>?
    private var blockedResolveReleaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var resolveCallCount = 0

    init(routes: [AccessRoute], blockedCallIndex: Int, pairID: UUID? = nil) {
        precondition(!routes.isEmpty)
        self.routes = routes
        self.blockedCallIndex = blockedCallIndex
        self.pairID = pairID
    }

    func waitForBlockedResolveToStart() async {
        if blockedResolveStarted {
            return
        }

        await withCheckedContinuation { continuation in
            blockedResolveStartedContinuation = continuation
        }
    }

    func releaseBlockedResolve() {
        blockedResolveReleaseContinuation?.resume()
        blockedResolveReleaseContinuation = nil
    }

    func resolveAccess(hasPendingInvite: Bool) async throws -> AccessRouteResolution {
        resolveCallCount += 1
        let callIndex = resolveCallCount

        if callIndex == blockedCallIndex {
            blockedResolveStarted = true
            blockedResolveStartedContinuation?.resume()
            blockedResolveStartedContinuation = nil

            await withCheckedContinuation { continuation in
                blockedResolveReleaseContinuation = continuation
            }
        }

        let routeIndex = min(callIndex - 1, routes.count - 1)
        return .test(route: routes[routeIndex], pairID: pairID)
    }

    func markRelationshipEndedNoticeSeen(coupleID _: UUID) async throws {}
}

/// Drives the relationship-ended acknowledge flow: resolves to the ended notice
/// until the notice is marked seen, then resolves to `.unpaired`, recording each
/// couple id passed to the mark call (and optionally failing the mark).
private actor RelationshipEndedAccessRouteService: AccessRouteServicing {
    let coupleID: UUID
    private let failsMark: Bool
    private var noticeSeen = false
    private(set) var markedCoupleIDs: [UUID] = []
    private(set) var resolveCallCount = 0

    init(coupleID: UUID = UUID(), failsMark: Bool = false) {
        self.coupleID = coupleID
        self.failsMark = failsMark
    }

    func resolveAccess(hasPendingInvite _: Bool) async throws -> AccessRouteResolution {
        resolveCallCount += 1
        return resolution(route: noticeSeen ? .unpaired : .relationshipEndedNotice)
    }

    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws {
        markedCoupleIDs.append(coupleID)

        if failsMark {
            throw AccessRouteServiceTestError.unavailable
        }

        noticeSeen = true
    }

    private func resolution(route: AccessRoute) -> AccessRouteResolution {
        AccessRouteResolution(
            route: route,
            snapshot: AccessRouteSnapshot(
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: SupabaseRelationshipState(
                    coupleID: coupleID,
                    pairID: UUID(),
                    relationshipStatus: .ended,
                    memberStatus: noticeSeen ? .endedNoticeSeen : .endedNoticePending,
                    partnerUserID: UUID(),
                    partnerDisplayName: "Partner",
                    partnerProfilePhotoAssetID: nil,
                    startedOn: "2026-06-24",
                    endedAt: Date(timeIntervalSince1970: 1_900_000_000),
                    deleteAfter: nil,
                    endedNoticeSeenAt: noticeSeen ? Date(timeIntervalSince1970: 1_950_000_000) : nil
                ),
                hasPendingInvite: false
            )
        )
    }
}

private extension AccessSyncSnapshot {
    static func testPaired(
        ownerUserID: UUID,
        coupleID: UUID = UUID(),
        partnerDisplayName: String = "Partner"
    ) -> AccessSyncSnapshot {
        AccessSyncSnapshot(
            ownerUserID: ownerUserID,
            userEntitlement: .testEntitled(userID: ownerUserID),
            coupleEntitlement: .testEntitled(coupleID: coupleID, coveringUserID: ownerUserID),
            relationshipState: .test(
                coupleID: coupleID,
                partnerDisplayName: partnerDisplayName
            ),
            refreshedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }
}

private extension AccessRouteResolution {
    static func test(
        route: AccessRoute,
        partnerDisplayName: String? = nil,
        partnerProfilePhotoAssetID: UUID? = nil,
        pairID: UUID? = nil
    ) -> AccessRouteResolution {
        AccessRouteResolution(
            route: route,
            snapshot: AccessRouteSnapshot(
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: relationshipState(
                    route: route,
                    partnerDisplayName: partnerDisplayName,
                    partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                    pairID: pairID
                ),
                hasPendingInvite: route == .invitePending
            )
        )
    }

    private static func relationshipState(
        route: AccessRoute,
        partnerDisplayName: String?,
        partnerProfilePhotoAssetID: UUID?,
        pairID: UUID?
    ) -> SupabaseRelationshipState? {
        if let partnerDisplayName {
            return .test(
                partnerDisplayName: partnerDisplayName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                pairID: pairID
            )
        }

        switch route {
        case .paired, .pairedPaywalled, .relationshipEndedNotice:
            return .test(
                partnerDisplayName: "Partner",
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                pairID: pairID
            )
        case .limitedAuthenticated, .unpaired, .invitePending:
            return nil
        }
    }
}

private extension SupabaseUserEntitlement {
    static func testEntitled(userID: UUID) -> SupabaseUserEntitlement {
        SupabaseUserEntitlement(
            userID: userID,
            isEntitled: true,
            source: "storekit",
            status: "active",
            productID: UUID(),
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension SupabaseCoupleEntitlement {
    static func testEntitled(coupleID: UUID, coveringUserID: UUID) -> SupabaseCoupleEntitlement {
        SupabaseCoupleEntitlement(
            coupleID: coupleID,
            isEntitled: true,
            coveringUserID: coveringUserID,
            source: "storekit",
            status: "active",
            productID: UUID(),
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension SupabaseRelationshipState {
    static func test(
        coupleID: UUID = UUID(),
        partnerDisplayName: String,
        partnerProfilePhotoAssetID: UUID? = nil,
        pairID: UUID? = nil
    ) -> SupabaseRelationshipState {
        SupabaseRelationshipState(
            coupleID: coupleID,
            pairID: pairID ?? UUID(),
            relationshipStatus: .active,
            memberStatus: .active,
            partnerUserID: UUID(),
            partnerDisplayName: partnerDisplayName,
            partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
            startedOn: "2026-06-24",
            endedAt: nil,
            deleteAfter: nil,
            endedNoticeSeenAt: nil
        )
    }
}

@MainActor
private final class TestPairingCelebrationStore: PairingCelebrationStoring {
    private var seenPairIDs: Set<UUID>

    init(seenPairIDs: Set<UUID> = []) {
        self.seenPairIDs = seenPairIDs
    }

    func hasSeenCelebration(forPairID pairID: UUID) -> Bool {
        seenPairIDs.contains(pairID)
    }

    func markCelebrationSeen(forPairID pairID: UUID) {
        seenPairIDs.insert(pairID)
    }
}

@MainActor
private final class TestPairingInviteStore: PairingInviteStoring {
    private var invitesByUserID: [String: PairingInvite]

    init(
        invite: PairingInvite? = nil,
        userID: String = AuthSession.test(profileStatus: .complete).id
    ) {
        if let invite {
            self.invitesByUserID = [userID: invite]
        } else {
            self.invitesByUserID = [:]
        }
    }

    func loadInvite(for userID: String) -> PairingInvite? {
        invitesByUserID[userID]
    }

    func saveInvite(_ invite: PairingInvite, for userID: String) {
        invitesByUserID[userID] = invite
    }

    func clearInvite(for userID: String) {
        invitesByUserID[userID] = nil
    }
}

private final class StartupOrderRecorder: @unchecked Sendable {
    enum Event: Equatable {
        case restoreSession
        case startSync
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.withLock {
            recordedEvents
        }
    }

    func record(_ event: Event) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

private actor OrderedPaeoniaSyncService: PaeoniaSyncing {
    private let recorder: StartupOrderRecorder

    init(recorder: StartupOrderRecorder) {
        self.recorder = recorder
    }

    func configure(session _: SyncSession?) {}

    func start() {
        recorder.record(.startSync)
    }

    func requestSync(reason _: SyncRequestReason) {}

    func runOnce(reason _: SyncRequestReason) async -> SyncRunResult {
        SyncRunResult(
            status: .succeeded,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    func stop() {}

    func resetForUserChange() {}
}

private actor OrderedAuthService: AuthServicing {
    private let recorder: StartupOrderRecorder

    init(recorder: StartupOrderRecorder) {
        self.recorder = recorder
    }

    func restoreSession() async throws -> AuthSession? {
        recorder.record(.restoreSession)
        return .test(profileStatus: .complete)
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        .test(profileStatus: .needsOnboarding)
    }

    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession {
        AuthSession(
            id: "ordered-google-user",
            provider: .google,
            displayName: nil,
            timeZoneID: nil,
            profilePhotoAssetID: nil,
            profileStatus: .needsOnboarding
        )
    }

    func signInForDevelopment() async throws -> AuthSession {
        .test(profileStatus: .needsOnboarding)
    }

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async throws -> AuthSession {
        .test(profileStatus: .complete)
    }

    func signOut() async throws {}

    func requestAccountDeletion() async throws {}
}

private extension PairingInvite {
    static func test() -> PairingInvite {
        PairingInvite(
            id: UUID(uuidString: "0841FAE5-E016-497A-B082-CDF8D4432F30") ?? UUID(),
            code: "01ABCD",
            joinURL: URL(string: "https://paeonia.no/join/01ABCD") ?? URL(fileURLWithPath: "/"),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }
}

// swiftlint:enable async_without_await
// swiftlint:disable:this file_length
