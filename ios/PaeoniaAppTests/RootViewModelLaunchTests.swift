import Foundation
import Testing
@testable import PaeoniaApp

/// The cold launch of a signed-in, paired person: Home opens from the state saved
/// on the phone while the launch call is open, and the server's answer settles it.
@MainActor
struct RootViewModelLaunchTests {
    private let userID = UUID()

    private var completeSession: AuthSession {
        .test(id: userID.uuidString, profileStatus: .complete)
    }

    /// A launch whose restore stays open until the test releases it, with the
    /// saved session and a saved paired snapshot on the phone.
    private struct PairedLaunch {
        let viewModel: RootViewModel
        let auth: FlowAuthService
        let access: ScriptedAccessRouteService
        let syncService: TestPaeoniaSyncService
    }

    private func makePairedLaunch(
        launchAccess: RemoteAccessSnapshot?,
        restoreError: (any Error)? = nil,
        deviceOwner: String? = nil
    ) async throws -> PairedLaunch {
        let store = InMemoryAccessSyncSnapshotRepository()
        try await store.save(.testPaired(ownerUserID: userID, partnerDisplayName: "Riley"))
        let auth = FlowAuthService(
            restoredSession: completeSession,
            storedSession: completeSession,
            launchAccess: launchAccess,
            restoreError: restoreError,
            gatesRestore: true
        )
        let access = ScriptedAccessRouteService([.unpairedForFlowTest])
        let syncService = TestPaeoniaSyncService()
        let viewModel = RootViewModel(
            syncService: syncService,
            authService: auth,
            accessRouteService: access,
            accessSnapshotStore: store,
            inviteStore: TestPairingInviteStore(),
            pairingCelebrationStore: TestPairingCelebrationStore(),
            systemSideEffects: NoOpRootSystemSideEffects(),
            deviceOwnerStore: InMemoryRootDeviceOwnerStore(ownerUserID: deviceOwner ?? userID.uuidString)
        )
        return PairedLaunch(viewModel: viewModel, auth: auth, access: access, syncService: syncService)
    }

    @Test func launchShowsSavedHomeBeforeTheServerAnswersThenSettlesWithoutAnotherCall() async throws {
        let launch = try await makePairedLaunch(launchAccess: .pairedForFlowTest(ownerUserID: userID))

        let start = Task { await launch.viewModel.start() }
        await launch.auth.waitForRestore()

        // Home is up while the launch call is still open. Nothing is committed yet.
        #expect(launch.viewModel.state == .paired)
        #expect(launch.viewModel.currentPartnerDisplayName == "Riley")
        #expect(!launch.viewModel.route.isAccessSettled)
        #expect(!launch.viewModel.isPairingCelebrationPresented)

        await launch.auth.releaseRestore()
        await start.value
        #expect(launch.viewModel.state == .paired)
        #expect(launch.viewModel.route.isAccessSettled)
        // The launch call carried the access state, so no second call was made.
        #expect(await launch.access.callCount == 0)
        #expect(await launch.syncService.relationshipAccessPurgePermanence.isEmpty)
    }

    @Test func serverAnswerAfterTheSavedLaunchHomeMovesThePersonOffHomeAndPurges() async throws {
        let launch = try await makePairedLaunch(launchAccess: .unpairedForFlowTest(ownerUserID: userID))

        let start = Task { await launch.viewModel.start() }
        await launch.auth.waitForRestore()
        #expect(launch.viewModel.state == .paired)

        await launch.auth.releaseRestore()
        await start.value
        #expect(launch.viewModel.state == .unpaired)
        #expect(await launch.syncService.relationshipAccessPurgePermanence == [true])
    }

    @Test func failedLaunchCallDoesNotLeaveTheSavedHomeOnScreen() async throws {
        let launch = try await makePairedLaunch(
            launchAccess: nil,
            restoreError: PaeoniaConvexError.http(status: 403, body: "Forbidden")
        )

        let start = Task { await launch.viewModel.start() }
        await launch.auth.waitForRestore()
        #expect(launch.viewModel.state == .paired)

        await launch.auth.releaseRestore()
        await start.value
        #expect(launch.viewModel.state == .unauthenticated)
        #expect(launch.viewModel.notice == .sessionLoadFailed)
    }

    @Test func launchDoesNotShowSavedHomeWhenThePhoneHoldsAnotherAccountsData() async throws {
        let launch = try await makePairedLaunch(
            launchAccess: .pairedForFlowTest(ownerUserID: userID),
            deviceOwner: UUID().uuidString
        )

        let start = Task { await launch.viewModel.start() }
        await launch.auth.waitForRestore()
        #expect(launch.viewModel.state == .launching)

        await launch.auth.releaseRestore()
        await start.value
        #expect(launch.viewModel.state == .paired)
    }
}
