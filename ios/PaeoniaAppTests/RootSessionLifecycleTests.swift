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

    /// The start date picked on the welcome flow goes into the outbox for the person who
    /// signs in, once, and the next signed-out screen after a sign-out is sign-in for returning.
    @Test func aStartDatePickedBeforeSignInIsQueuedForWhoeverSignsIn() async throws {
        let pending = InMemoryPendingSyncOperationRepository()
        let welcome = WelcomeFlowModel(
            store: InMemoryWelcomeFlowStore(),
            funnel: NoOpWelcomeFunnelRecorder(),
            startDateQueue: FirstDayStartedOnQueue(pendingOperationStore: pending),
            phoneHasNoOtherAccount: { true }
        )
        welcome.saveStartDate(try #require(PairingStartDate(rawValue: "2024-02-29").date()))
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: FlowAuthService(restoredSession: completeSession),
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            welcomeFlow: welcome
        )

        await viewModel.start()
        await viewModel.refreshAuthRoute()

        let queued = try await pending.inFlightOperations(ownerUserID: userID, kind: .setFirstDayStartedOn)
        let payload = try JSONDecoder().decode(
            SetFirstDayStartedOnPayload.self,
            from: try #require(queued.first?.requestData)
        )
        #expect(queued.count == 1)
        #expect(payload.startedOn == "2024-02-29")

        await viewModel.signOut()
        #expect(welcome.step == .signIn(.returning))
    }

    /// A start date that could not be queued for the person who signed in stays on the
    /// phone. Signing out drops it, so the next account never gets it.
    @Test func aStartDateThatFailedToQueueDoesNotReachTheNextAccount() async throws {
        let nextUserID = UUID()
        let pending = FailingFirstEnqueuePendingStore()
        let welcome = WelcomeFlowModel(
            store: InMemoryWelcomeFlowStore(),
            funnel: NoOpWelcomeFunnelRecorder(),
            startDateQueue: FirstDayStartedOnQueue(pendingOperationStore: pending),
            phoneHasNoOtherAccount: { true }
        )
        welcome.saveStartDate(try #require(PairingStartDate(rawValue: "2024-02-29").date()))
        let viewModel = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: FlowAuthService(
                restoredSession: completeSession,
                signInSession: .test(id: nextUserID.uuidString, profileStatus: .complete)
            ),
            accessRouteService: ScriptedAccessRouteService([
                .pairedForFlowTest(ownerUserID: userID),
                .pairedForFlowTest(ownerUserID: nextUserID),
            ]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            welcomeFlow: welcome
        )

        await viewModel.start()
        #expect(await pending.attemptedOwnerIDs == [userID])

        await viewModel.signOut()
        await viewModel.signInWithGoogle()

        #expect(viewModel.currentSession?.id == nextUserID.uuidString)
        #expect(await pending.attemptedOwnerIDs == [userID])
        #expect(try await pending.inFlightOperations(ownerUserID: nextUserID, kind: .setFirstDayStartedOn).isEmpty)
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

/// Refuses the first write, as a full disk would, and keeps the ones after it.
private actor FailingFirstEnqueuePendingStore: PendingSyncOperationPersisting {
    private let kept = InMemoryPendingSyncOperationRepository()
    private(set) var attemptedOwnerIDs: [UUID] = []

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        attemptedOwnerIDs.append(request.ownerUserID)
        guard attemptedOwnerIDs.count > 1 else {
            throw FlowTestError.unavailable
        }
        try await kept.enqueue(request)
    }

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        try await kept.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }

    func readyOperations(
        ownerUserID _: UUID,
        limit _: Int,
        now _: Date
    ) async throws -> [PendingSyncOperationSnapshot] {
        []
    }

    func nextPendingOperationDate(ownerUserID _: UUID, now _: Date) async throws -> Date? {
        nil
    }

    func markSending(clientOperationID _: UUID, at _: Date) async throws {}
    func markSucceeded(clientOperationID _: UUID, at _: Date) async throws {}
    func markRetryableFailure(
        clientOperationID _: UUID,
        errorDescription _: String,
        nextRetryAt _: Date?,
        at _: Date
    ) async throws {}
    func markTerminalFailure(clientOperationID _: UUID, errorDescription _: String, at _: Date) async throws {}
    func deleteCompleted(ownerUserID _: UUID) async throws {}
    func resetInFlight(ownerUserID _: UUID) async throws {}
}

// swiftlint:enable async_without_await
