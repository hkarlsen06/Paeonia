import Foundation
import Observation
import Testing
@testable import PaeoniaApp

/// Each way a session ends must leave the server with no install of this phone that can start the
/// old account's partner's games. A signed-in launch keeps the install. These run the real root
/// view model, token service and install registry against a fake server.
@MainActor
struct RootLiveActivitySessionTests {
    private let userID = UUID()
    private let server = FakeLiveActivityTokenServer()
    private let registry: LiveActivityInstallRegistry
    private let service: LiveActivityTokenService

    init() {
        registry = LiveActivityInstallRegistry(store: InMemoryLiveActivityInstallStore(), server: server)
        service = LiveActivityTokenService(registry: registry)
    }

    private var completeSession: AuthSession {
        .test(id: userID.uuidString, profileStatus: .complete)
    }

    @Test func aSignedInLaunchKeepsTheInstallAndASignOutEndsIt() async throws {
        try await registerStartToken(for: userID.uuidString)
        let viewModel = makeViewModel(restoring: completeSession)
        await viewModel.start()
        #expect(server.liveInstalls.count == 1)

        await viewModel.signOut()

        #expect(await installsEnd())
    }

    @Test func aSessionThatEndsWhileTheAppRunsEndsTheInstall() async throws {
        try await registerStartToken(for: userID.uuidString)
        let provider = ActiveSessionFlag()
        let viewModel = makeViewModel(restoring: completeSession, provider: provider)
        await viewModel.start()

        provider.isActive = false

        #expect(await installsEnd())
    }

    @Test func deletingTheAccountEndsTheInstall() async throws {
        try await registerStartToken(for: userID.uuidString)
        let viewModel = makeViewModel(restoring: completeSession)
        await viewModel.start()

        await viewModel.deleteAccount()

        #expect(await installsEnd())
    }

    @Test func anotherAccountSigningInEndsThePreviousAccountsInstall() async throws {
        let previousOwner = UUID().uuidString
        try await registerStartToken(for: previousOwner)
        let viewModel = makeViewModel(restoring: completeSession, previousOwner: previousOwner)

        await viewModel.start()

        #expect(await installsEnd())
    }

    @Test func aLaunchThatFindsTheSessionGoneEndsTheInstall() async throws {
        try await registerStartToken(for: userID.uuidString)
        let viewModel = makeViewModel(restoring: nil)

        await viewModel.start()

        #expect(await installsEnd())
    }

    @Test func aBackgroundLaunchBeforeTheFirstUnlockKeepsTheInstall() async throws {
        try await registerStartToken(for: userID.uuidString)

        // Clerk cannot read the saved sign-in yet, so it loads with nobody signed in.
        service.resume(accountID: nil, clerkHasLoaded: true, storedSessionIsReadable: false)

        #expect(try registry.accountID == userID.uuidString)
        #expect(server.liveInstalls.count == 1)
    }

    @Test func aLaunchWithNobodySignedInEndsTheInstall() async throws {
        try await registerStartToken(for: userID.uuidString)

        service.resume(accountID: nil, clerkHasLoaded: true, storedSessionIsReadable: true)

        #expect(await installsEnd())
    }

    /// The phone registered its push-to-start token for `accountID` in an earlier run.
    private func registerStartToken(for accountID: String) async throws {
        _ = try await registry.register(.start, token: "start-token", activityID: nil, for: accountID)
    }

    private func installsEnd() async -> Bool {
        await waitUntil { @MainActor in server.liveInstalls.isEmpty && server.endedInstalls.count == 1 }
    }

    private func makeViewModel(
        restoring session: AuthSession?,
        previousOwner: String? = nil,
        provider: ActiveSessionFlag = ActiveSessionFlag()
    ) -> RootViewModel {
        RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: FlowAuthService(restoredSession: session),
            accessRouteService: ScriptedAccessRouteService([.pairedForFlowTest(ownerUserID: userID)]),
            accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
            systemSideEffects: LiveActivitySystemSideEffects(service: service),
            deviceOwnerStore: InMemoryRootDeviceOwnerStore(ownerUserID: previousOwner ?? userID.uuidString),
            authProviderSessionIsActive: { provider.isActive }
        )
    }
}

/// The real Live Activity service, and nothing else of the system.
@MainActor
private struct LiveActivitySystemSideEffects: RootSystemSideEffecting {
    let service: LiveActivityTokenService

    func resetPushRegistrationState() {}

    func endLiveActivitySession() {
        service.endSession()
    }

    func endGameLiveActivities() async {
        await GameLiveActivityController.endAll()
    }

    func reconcileDeliveredNotifications() {}

    func clearAppBadge() {}
}

@MainActor
@Observable
private final class ActiveSessionFlag {
    var isActive: Bool? = true
}
