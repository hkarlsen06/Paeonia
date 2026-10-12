import Foundation
import Observation
import Testing
@testable import PaeoniaApp

// swiftlint:disable async_without_await

/// Sessions that end on their own, account switches, sync that must not start
/// for a departed user, refreshes that must never sign anyone out, and profile
/// saves that report success without waiting for sync.
@MainActor
struct RootSessionLifecycleTests {
    private let userID = UUID()

    private var completeSession: AuthSession {
        .test(id: userID.uuidString, profileStatus: .complete)
    }

    @Test func sessionThatEndsWhileRunningReturnsToSignInAndKeepsData() async {
        let provider = ProviderSessionFlag()
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: FlowAuthService(restoredSession: completeSession),
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            inviteStore: TestPairingInviteStore(),
            pairingCelebrationStore: TestPairingCelebrationStore(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            authProviderSessionIsActive: { provider.isActive }
        )
        await viewModel.start()
        #expect(viewModel.state == .paired)

        provider.isActive = false

        #expect(await waitUntil { @MainActor in viewModel.state == .unauthenticated })
        #expect(viewModel.notice == .sessionEnded)
        // Nothing saved on the phone is removed for a session that only lapsed.
        #expect(await syncService.resetCallCount == 0)
    }

    @Test func providerStillLoadingIsNotTreatedAsASignOut() async throws {
        let provider = ProviderSessionFlag(isActive: nil)
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: FlowAuthService(restoredSession: completeSession),
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            authProviderSessionIsActive: { provider.isActive }
        )
        await viewModel.start()
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.state == .paired)
        #expect(viewModel.notice == nil)
    }

    @Test func signingInAsSomeoneElseClearsThePreviousPersonsData() async {
        let previousOwner = UUID()
        let ownerStore = InMemoryRootDeviceOwnerStore(ownerUserID: previousOwner.uuidString)
        let syncService = TestPaeoniaSyncService()
        let viewModel = makeViewModel(syncService: syncService, ownerStore: ownerStore)

        await viewModel.start()

        #expect(await syncService.resetCallCount == 1)
        let purgedSession = await syncService.configuredSessions.first.flatMap { $0 }
        #expect(purgedSession?.userID == previousOwner)
        #expect(ownerStore.ownerUserID == userID.uuidString)
        #expect(viewModel.state == .paired)
    }

    /// A join code belongs to the person who was signed in. It used to carry into
    /// the next account when a session ended on its own.
    @Test func joinCodeIsKeptOnlyWhileTheSamePersonIsSignedIn() {
        let person = UUID().uuidString

        #expect(RootView.keepsJoinInviteCode(from: nil, to: person))
        #expect(RootView.keepsJoinInviteCode(from: person, to: person.lowercased()))
        #expect(!RootView.keepsJoinInviteCode(from: person, to: nil))
        #expect(!RootView.keepsJoinInviteCode(from: person, to: UUID().uuidString))
    }

    @Test func samePersonSigningBackInKeepsTheirData() async {
        let ownerStore = InMemoryRootDeviceOwnerStore(ownerUserID: userID.uuidString)
        let syncService = TestPaeoniaSyncService()
        let viewModel = makeViewModel(syncService: syncService, ownerStore: ownerStore)

        await viewModel.start()

        #expect(await syncService.resetCallCount == 0)
    }

    @Test func signingOutForgetsWhoseDataWasOnThePhone() async {
        let ownerStore = InMemoryRootDeviceOwnerStore()
        let viewModel = makeViewModel(syncService: TestPaeoniaSyncService(), ownerStore: ownerStore)
        await viewModel.start()
        #expect(ownerStore.ownerUserID == userID.uuidString)

        await viewModel.signOut()

        #expect(ownerStore.ownerUserID == nil)
    }

    @Test func syncDoesNotStartForASessionThatEndedWhileSyncWasStarting() async {
        let syncService = GatedSyncService()
        let liveSync = RecordingLiveSync()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: FlowAuthService(restoredSession: completeSession),
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            liveSync: liveSync
        )
        await viewModel.start(deferringSyncUntilLaunchCompletes: true)
        await liveSync.holdNextStart()

        let startup = Task { await viewModel.finishDeferredLaunchStartup() }
        await liveSync.waitForHeldStart()
        await viewModel.signOut()
        await liveSync.releaseStart()
        await startup.value

        // Before the fix the stale startup went on to start the sync service
        // for someone who had already signed out, and left the feeds running.
        #expect(await syncService.startCallCount == 0)
        #expect(await liveSync.events.last == .stop)
    }

    @Test func failedRefreshAfterAPurchaseKeepsThePersonSignedIn() async {
        let auth = FlowAuthService(restoredSession: completeSession, failsRestoreAfterFirst: true)
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: auth,
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: NoOpRootSystemSideEffects()
        )
        await viewModel.start()

        await viewModel.refreshAfterSubscriptionChange()
        await viewModel.refreshAuthRoute()

        #expect(viewModel.state == .paired)
        #expect(viewModel.notice == nil)
    }

    @Test func profileSaveReportsSuccessWithoutWaitingForSync() async {
        let syncService = GatedSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: FlowAuthService(restoredSession: completeSession),
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: NoOpRootSystemSideEffects()
        )
        await viewModel.start()
        await syncService.holdNextRun()

        let saved = await viewModel.updateCurrentProfile(displayName: "Mina", profilePhotoUpdate: .unchanged)

        #expect(saved)
        #expect(viewModel.currentSession?.displayName == "Mina")
        await syncService.releaseRun()
    }

    private func makeViewModel(
        syncService: TestPaeoniaSyncService,
        ownerStore: any RootDeviceOwnerStoring
    ) -> RootViewModel {
        RootViewModel(
            syncService: syncService,
            authService: FlowAuthService(restoredSession: completeSession),
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            deviceOwnerStore: ownerStore
        )
    }
}

