import AuthenticationServices
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

    @Test func mainTabsRemainInVisibleOrder() {
        #expect(MainTab.allCases == [.home, .questions, .games, .memories, .us])
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
        let accessSnapshotStore = InMemoryAccessSyncSnapshotRepository()
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            accessSnapshotStore: accessSnapshotStore
        )

        await viewModel.start()

        #expect(viewModel.authRoute.appState == .limitedAuthenticated)
        #expect(viewModel.state == .unpaired)
        #expect(await accessRouteService.resolveCallCount == 1)
        // A person who has never paired has no stale relationship data to
        // purge; preserving local invite work is intentional.
        #expect(await syncService.relationshipAccessPurgePermanence.isEmpty)
    }

    @MainActor
    @Test func coldLaunchPurgesStaleRelationshipWhenCurrentSnapshotIsUnpaired() async throws {
        let ownerUserID = try #require(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let accessSnapshotStore = InMemoryAccessSyncSnapshotRepository()
        try await accessSnapshotStore.save(
            .testPaired(ownerUserID: ownerUserID)
        )
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .unpaired),
            accessSnapshotStore: accessSnapshotStore
        )

        await viewModel.start()

        #expect(viewModel.state == .unpaired)
        #expect(await syncService.relationshipAccessPurgePermanence == [true])
        #expect(await syncService.relationshipAccessPurgeOwnerUserIDs == [ownerUserID])
    }

    @MainActor
    @Test func paywalledPairStartsOnlyUserScopedSync() async throws {
        let ownerUserID = try #require(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .pairedPaywalled)
        )

        await viewModel.start()

        #expect(viewModel.state == .pairedPaywalled)
        #expect(await syncService.startCallCount == 1)
        let configuredSessions = await syncService.configuredSessions
        let latestSession = configuredSessions.last.flatMap { $0 }
        #expect(latestSession?.activeCoupleID == nil)
        #expect(latestSession?.relationshipCoupleID == viewModel.currentActiveCoupleID)
        #expect(await syncService.relationshipAccessPurgePermanence == [false])
        #expect(
            await syncService.relationshipAccessPurgeOwnerUserIDs
                == [ownerUserID]
        )
    }

    @MainActor
    @Test func acknowledgingRelationshipEndedMarksNoticeSeenAndResolvesToUnpaired() async {
        let coupleID = UUID()
        let accessRouteService = RelationshipEndedAccessRouteService(coupleID: coupleID)
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService
        )

        await viewModel.start()
        #expect(viewModel.state == .relationshipEndedNotice)
        #expect(await syncService.relationshipAccessPurgePermanence == [true])

        await viewModel.acknowledgeRelationshipEnded()

        #expect(viewModel.state == .unpaired)
        #expect(viewModel.notice == nil)
        #expect(viewModel.isWorking == false)
        #expect(await accessRouteService.markedCoupleIDs == [coupleID])
        // The acknowledged stale relationship still requires the same
        // idempotent permanent purge before the unpaired route is committed.
        #expect(await syncService.relationshipAccessPurgePermanence == [true, true])
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
        pairedViewModel.selectMainTab(.us)
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

        pairedViewModel.selectMainTab(.us)
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

        await viewModel.signInWithGoogle()

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.provider == .google)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)
    }

    @MainActor
    @Test func cancelledGoogleSignInDoesNotShowFailureNotice() async {
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: AuthServiceSpy(
                failingOperations: [.signInWithGoogle],
                failureError: ASWebAuthenticationSessionError(.canceledLogin)
            )
        )

        await viewModel.start()
        await viewModel.signInWithGoogle()

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
    @Test func signOutSendsWaitingWritesWhileStillSignedInThenPurges() async throws {
        let authService = AuthServiceSpy(session: .test(profileStatus: .complete))
        let syncService = TestPaeoniaSyncService(isSignedIn: {
            (try? await authService.restoreSession()) != nil
        })
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.start()
        await viewModel.signOut()

        #expect(await syncService.signOutSteps == ["flush while signed in", "purge"])
    }

    @MainActor
    @Test func deleteAccountShowsDeletingStateBeforeClearingSession() async throws {
        let authService = BlockingDeleteAuthService()
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
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
        #expect(await syncService.resetCallCount == 1)
    }

    @MainActor
    @Test func pairedProfileUpdateCommitsSessionAndRequestsSync() async throws {
        let syncService = TestPaeoniaSyncService()
        let authService = AuthServiceSpy(session: .test(profileStatus: .complete))
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .paired)
        )

        await viewModel.start()
        let updated = await viewModel.updateCurrentProfile(
            displayName: "Jamie",
            profilePhotoUpdate: .replace(Data([1, 2, 3]))
        )

        #expect(updated)
        #expect(viewModel.state == .paired)
        #expect(viewModel.currentSession?.displayName == "Jamie")
        #expect(
            viewModel.currentSession?.profilePhotoAssetID
                == UUID(uuidString: "99999999-9999-9999-9999-999999999999")
        )
        // The save reports success first; the sync pass follows on its own.
        #expect(await waitUntil { await syncService.runOnceReasons == [.localChange] })
    }

    @MainActor
    @Test func failedPairedProfileUpdateKeepsStableSession() async {
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            failingOperations: [.updateProfile]
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .paired)
        )

        await viewModel.start()
        let updated = await viewModel.updateCurrentProfile(
            displayName: "Jamie",
            profilePhotoUpdate: .unchanged
        )

        #expect(!updated)
        #expect(viewModel.state == .paired)
        #expect(viewModel.currentSession?.displayName == "Test account")
    }

    @MainActor
    @Test func deleteFailureRestoresPreviousRoute() async {
        let syncService = TestPaeoniaSyncService()
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            failingOperations: [.requestAccountDeletion]
        )
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.start()
        await viewModel.deleteAccount()

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(viewModel.currentSession?.profileStatus == .complete)
        #expect(viewModel.notice == .deleteAccountFailed)
        #expect(await syncService.resetCallCount == 0)
    }

    @MainActor
    @Test func appleDeletionFallbackSignsOutAndShowsManualRevocationStep() async {
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            accountDeletionOutcome: .manualAppleRevocationRequired
        )
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: authService,
            accessRouteService: StaticAccessRouteService(route: .limitedAuthenticated)
        )

        await viewModel.start()
        await viewModel.deleteAccount(appleAuthorizationCode: nil)

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.requiresManualAppleRevocation)

        viewModel.dismissManualAppleRevocation()
        #expect(!viewModel.requiresManualAppleRevocation)
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
    @Test func startRetriesPrivacyThenRestoresAuthBeforeStartingSync() async {
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
        #expect(recorder.events == [.retryPrivacyPurges, .restoreSession, .startSync])
    }

    @MainActor
    @Test func coldLaunchCanDeferSyncUntilAnimationFinishes() async {
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .paired)
        )

        await viewModel.start(deferringSyncUntilLaunchCompletes: true)

        #expect(viewModel.state == .paired)
        #expect(await syncService.startCallCount == 0)
        #expect(await syncService.configuredSessions.isEmpty)

        await viewModel.finishDeferredLaunchStartup()

        #expect(await syncService.startCallCount == 1)
        #expect(await syncService.configuredSessions.count == 1)

        await viewModel.synchronizePairedPresentationData()

        #expect(await syncService.runOnceReasons == [.startup])
    }

    @MainActor
    @Test func pairedRouteWaitsForPendingPrivacyPurgeAndRecoversOnForeground() async {
        let syncService = TestPaeoniaSyncService(
            privacyRetryResults: [.recordsPendingRetry, .recordsPendingRetry, .completed]
        )
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: StaticAccessRouteService(route: .paired)
        )

        await viewModel.start()

        #expect(viewModel.state == .launching)
        #expect(await syncService.startCallCount == 0)

        await viewModel.refreshAfterForegroundActivation()

        #expect(viewModel.state == .paired)
        #expect(await syncService.startCallCount == 1)
    }
}

