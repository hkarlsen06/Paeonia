import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct SettingsViewModelTests {
    @Test func loadReadsWidgetAlertsAndDeniedStatus() async {
        let preferences = FakeNotificationPreferences(enabled: false)
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization(denied: true)
        )

        await viewModel.load()

        #expect(viewModel.isLoaded)
        #expect(viewModel.widgetAlertsEnabled == false)
        #expect(viewModel.systemNotificationsDenied)
    }

    @Test func togglePersistsThroughService() async {
        let preferences = FakeNotificationPreferences(enabled: true)
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setWidgetAlertsEnabled(false)

        #expect(viewModel.widgetAlertsEnabled == false)
        #expect(await preferences.lastSetValue == false)
        #expect(viewModel.notice == nil)
    }

    @Test func failedSaveRevertsAndShowsNotice() async {
        let preferences = FakeNotificationPreferences(enabled: true, failOnSet: true)
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setWidgetAlertsEnabled(false)

        // The optimistic flip is rolled back and the failure surfaces.
        #expect(viewModel.widgetAlertsEnabled == true)
        #expect(viewModel.notice == .saveFailed)
    }

    @Test func unchangedValueDoesNotWrite() async {
        let preferences = FakeNotificationPreferences(enabled: true)
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setWidgetAlertsEnabled(true)

        #expect(await preferences.setCallCount == 0)
    }

    @Test func leaveRelationshipSucceeds() async {
        let pairing = FakePairingService(leaveResult: .success(true))
        let viewModel = SettingsViewModel(
            preferences: FakeNotificationPreferences(enabled: true),
            authorization: FakePushAuthorization(),
            pairingService: pairing,
            operationProvider: FakeOperationProvider()
        )

        let didLeave = await viewModel.leaveRelationship()

        #expect(didLeave)
        #expect(viewModel.notice == nil)
        #expect(viewModel.isLeavingRelationship == false)
        #expect(await pairing.leaveCallCount == 1)
    }

    @Test func leaveRelationshipFailureSurfacesNotice() async {
        let pairing = FakePairingService(leaveResult: .failure(FakePreferencesError.failed))
        let viewModel = SettingsViewModel(
            preferences: FakeNotificationPreferences(enabled: true),
            authorization: FakePushAuthorization(),
            pairingService: pairing,
            operationProvider: FakeOperationProvider()
        )

        let didLeave = await viewModel.leaveRelationship()

        #expect(didLeave == false)
        #expect(viewModel.notice == .leaveFailed)
        #expect(viewModel.isLeavingRelationship == false)
    }
}

private enum FakePreferencesError: Error {
    case failed
}

// An actor supplies the async-ness, so the sync bodies need no `async`/`await`.
private actor FakeNotificationPreferences: NotificationPreferencesProviding {
    private var enabled: Bool
    private let failOnSet: Bool
    private(set) var setCallCount = 0
    private(set) var lastSetValue: Bool?

    init(enabled: Bool, failOnSet: Bool = false) {
        self.enabled = enabled
        self.failOnSet = failOnSet
    }

    func loadWidgetAlertsEnabled() -> Bool {
        enabled
    }

    func setWidgetAlertsEnabled(_ value: Bool) throws {
        setCallCount += 1
        if failOnSet {
            throw FakePreferencesError.failed
        }
        lastSetValue = value
        enabled = value
    }
}

private struct FakePushAuthorization: PushAuthorizationProviding {
    var denied = false

    func requestAuthorizationIfNeeded() {}

    func isDenied() -> Bool {
        denied
    }
}

/// A pairing service whose only exercised method is `leaveRelationship`; the rest
/// of the protocol is unused by the You-tab flow.
private actor FakePairingService: PairingServicing {
    private let leaveResult: Result<Bool, Error>
    private(set) var leaveCallCount = 0

    init(leaveResult: Result<Bool, Error>) {
        self.leaveResult = leaveResult
    }

    func createInvite(operation: PairingClientOperation, expiresAt: Date) async throws -> PairingInvite {
        fatalError("unused")
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        fatalError("unused")
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> PairingAcceptedRelationship {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        leaveCallCount += 1
        return try leaveResult.get()
    }
}

@MainActor
private final class FakeOperationProvider: PairingClientOperationProviding {
    func makeOperation() -> PairingClientOperation {
        SyncClientOperation(clientID: UUID(), clientSequence: 1)
    }
}
