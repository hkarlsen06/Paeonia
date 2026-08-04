import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
struct SettingsViewModelTests {
    @Test func loadReadsWidgetAlertsAndDeniedStatus() async {
        let preferences = FakeNotificationPreferences(preferences: NotificationPreferences(
            streakRemindersEnabled: false,
            dailyChallengeEnabled: true,
            partnerAnsweredEnabled: false,
            messagesEnabled: false,
            widgetUpdatesEnabled: false,
            memoriesEnabled: false
        ))
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization(denied: true)
        )

        await viewModel.load()

        #expect(viewModel.isLoaded)
        #expect(viewModel.streakRemindersEnabled == false)
        #expect(viewModel.dailyChallengeEnabled)
        #expect(viewModel.partnerAnsweredEnabled == false)
        #expect(viewModel.messagesEnabled == false)
        #expect(viewModel.widgetAlertsEnabled == false)
        #expect(viewModel.memoriesEnabled == false)
        #expect(viewModel.systemNotificationsDenied)
    }

    @Test func togglePersistsThroughService() async {
        let preferences = FakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setNotificationPreference(.widgetUpdates, enabled: false)

        #expect(viewModel.widgetAlertsEnabled == false)
        #expect(await preferences.lastSetKind == .widgetUpdates)
        #expect(await preferences.lastSetValue == false)
        #expect(viewModel.notice == nil)
    }

    @Test func togglePersistsPartnerAnswerPreference() async {
        let preferences = FakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setNotificationPreference(.partnerAnswered, enabled: false)

        #expect(viewModel.partnerAnsweredEnabled == false)
        #expect(await preferences.lastSetKind == .partnerAnswered)
        #expect(await preferences.lastSetValue == false)
    }

    @Test func togglePersistsMemoryPreference() async {
        let preferences = FakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setNotificationPreference(.memories, enabled: false)

        #expect(viewModel.memoriesEnabled == false)
        #expect(await preferences.lastSetKind == .memories)
        #expect(await preferences.lastSetValue == false)
    }

    @Test func togglePersistsMessagePreference() async {
        let preferences = FakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setNotificationPreference(.messages, enabled: false)

        #expect(viewModel.messagesEnabled == false)
        #expect(await preferences.lastSetKind == .messages)
        #expect(await preferences.lastSetValue == false)
    }

    @Test func failedSaveRevertsAndShowsNotice() async {
        let preferences = FakeNotificationPreferences(failOnSet: true)
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setNotificationPreference(.streakReminders, enabled: false)

        // The optimistic flip is rolled back and the failure surfaces.
        #expect(viewModel.streakRemindersEnabled == true)
        #expect(viewModel.notice == .saveFailed)
    }

    @Test func unchangedValueDoesNotWrite() async {
        let preferences = FakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: FakePushAuthorization()
        )
        await viewModel.load()

        await viewModel.setNotificationPreference(.dailyChallenge, enabled: true)

        #expect(await preferences.setCallCount == 0)
    }

    @Test func leaveRelationshipSucceeds() async {
        let pairing = FakePairingService(leaveResult: .success(true))
        let viewModel = SettingsViewModel(
            preferences: FakeNotificationPreferences(),
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
            preferences: FakeNotificationPreferences(),
            authorization: FakePushAuthorization(),
            pairingService: pairing,
            operationProvider: FakeOperationProvider()
        )

        let didLeave = await viewModel.leaveRelationship()

        #expect(didLeave == false)
        #expect(viewModel.notice == .leaveFailed)
        #expect(viewModel.isLeavingRelationship == false)
    }

    @Test func restorePurchasesConfiguresUserAndSurfacesSuccess() async {
        let storeKit = FakeSettingsStoreKit(restoreResult: .success(true))
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: FakePushAuthorization(),
            userID: "user-123",
            storeKitService: storeKit
        )

        let restored = await viewModel.restorePurchases()

        #expect(storeKit.configuredUserID == "user-123")
        #expect(storeKit.restoreCallCount == 1)
        #expect(restored)
        #expect(viewModel.notice == .purchasesRestored)
        #expect(!viewModel.isRestoringPurchases)
    }

    @Test func restorePurchasesSurfacesNothingFound() async {
        let storeKit = FakeSettingsStoreKit(restoreResult: .success(false))
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: FakePushAuthorization(),
            userID: "user-123",
            storeKitService: storeKit
        )

        let restored = await viewModel.restorePurchases()

        #expect(!restored)
        #expect(viewModel.notice == .noPurchasesToRestore)
    }

    @Test func restorePurchasesSurfacesFailure() async {
        let storeKit = FakeSettingsStoreKit(
            restoreResult: .failure(PaeoniaPurchaseError.restoreFailed)
        )
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: FakePushAuthorization(),
            userID: "user-123",
            storeKitService: storeKit
        )

        let restored = await viewModel.restorePurchases()

        #expect(!restored)
        #expect(viewModel.notice == .restorePurchasesFailed)
        #expect(!viewModel.isRestoringPurchases)
    }
}

private enum FakePreferencesError: Error {
    case failed
}

// An actor supplies the async-ness, so the sync bodies need no `async`/`await`.
private actor FakeNotificationPreferences: NotificationPreferencesProviding {
    private var preferences: NotificationPreferences
    private let failOnSet: Bool
    private(set) var setCallCount = 0
    private(set) var lastSetKind: NotificationPreferenceKind?
    private(set) var lastSetValue: Bool?

    init(preferences: NotificationPreferences = NotificationPreferences(), failOnSet: Bool = false) {
        self.preferences = preferences
        self.failOnSet = failOnSet
    }

    func loadNotificationPreferences() -> NotificationPreferences {
        preferences
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled value: Bool) throws {
        setCallCount += 1
        if failOnSet {
            throw FakePreferencesError.failed
        }
        lastSetKind = kind
        lastSetValue = value
        switch kind {
        case .streakReminders:
            preferences.streakRemindersEnabled = value
        case .dailyChallenge:
            preferences.dailyChallengeEnabled = value
        case .partnerAnswered:
            preferences.partnerAnsweredEnabled = value
        case .messages:
            preferences.messagesEnabled = value
        case .widgetUpdates:
            preferences.widgetUpdatesEnabled = value
        case .memories:
            preferences.memoriesEnabled = value
        }
    }
}

private struct FakePushAuthorization: PushAuthorizationProviding {
    var denied = false

    func requestAuthorizationIfNeeded() -> Bool { true }

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
        startedOn: PairingStartDate?
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

@MainActor
private final class FakeSettingsStoreKit: PaeoniaStoreKitServicing {
    let products: [Product] = []
    private let restoreResult: Result<Bool, Error>
    private(set) var configuredUserID: String?
    private(set) var restoreCallCount = 0

    init(restoreResult: Result<Bool, Error>) {
        self.restoreResult = restoreResult
    }

    func configure(userID: String) {
        configuredUserID = userID
    }

    func loadProducts() async throws {}

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? {
        nil
    }

    func product(for productID: PaeoniaConsumableProductID) -> Product? {
        nil
    }

    func purchase(_ product: Product) async throws -> Bool {
        false
    }

    func restorePurchases() async throws -> Bool {
        restoreCallCount += 1
        return try restoreResult.get()
    }

    func redeemStreakRestore() async throws -> Int? {
        nil
    }

    func recoverPendingStreakRestores() async -> Int? {
        nil
    }
}
