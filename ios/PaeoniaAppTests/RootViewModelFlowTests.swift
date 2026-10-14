import AuthenticationServices
import Foundation
import Testing
@testable import PaeoniaApp

/// Root routing during sign-in, profile setup, slow launches, tab resets,
/// profile saves, and account deletion.
@MainActor
struct RootViewModelFlowTests {
    private let userID = UUID()

    private var completeSession: AuthSession {
        .test(id: userID.uuidString, profileStatus: .complete)
    }

    private func makeViewModel(
        auth: FlowAuthService,
        access: any AccessRouteServicing,
        store: InMemoryAccessSyncSnapshotRepository = InMemoryAccessSyncSnapshotRepository(),
        syncService: TestPaeoniaSyncService = TestPaeoniaSyncService(),
        savedAccessGracePeriod: Duration = .seconds(1)
    ) -> RootViewModel {
        RootViewModel(
            syncService: syncService,
            authService: auth,
            accessRouteService: access,
            accessSnapshotStore: store,
            inviteStore: TestPairingInviteStore(),
            pairingCelebrationStore: TestPairingCelebrationStore(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            savedAccessGracePeriod: savedAccessGracePeriod
        )
    }

    // MARK: - Holding the current screen

    @Test func signInKeepsTheSignInScreenWhileAccessResolves() async {
        let access = ScriptedAccessRouteService([.unpairedForFlowTest], blockedCall: 1)
        let viewModel = makeViewModel(
            auth: FlowAuthService(signInSession: completeSession),
            access: access
        )
        await viewModel.start()
        #expect(viewModel.state == .unauthenticated)

        let signIn = Task { await viewModel.signInWithGoogle() }
        await access.waitForBlockedCall()

        // This used to be `.launching`: an empty plum screen with no spinner.
        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.signingInWith == .google)

        await access.release()
        await signIn.value
        #expect(viewModel.state == .unpaired)
        #expect(viewModel.signingInWith == nil)
        #expect(!viewModel.isWorking)
    }

    @Test func failedSignInClearsTheButtonSpinner() async {
        let viewModel = makeViewModel(
            auth: FlowAuthService(signInSession: nil),
            access: ScriptedAccessRouteService([.unpairedForFlowTest])
        )
        await viewModel.start()

        await viewModel.signInWithGoogle()

        #expect(viewModel.signingInWith == nil)
        #expect(viewModel.notice == .signInFailed)
        #expect(viewModel.state == .unauthenticated)
    }

    @Test func finishingProfileSetupKeepsTheSetupScreenWhileAccessResolves() async {
        let access = ScriptedAccessRouteService([.unpairedForFlowTest], blockedCall: 1)
        let viewModel = makeViewModel(
            auth: FlowAuthService(restoredSession: .test(id: userID.uuidString, profileStatus: .needsOnboarding)),
            access: access
        )
        await viewModel.start()
        #expect(viewModel.state == .onboarding)

        let finish = Task {
            await viewModel.completeOnboarding(displayName: "Mina", timeZoneID: "Europe/Oslo", profilePhotoData: nil)
        }
        await access.waitForBlockedCall()

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.isWorking)