/// The live access feed writes the snapshot store, and Root re-routes on its own.
struct RootLiveAccessTests {
    @MainActor
    private final class Fixture {
        let userID: UUID
        let store: InMemoryAccessSyncSnapshotRepository
        let syncService: TestPaeoniaSyncService
        let celebrationStore: TestPairingCelebrationStore

        init() {
            userID = UUID()
            store = InMemoryAccessSyncSnapshotRepository()
            syncService = TestPaeoniaSyncService()
            celebrationStore = TestPairingCelebrationStore()
        }

        func makeViewModel(
            route: AccessRoute,
            invite: PairingInvite? = nil,
            authService: AuthServiceSpy? = nil
        ) -> RootViewModel {
            RootViewModel(
                syncService: syncService,
                authService: authService ?? AuthServiceSpy(
                    session: .test(id: userID.uuidString, profileStatus: .complete)
                ),
                accessRouteService: StaticAccessRouteService(route: route),
                accessSnapshotStore: store,
                inviteStore: TestPairingInviteStore(invite: invite, userID: userID.uuidString),
                pairingCelebrationStore: celebrationStore
            )
        }
    }

    @MainActor
    @Test func inviterWaitingScreenMovesToPairedWhenThePartnerAccepts() async throws {
        let fixture = Fixture()
        let coupleID = UUID()
        let viewModel = fixture.makeViewModel(route: .invitePending, invite: .test())
        await viewModel.start()
        #expect(viewModel.state == .invitePending)

        try await fixture.store.save(
            .testPaired(ownerUserID: fixture.userID, coupleID: coupleID, partnerDisplayName: "Riley")
        )

        #expect(await waitUntil { @MainActor in viewModel.state == .paired })
        #expect(viewModel.currentPartnerDisplayName == "Riley")
        #expect(viewModel.isPairingCelebrationPresented)
        // Sync restarts for the new couple without a refresh.
        let syncService = fixture.syncService
        #expect(await waitUntil {
            (await syncService.configuredSessions.last.flatMap { $0 })?.activeCoupleID == coupleID
        })
    }

    @MainActor
    @Test func partnerLeavingRoutesToTheEndedNoticeAndPurgesOnce() async throws {
        let fixture = Fixture()
        let viewModel = fixture.makeViewModel(route: .paired)
        await viewModel.start()
        #expect(viewModel.state == .paired)

        let ended = AccessSyncSnapshot.testEnded(ownerUserID: fixture.userID)
        try await fixture.store.save(ended)

        #expect(await waitUntil { @MainActor in viewModel.state == .relationshipEndedNotice })
        #expect(await fixture.syncService.relationshipAccessPurgePermanence == [true])

        // The feed restarts after a purge and writes the same snapshot again.
        // That must not purge a second time.
        try await fixture.store.save(ended)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.state == .relationshipEndedNotice)
        #expect(await fixture.syncService.relationshipAccessPurgePermanence == [true])
    }

    @MainActor
    @Test func lostCoupleEntitlementRoutesToThePaywallAndHidesContent() async throws {
        let fixture = Fixture()
        let viewModel = fixture.makeViewModel(route: .paired)
        await viewModel.start()

        try await fixture.store.save(.testPaywalled(ownerUserID: fixture.userID))

        #expect(await waitUntil { @MainActor in viewModel.state == .pairedPaywalled })
        #expect(await fixture.syncService.relationshipAccessPurgePermanence == [false])
    }

    @MainActor
    @Test func partnerNameChangeShowsWithoutARefresh() async throws {
        let fixture = Fixture()
        let coupleID = UUID()
        let viewModel = fixture.makeViewModel(route: .paired)
        await viewModel.start()

        try await fixture.store.save(
            .testPaired(ownerUserID: fixture.userID, coupleID: coupleID, partnerDisplayName: "Riley")
        )
        #expect(await waitUntil { @MainActor in viewModel.currentPartnerDisplayName == "Riley" })

        try await fixture.store.save(
            .testPaired(ownerUserID: fixture.userID, coupleID: coupleID, partnerDisplayName: "Rae")
        )
        #expect(await waitUntil { @MainActor in viewModel.currentPartnerDisplayName == "Rae" })
        #expect(viewModel.state == .paired)
        #expect(await fixture.syncService.relationshipAccessPurgePermanence.isEmpty)
    }

    @MainActor
    @Test func snapshotsForAnotherUserAreIgnored() async throws {
        let fixture = Fixture()
        let viewModel = fixture.makeViewModel(route: .paired)
        await viewModel.start()
        let partnerBefore = viewModel.currentPartnerDisplayName

        try await fixture.store.save(.testPaired(ownerUserID: UUID(), partnerDisplayName: "Someone else"))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.currentPartnerDisplayName == partnerBefore)
    }

    @MainActor
    @Test func snapshotsAfterSignOutDoNotRoute() async throws {
        let fixture = Fixture()
        let viewModel = fixture.makeViewModel(route: .unpaired)
        await viewModel.start()
        await viewModel.signOut()
        #expect(viewModel.state == .unauthenticated)

        try await fixture.store.save(.testPaired(ownerUserID: fixture.userID))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.state == .unauthenticated)
    }

    @MainActor
    @Test func foregroundActivationDoesNotRereadTheSnapshotItself() async throws {
        let fixture = Fixture()
        let viewModel = fixture.makeViewModel(route: .limitedAuthenticated)
        // No observation yet: write before the model starts, so only an explicit
        // re-read could route from this snapshot.
        try await fixture.store.save(.testPaired(ownerUserID: fixture.userID, partnerDisplayName: "Riley"))
        await viewModel.start()
        let stateAfterStart = viewModel.state

        await viewModel.refreshAfterForegroundActivation()

        #expect(viewModel.state == stateAfterStart)
        #expect(await fixture.syncService.runOnceReasons == [.foreground])
    }
}