/// Only the newest banner host draws the banner, so a sheet's banner is never
/// hidden under it or shown twice.
@MainActor
struct PaeoniaBannerHostTests {
    @Test func newestHostDrawsTheBannerUntilItGoesAway() {
        let center = PaeoniaBannerCenter()
        let root = UUID()
        let sheet = UUID()

        center.registerHost(root)
        #expect(center.isActiveHost(root))

        center.registerHost(sheet)
        #expect(center.isActiveHost(sheet))
        #expect(!center.isActiveHost(root))

        center.unregisterHost(sheet)
        #expect(center.isActiveHost(root))
    }
}

// MARK: - Test doubles

@MainActor
@Observable
private final class ProviderSessionFlag {
    var isActive: Bool?

    init(isActive: Bool? = true) {
        self.isActive = isActive
    }
}

private actor RecordingLiveSync: LiveSyncCoordinating {
    enum Event: Equatable {
        case start
        case stop
    }

    private(set) var events: [Event] = []
    private var holdsStart = false
    private var heldStartBegan = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var startRelease: CheckedContinuation<Void, Never>?

    func holdNextStart() {
        holdsStart = true
    }

    func waitForHeldStart() async {
        guard !heldStartBegan else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseStart() {
        startRelease?.resume()
        startRelease = nil
    }

    func start(session _: SyncSession) async {
        events.append(.start)
        guard holdsStart else { return }
        holdsStart = false
        heldStartBegan = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        await withCheckedContinuation { startRelease = $0 }
    }

    func stop() async {
        events.append(.stop)
    }

    func pause() async {}

    func resume() {}
}

/// A sync service that can hold the next `runOnce` call.
private actor GatedSyncService: PaeoniaSyncing {
    private(set) var startCallCount = 0
    private var holdsRun = false
    private var runRelease: CheckedContinuation<Void, Never>?

    func holdNextRun() {
        holdsRun = true
    }

    func configure(session _: SyncSession?) {}

    func releaseRun() {
        runRelease?.resume()
        runRelease = nil
    }

    func start() {
        startCallCount += 1
    }

    func requestSync(reason _: SyncRequestReason) {}

    func runOnce(reason _: SyncRequestReason) async -> SyncRunResult {
        if holdsRun {
            holdsRun = false
            await withCheckedContinuation { runRelease = $0 }
        }
        return SyncRunResult(
            status: .succeeded,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    func stop() {}

    func resetForUserChange() async {}

    func purgeRelationshipAccess(ownerUserID _: UUID, permanently _: Bool) async -> LocalPrivacyPurgeResult {
        .completed
    }
}

// swiftlint:enable async_without_await