        await access.release()
        await finish.value
        #expect(viewModel.state == .unpaired)
    }

    // MARK: - Slow cold launch

    @Test func slowColdLaunchShowsTheSavedPairedStateUntilTheServerAnswers() async throws {
        let store = InMemoryAccessSyncSnapshotRepository()
        try await store.save(.testPaired(ownerUserID: userID, partnerDisplayName: "Riley"))
        let access = ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)], blockedCall: 1)
        let viewModel = makeViewModel(
            auth: FlowAuthService(restoredSession: completeSession),
            access: access,
            store: store,
            savedAccessGracePeriod: .milliseconds(20)
        )

        let start = Task { await viewModel.start() }
        await access.waitForBlockedCall()

        #expect(await waitUntil { @MainActor in viewModel.state == .paired })
        #expect(viewModel.currentPartnerDisplayName == "Riley")

        await access.release()
        await start.value
        #expect(viewModel.state == .paired)
    }

    @Test func slowColdLaunchKeepsWaitingWhenTheSavedStateIsNotPaired() async throws {
        let store = InMemoryAccessSyncSnapshotRepository()
        try await store.save(.testEnded(ownerUserID: userID))
        let access = ScriptedAccessRouteService([.unpairedForFlowTest], blockedCall: 1)
        let viewModel = makeViewModel(
            auth: FlowAuthService(restoredSession: completeSession),
            access: access,
            store: store,
            savedAccessGracePeriod: .milliseconds(20)
        )

        let start = Task { await viewModel.start() }
        await access.waitForBlockedCall()
        try await Task.sleep(for: .milliseconds(150))

        #expect(viewModel.state == .launching)

        await access.release()
        await start.value
        #expect(viewModel.state == .unpaired)
    }

    @Test func serverResultReplacesTheSavedPairedPreviewAndPurges() async throws {
        let store = InMemoryAccessSyncSnapshotRepository()
        try await store.save(.testPaired(ownerUserID: userID))
        let syncService = TestPaeoniaSyncService()
        let access = ScriptedAccessRouteService([.unpairedForFlowTest], blockedCall: 1)
        let viewModel = makeViewModel(
            auth: FlowAuthService(restoredSession: completeSession),
            access: access,
            store: store,
            syncService: syncService,
            savedAccessGracePeriod: .milliseconds(20)
        )

        let start = Task { await viewModel.start() }
        await access.waitForBlockedCall()
        #expect(await waitUntil { @MainActor in viewModel.state == .paired })

        await access.release()
        await start.value
        #expect(viewModel.state == .unpaired)
        #expect(await syncService.relationshipAccessPurgePermanence == [true])
    }

    // MARK: - Tabs

    @Test func leavingThePairedStateReturnsTheTabsToHome() async {
        let viewModel = makeViewModel(
            auth: FlowAuthService(restoredSession: completeSession),
            access: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID), .unpairedForFlowTest])
        )
        await viewModel.start()
        #expect(viewModel.state == .paired)
        viewModel.selectMainTab(.us)

        await viewModel.refreshAfterPairingChange()

        #expect(viewModel.state == .unpaired)
        #expect(viewModel.selectedMainTab == .home)
    }

    @Test func signingOutReturnsTheTabsToHome() async {
        let viewModel = makeViewModel(
            auth: FlowAuthService(restoredSession: completeSession),
            access: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)])
        )
        await viewModel.start()
        viewModel.selectMainTab(.memories)

        await viewModel.signOut()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.selectedMainTab == .home)
    }

    // MARK: - Profile save

    @Test func profileSaveKeepsARouteChangeThatArrivedDuringTheSave() async throws {
        let store = InMemoryAccessSyncSnapshotRepository()
        let auth = FlowAuthService(restoredSession: completeSession, gatesProfileUpdate: true)
        let access = ScriptedAccessRouteService(
            [.pairedForFlowTest(ownerUserID: userID), .pairedForFlowTest(ownerUserID: userID)],
            blockedCall: 2
        )
        let viewModel = makeViewModel(auth: auth, access: access, store: store)
        await viewModel.start()
        #expect(viewModel.state == .paired)

        let save = Task {
            await viewModel.updateCurrentProfile(displayName: "Mina", profilePhotoUpdate: .unchanged)
        }
        await auth.waitForProfileUpdate()

        // The partner leaves while the save is still sending.
        try await store.save(.testEnded(ownerUserID: userID))
        #expect(await waitUntil { @MainActor in viewModel.state == .relationshipEndedNotice })

        await auth.releaseProfileUpdate()
        await access.waitForBlockedCall()

        // The finished save must not put the old paired route back on screen.
        #expect(viewModel.state == .relationshipEndedNotice)
        #expect(viewModel.currentSession?.displayName == "Mina")

        await access.release()
        #expect(await save.value)
    }

    // MARK: - Account deletion

    @Test func cancellingTheAppleSheetKeepsTheAccount() async {
        let auth = FlowAuthService(restoredSession: appleSession)
        let viewModel = makeViewModel(auth: auth, access: ScriptedAccessRouteService([.unpairedForFlowTest]))
        await viewModel.start()

        await viewModel.deleteAccount(
            reauthenticatingWith: StubAppleSignInProvider(error: ASAuthorizationError(.canceled))
        )

        #expect(await auth.deletionCodes.isEmpty)
        #expect(viewModel.state == .unpaired)
        #expect(!viewModel.isWorking)
    }

    @Test func appleFailureOtherThanCancelStillDeletes() async {
        let auth = FlowAuthService(restoredSession: appleSession)
        let viewModel = makeViewModel(auth: auth, access: ScriptedAccessRouteService([.unpairedForFlowTest]))
        await viewModel.start()

        await viewModel.deleteAccount(
            reauthenticatingWith: StubAppleSignInProvider(error: ASAuthorizationError(.failed))
        )

        #expect(await auth.deletionCodes == [nil])
        #expect(viewModel.state == .unauthenticated)
    }

    @Test func appleReauthenticationPassesTheFreshCode() async {
        let auth = FlowAuthService(restoredSession: appleSession)
        let viewModel = makeViewModel(auth: auth, access: ScriptedAccessRouteService([.unpairedForFlowTest]))
        await viewModel.start()

        await viewModel.deleteAccount(reauthenticatingWith: StubAppleSignInProvider(code: "fresh-code"))

        #expect(await auth.deletionCodes == ["fresh-code"])
    }

    @Test func secondDeleteWhileTheAppleSheetIsOpenIsIgnored() async {
        let auth = FlowAuthService(restoredSession: appleSession)
        let viewModel = makeViewModel(auth: auth, access: ScriptedAccessRouteService([.unpairedForFlowTest]))
        await viewModel.start()
        let provider = GatedAppleSignInProvider()

        let first = Task { await viewModel.deleteAccount(reauthenticatingWith: provider) }
        await provider.waitForSheet()
        await viewModel.deleteAccount(reauthenticatingWith: provider)
        provider.finish(code: "code")
        await first.value

        #expect(provider.signInCount == 1)
        #expect(await auth.deletionCodes == ["code"])
    }

    private var appleSession: AuthSession {
        AuthSession(
            id: userID.uuidString,
            provider: .apple,
            displayName: "Mina",
            timeZoneID: "Europe/Oslo",
            profilePhotoAssetID: nil,
            profileStatus: .complete
        )
    }
}

/// The notification primer needs nothing from the location preference, and
/// the location primer still waits until that preference is known.
@MainActor
struct RootPermissionPrimerOrderTests {
    @Test func notificationPrimerDoesNotWaitForTheLocationPreference() async throws {
        let suiteName = "RootPermissionPrimerOrderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pushStore = UserDefaultsPushPermissionPrimerStore(defaults: defaults)
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: pushStore,
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )
        let identity = LocationIdentity(currentUserID: UUID(), coupleID: UUID())

        await coordinator.presentNotificationPrimerIfNeeded(
            identity: identity,
            pushAuthorization: FixedPushAuthorization(isNotDetermined: true)
        )
        #expect(coordinator.presentedPrimer == .notifications)

        pushStore.markResponded()
        coordinator.dismiss()
        coordinator.presentLocationPrimerIfNeeded(
            identity: identity,
            sharingStateIsKnown: false,
            sharingEnabled: false,
            locationAuthorizationState: .notDetermined
        )
        #expect(coordinator.presentedPrimer == nil)
    }
}
