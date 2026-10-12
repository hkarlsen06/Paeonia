import Foundation
import StoreKit
@testable import PaeoniaApp

// Test doubles for SettingsViewModelTests. Fakes implement only what the Me tab
// uses, so unused protocol requirements trap and sync bodies need no await.
// swiftlint:disable async_without_await unavailable_function

enum SettingsFakePreferencesError: Error {
    case failed
}

// An actor supplies the async-ness, so the sync bodies need no `async`/`await`.
actor SettingsFakeNotificationPreferences: NotificationPreferencesProviding {
    private var preferences: NotificationPreferences
    private var failOnSet: Bool
    private var failOnLoad: Bool
    private let holdSets: Bool
    private var heldSets = [CheckedContinuation<Void, Never>]()
    private var holdsLoads = false
    private var heldLoads = [CheckedContinuation<Void, Never>]()
    private let updates = AsyncStream<NotificationPreferences>.makeStream()
    private(set) var setCallCount = 0
    private(set) var lastSetKind: NotificationPreferenceKind?
    private(set) var lastSetValue: Bool?
    /// Every value that reached the "server", in arrival order.
    private(set) var sentValues = [Bool]()

    init(
        preferences: NotificationPreferences = NotificationPreferences(),
        failOnSet: Bool = false,
        failOnLoad: Bool = false,
        holdSets: Bool = false
    ) {
        self.preferences = preferences
        self.failOnSet = failOnSet
        self.failOnLoad = failOnLoad
        self.holdSets = holdSets
    }

    func setFailing(_ failing: Bool) {
        failOnSet = failing
    }

    func setLoadFailing(_ failing: Bool) {
        failOnLoad = failing
    }

    func setLoadHolding(_ holding: Bool) {
        holdsLoads = holding
    }

    var heldLoadCount: Int {
        heldLoads.count
    }

    func releaseLoads() {
        heldLoads.forEach { $0.resume() }
        heldLoads = []
    }

    func releaseNextSet() {
        guard !heldSets.isEmpty else {
            return
        }
        heldSets.removeFirst().resume()
    }

    nonisolated func notificationPreferenceUpdates() -> AsyncStream<NotificationPreferences> {
        updates.stream
    }

    func emit(_ value: NotificationPreferences) {
        updates.continuation.yield(value)
    }

    var heldSetCount: Int {
        heldSets.count
    }

    func releaseSets() {
        heldSets.forEach { $0.resume() }
        heldSets = []
    }

    /// Returns the values as they were when the read started, like a real
    /// request that is slow to come back.
    func loadNotificationPreferences() async throws -> NotificationPreferences {
        let snapshot = preferences
        if holdsLoads {
            await withCheckedContinuation { heldLoads.append($0) }
        }
        if failOnLoad {
            throw SettingsFakePreferencesError.failed
        }
        return snapshot
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled value: Bool) async throws {
        setCallCount += 1
        if holdSets {
            await withCheckedContinuation { heldSets.append($0) }
        }
        if failOnSet {
            throw SettingsFakePreferencesError.failed
        }
        lastSetKind = kind
        lastSetValue = value
        sentValues.append(value)
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
        case .games:
            preferences.gamesEnabled = value
        }
    }
}

struct SettingsFakePushAuthorization: PushAuthorizationProviding {
    var denied = false

    func requestAuthorizationIfNeeded() -> Bool { true }

    func isDenied() -> Bool {
        denied
    }
}

/// A pairing service whose only exercised method is `leaveRelationship`; the rest
/// of the protocol is unused by the You-tab flow.
actor SettingsFakePairingService: PairingServicing {
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
final class SettingsFakeOperationProvider: PairingClientOperationProviding {
    func makeOperation() -> PairingClientOperation {
        SyncClientOperation(clientID: UUID(), clientSequence: 1)
    }
}

@MainActor
final class SettingsFakeStoreKit: PaeoniaStoreKitServicing {
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
/// The iOS notification permission. Asking flips it to the configured answer.
actor SettingsFakeSystemPermission: PushAuthorizationProviding {
    private var status: SettingsViewModel.SystemNotificationPermission
    private let answer: SettingsViewModel.SystemNotificationPermission
    private(set) var requestCount = 0

    init(
        status: SettingsViewModel.SystemNotificationPermission,
        answer: SettingsViewModel.SystemNotificationPermission
    ) {
        self.status = status
        self.answer = answer
    }

    func isNotDetermined() -> Bool {
        status == .notAsked
    }

    func isDenied() -> Bool {
        status == .denied
    }

    func requestAuthorizationIfNeeded() -> Bool {
        guard status == .notAsked else {
            return true
        }
        requestCount += 1
        status = answer
        return true
    }
}
// swiftlint:enable async_without_await unavailable_function