actor TestPaeoniaSyncService: PaeoniaSyncing {
    private(set) var startCallCount = 0
    private(set) var requestedReasons: [SyncRequestReason] = []
    private(set) var runOnceReasons: [SyncRequestReason] = []
    private(set) var configuredSessions: [SyncSession?] = []
    private(set) var resetCallCount = 0
    private(set) var relationshipAccessPurgeOwnerUserIDs: [UUID] = []
    private(set) var relationshipAccessPurgePermanence: [Bool] = []
    /// Sign-out steps in order: `flush` (with whether the account was still signed in) and `purge`.
    private(set) var signOutSteps: [String] = []
    private var privacyRetryResults: [LocalPrivacyPurgeRetryResult]
    private let isSignedIn: (@Sendable () async -> Bool)?

    init(
        privacyRetryResults: [LocalPrivacyPurgeRetryResult] = [],
        isSignedIn: (@Sendable () async -> Bool)? = nil
    ) {
        self.privacyRetryResults = privacyRetryResults
        self.isSignedIn = isSignedIn
    }

    func flushPendingWrites(timeout _: Duration) async {
        let signedIn = await isSignedIn?() ?? true
        signOutSteps.append(signedIn ? "flush while signed in" : "flush after sign-out")
    }

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

    func resetForUserChange() async {
        resetCallCount += 1
        signOutSteps.append("purge")
    }

    func retryPendingPrivacyPurges() async -> LocalPrivacyPurgeRetryResult {
        guard !privacyRetryResults.isEmpty else {
            return .completed
        }
        return privacyRetryResults.removeFirst()
    }

    func purgeRelationshipAccess(
        ownerUserID: UUID,
        permanently: Bool
    ) async -> LocalPrivacyPurgeResult {
        relationshipAccessPurgeOwnerUserIDs.append(ownerUserID)
        relationshipAccessPurgePermanence.append(permanently)
        return .completed
    }
}

actor StaticAccessRouteService: AccessRouteServicing {
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
                relationshipState: RemoteRelationshipState(
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

extension AccessSyncSnapshot {
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

extension AccessSyncSnapshot {
    static func testEnded(ownerUserID: UUID, coupleID: UUID = UUID()) -> AccessSyncSnapshot {
        AccessSyncSnapshot(
            ownerUserID: ownerUserID,
            userEntitlement: .testEntitled(userID: ownerUserID),
            coupleEntitlement: nil,
            relationshipState: RemoteRelationshipState(
                coupleID: coupleID,
                pairID: UUID(),
                relationshipStatus: .ended,
                memberStatus: .endedNoticePending,
                partnerUserID: UUID(),
                partnerDisplayName: "Partner",
                partnerProfilePhotoAssetID: nil,
                startedOn: "2026-06-24",
                endedAt: Date(timeIntervalSince1970: 1_900_000_000),
                deleteAfter: nil,
                endedNoticeSeenAt: nil
            ),
            refreshedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    static func testPaywalled(ownerUserID: UUID, coupleID: UUID = UUID()) -> AccessSyncSnapshot {
        AccessSyncSnapshot(
            ownerUserID: ownerUserID,
            userEntitlement: nil,
            coupleEntitlement: RemoteCoupleEntitlement(
                coupleID: coupleID,
                isEntitled: false,
                coveringUserID: nil,
                source: nil,
                status: "expired",
                productID: nil,
                billingPeriod: nil,
                currentPeriodEnd: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            relationshipState: .test(coupleID: coupleID, partnerDisplayName: "Partner"),
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
    ) -> RemoteRelationshipState? {
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

private extension RemoteUserEntitlement {
    static func testEntitled(userID: UUID) -> RemoteUserEntitlement {
        RemoteUserEntitlement(
            userID: userID,
            isEntitled: true,
            source: "storekit",
            status: "active",
            productID: UUID(),
            billingPeriod: nil,
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension RemoteCoupleEntitlement {
    static func testEntitled(coupleID: UUID, coveringUserID: UUID) -> RemoteCoupleEntitlement {
        RemoteCoupleEntitlement(
            coupleID: coupleID,
            isEntitled: true,
            coveringUserID: coveringUserID,
            source: "storekit",
            status: "active",
            productID: UUID(),
            billingPeriod: nil,
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension RemoteRelationshipState {
    static func test(
        coupleID: UUID = UUID(),
        partnerDisplayName: String,
        partnerProfilePhotoAssetID: UUID? = nil,
        pairID: UUID? = nil
    ) -> RemoteRelationshipState {
        RemoteRelationshipState(
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
final class TestPairingCelebrationStore: PairingCelebrationStoring {
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
final class TestPairingInviteStore: PairingInviteStoring {
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
        case retryPrivacyPurges
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

    func resetForUserChange() async {}

    func retryPendingPrivacyPurges() async -> LocalPrivacyPurgeRetryResult {
        recorder.record(.retryPrivacyPurges)
        return .completed
    }

    func purgeRelationshipAccess(
        ownerUserID _: UUID,
        permanently _: Bool
    ) async -> LocalPrivacyPurgeResult {
        .completed
    }
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

    func signInWithGoogle() async throws -> AuthSession {
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

    func updateProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async throws -> AuthSession {
        AuthSession(
            id: "11111111-1111-1111-1111-111111111111",
            provider: .development,
            displayName: displayName,
            timeZoneID: "Europe/Oslo",
            profilePhotoAssetID: nil,
            profileStatus: .complete
        )
    }

    func signOut() async throws {}

    func requestAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        .completed
    }
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
