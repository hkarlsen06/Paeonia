import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
struct SettingsViewModelTests {
    @Test func loadReadsWidgetAlertsAndDeniedStatus() async {
        let preferences = SettingsFakeNotificationPreferences(preferences: NotificationPreferences(
            streakRemindersEnabled: false,
            dailyChallengeEnabled: true,
            partnerAnsweredEnabled: false,
            messagesEnabled: false,
            widgetUpdatesEnabled: false,
            memoriesEnabled: false
        ))
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: SettingsFakePushAuthorization(denied: true)
        )

        await viewModel.loadNotificationSettings()

        #expect(viewModel.isNotificationSettingsLoaded)
        #expect(viewModel.isEnabled(.streakReminders) == false)
        #expect(viewModel.isEnabled(.dailyChallenge))
        #expect(viewModel.isEnabled(.partnerAnswered) == false)
        #expect(viewModel.isEnabled(.messages) == false)
        #expect(viewModel.isEnabled(.widgetUpdates) == false)
        #expect(viewModel.isEnabled(.memories) == false)
        #expect(viewModel.systemNotificationPermission == .denied)
    }

    @Test func togglePersistsThroughService() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: SettingsFakePushAuthorization()
        )
        await viewModel.loadNotificationSettings()

        await viewModel.setNotificationPreference(.widgetUpdates, enabled: false)

        #expect(viewModel.isEnabled(.widgetUpdates) == false)
        #expect(await preferences.lastSetKind == .widgetUpdates)
        #expect(await preferences.lastSetValue == false)
        #expect(viewModel.notice == nil)
    }

    @Test func togglePersistsPartnerAnswerPreference() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: SettingsFakePushAuthorization()
        )
        await viewModel.loadNotificationSettings()

        await viewModel.setNotificationPreference(.partnerAnswered, enabled: false)

        #expect(viewModel.isEnabled(.partnerAnswered) == false)
        #expect(await preferences.lastSetKind == .partnerAnswered)
        #expect(await preferences.lastSetValue == false)
    }

    @Test func togglePersistsMemoryPreference() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: SettingsFakePushAuthorization()
        )
        await viewModel.loadNotificationSettings()

        await viewModel.setNotificationPreference(.memories, enabled: false)

        #expect(viewModel.isEnabled(.memories) == false)
        #expect(await preferences.lastSetKind == .memories)
        #expect(await preferences.lastSetValue == false)
    }

    @Test func togglePersistsMessagePreference() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: SettingsFakePushAuthorization()
        )
        await viewModel.loadNotificationSettings()

        await viewModel.setNotificationPreference(.messages, enabled: false)

        #expect(viewModel.isEnabled(.messages) == false)
        #expect(await preferences.lastSetKind == .messages)
        #expect(await preferences.lastSetValue == false)
    }

    @Test func failedSaveRevertsAndShowsNotice() async {
        let preferences = SettingsFakeNotificationPreferences(failOnSet: true)
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: SettingsFakePushAuthorization()
        )
        await viewModel.loadNotificationSettings()

        await viewModel.setNotificationPreference(.streakReminders, enabled: false)

        // The optimistic flip is rolled back and the failure surfaces.
        #expect(viewModel.isEnabled(.streakReminders) == true)
        #expect(viewModel.notice == .saveFailed)
    }

    @Test func unchangedValueDoesNotWrite() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            authorization: SettingsFakePushAuthorization()
        )
        await viewModel.loadNotificationSettings()

        await viewModel.setNotificationPreference(.dailyChallenge, enabled: true)

        #expect(await preferences.setCallCount == 0)
    }

    @Test func leaveRelationshipSucceeds() async {
        let pairing = SettingsFakePairingService(leaveResult: .success(true))
        let viewModel = SettingsViewModel(
            preferences: SettingsFakeNotificationPreferences(),
            authorization: SettingsFakePushAuthorization(),
            pairingService: pairing,
            operationProvider: SettingsFakeOperationProvider()
        )

        let didLeave = await viewModel.leaveRelationship()

        #expect(didLeave)
        #expect(viewModel.notice == nil)
        #expect(viewModel.isLeavingRelationship == false)
        #expect(await pairing.leaveCallCount == 1)
    }

    @Test func leaveRelationshipFailureSurfacesNotice() async {
        let pairing = SettingsFakePairingService(leaveResult: .failure(SettingsFakePreferencesError.failed))
        let viewModel = SettingsViewModel(
            preferences: SettingsFakeNotificationPreferences(),
            authorization: SettingsFakePushAuthorization(),
            pairingService: pairing,
            operationProvider: SettingsFakeOperationProvider()
        )

        let didLeave = await viewModel.leaveRelationship()

        #expect(didLeave == false)
        #expect(viewModel.notice == .leaveFailed)
        #expect(viewModel.isLeavingRelationship == false)
    }

    @Test func restorePurchasesConfiguresUserAndSurfacesSuccess() async {
        let storeKit = SettingsFakeStoreKit(restoreResult: .success(true))
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: SettingsFakePushAuthorization(),
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
        let storeKit = SettingsFakeStoreKit(restoreResult: .success(false))
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: SettingsFakePushAuthorization(),
            userID: "user-123",
            storeKitService: storeKit
        )

        let restored = await viewModel.restorePurchases()

        #expect(!restored)
        #expect(viewModel.notice == .noPurchasesToRestore)
    }

    @Test func restorePurchasesSurfacesFailure() async {
        let storeKit = SettingsFakeStoreKit(
            restoreResult: .failure(PaeoniaPurchaseError.restoreFailed)
        )
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: SettingsFakePushAuthorization(),
            userID: "user-123",
            storeKitService: storeKit
        )

        let restored = await viewModel.restorePurchases()

        #expect(!restored)
        #expect(viewModel.notice == .restorePurchasesFailed(.other))
        #expect(!viewModel.isRestoringPurchases)
    }
}

extension SettingsViewModelTests {
    @Test func liveValuesUpdateToggles() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
        let observing = Task { await viewModel.observeNotificationSettings() }

        await preferences.emit(NotificationPreferences(messagesEnabled: false))
        await waitUntil { viewModel.isEnabled(.messages) == false }

        #expect(viewModel.isEnabled(.messages) == false)
        #expect(viewModel.isEnabled(.memories))
        observing.cancel()
    }

    @Test func staleLiveValueDoesNotRevertToggleWithSaveInFlight() async {
        let preferences = SettingsFakeNotificationPreferences(holdSets: true)
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
        let observing = Task { await viewModel.observeNotificationSettings() }

        let saving = Task { await viewModel.setNotificationPreference(.messages, enabled: false) }
        await waitUntil { await preferences.heldSetCount == 1 }

        // The server still reports the old messages value and a new memories value.
        await preferences.emit(NotificationPreferences(memoriesEnabled: false))
        await waitUntil { viewModel.isEnabled(.memories) == false }

        #expect(viewModel.isEnabled(.messages) == false)
        #expect(viewModel.isEnabled(.memories) == false)

        await preferences.releaseSets()
        await saving.value

        // Later live values apply again once the save finished.
        await preferences.emit(NotificationPreferences(messagesEnabled: true, memoriesEnabled: false))
        await waitUntil { viewModel.isEnabled(.messages) }
        #expect(viewModel.isEnabled(.messages))
        observing.cancel()
    }
}

// MARK: - Rapid toggles and failures

extension SettingsViewModelTests {
    /// Three quick taps used to start three overlapping requests that could
    /// reach the server in any order. Now one request runs per switch and the
    /// newest value follows it, so the server always ends on the last tap.
    @Test func rapidTogglesSendOneRequestAtATimeAndEndOnLastTap() async {
        let preferences = SettingsFakeNotificationPreferences(holdSets: true)
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
        await viewModel.loadNotificationSettings()

        let firstTap = Task { await viewModel.setNotificationPreference(.messages, enabled: false) }
        await waitUntil { await preferences.heldSetCount == 1 }

        await viewModel.setNotificationPreference(.messages, enabled: true)
        await viewModel.setNotificationPreference(.messages, enabled: false)
        await viewModel.setNotificationPreference(.messages, enabled: true)

        // Still only the first request is in flight.
        #expect(await preferences.setCallCount == 1)
        #expect(viewModel.isEnabled(.messages))

        await preferences.releaseNextSet()
        await waitUntil { await preferences.setCallCount == 2 }
        await waitUntil { await preferences.heldSetCount == 1 }
        await preferences.releaseNextSet()
        await firstTap.value

        #expect(await preferences.sentValues == [false, true])
        #expect(viewModel.isEnabled(.messages))
        #expect(viewModel.notice == nil)
    }

    @Test func tapsThatEndOnTheSavedValueSendNothingMore() async {
        let preferences = SettingsFakeNotificationPreferences(holdSets: true)
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
        await viewModel.loadNotificationSettings()

        let firstTap = Task { await viewModel.setNotificationPreference(.memories, enabled: false) }
        await waitUntil { await preferences.heldSetCount == 1 }
        await viewModel.setNotificationPreference(.memories, enabled: true)
        await viewModel.setNotificationPreference(.memories, enabled: false)

        await preferences.releaseNextSet()
        await firstTap.value

        #expect(await preferences.sentValues == [false])
        #expect(viewModel.isEnabled(.memories) == false)
    }

    /// A failed save goes back to what the server last said, not to whatever the
    /// switch showed before the tap.
    @Test func failedSaveFallsBackToLatestServerValue() async {
        let preferences = SettingsFakeNotificationPreferences(holdSets: true)
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
        let observing = Task { await viewModel.observeNotificationSettings() }
        await viewModel.loadNotificationSettings()

        let tap = Task { await viewModel.setNotificationPreference(.dailyChallenge, enabled: false) }
        await waitUntil { await preferences.heldSetCount == 1 }

        // Another device turned it off meanwhile; this save then fails.
        await preferences.emit(NotificationPreferences(dailyChallengeEnabled: false))
        await preferences.setFailing(true)
        await viewModel.setNotificationPreference(.dailyChallenge, enabled: true)
        await waitUntil { await preferences.heldSetCount == 1 }
        await preferences.releaseNextSet()
        await tap.value

        #expect(viewModel.isEnabled(.dailyChallenge) == false)
        #expect(viewModel.notice == .saveFailed)
        observing.cancel()
    }

    /// After "Not now" on the app's primer, iOS has never asked. The switches
    /// cannot help then, so the screen offers the real iOS prompt.
    @Test func notAskedPermissionCanBeRequestedFromSettings() async {
        let permission = SettingsFakeSystemPermission(status: .notAsked, answer: .allowed)
        let viewModel = SettingsViewModel(preferences: nil, authorization: permission)

        await viewModel.loadNotificationSettings()
        #expect(viewModel.systemNotificationPermission == .notAsked)

        await viewModel.requestSystemNotificationPermission()

        #expect(await permission.requestCount == 1)
        #expect(viewModel.systemNotificationPermission == .allowed)
        #expect(!viewModel.isRequestingSystemPermission)
    }

    @Test func sayingNoToThePromptLeadsToTheSettingsPath() async {
        let permission = SettingsFakeSystemPermission(status: .notAsked, answer: .denied)
        let viewModel = SettingsViewModel(preferences: nil, authorization: permission)
        await viewModel.loadNotificationSettings()

        await viewModel.requestSystemNotificationPermission()

        #expect(viewModel.systemNotificationPermission == .denied)
    }

    @Test func deniedPermissionIsNotRequestedAgain() async {
        let permission = SettingsFakeSystemPermission(status: .denied, answer: .allowed)
        let viewModel = SettingsViewModel(preferences: nil, authorization: permission)
        await viewModel.loadNotificationSettings()

        await viewModel.requestSystemNotificationPermission()

        #expect(await permission.requestCount == 0)
        #expect(viewModel.systemNotificationPermission == .denied)
    }

    /// Reopening the screen starts a fresh read. If a save finishes while that
    /// read is slow, the read's older value must not put the switch back.
    @Test func slowReadDoesNotUndoASaveThatFinishedFirst() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
        await viewModel.loadNotificationSettings()

        await preferences.setLoadHolding(true)
        let reopening = Task { await viewModel.loadNotificationSettings() }
        await waitUntil { await preferences.heldLoadCount == 1 }

        await viewModel.setNotificationPreference(.messages, enabled: false)
        await preferences.releaseLoads()
        await reopening.value

        #expect(viewModel.isEnabled(.messages) == false)
    }

    @Test func failedLoadKeepsSwitchesDisabledUntilLiveValuesArrive() async {
        let preferences = SettingsFakeNotificationPreferences(failOnLoad: true)
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())

        await viewModel.loadNotificationSettings()

        #expect(viewModel.notificationLoadState == .failed(.other))
        #expect(!viewModel.isNotificationSettingsLoaded)

        let observing = Task { await viewModel.observeNotificationSettings() }
        await preferences.emit(NotificationPreferences(streakRemindersEnabled: false))
        await waitUntil { viewModel.isNotificationSettingsLoaded }

        #expect(viewModel.notificationLoadState == .loaded)
        #expect(viewModel.isEnabled(.streakReminders) == false)
        observing.cancel()
    }

    @Test func failedRefreshKeepsLoadedValues() async {
        let preferences = SettingsFakeNotificationPreferences(
            preferences: NotificationPreferences(memoriesEnabled: false)
        )
        let viewModel = SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
        await viewModel.loadNotificationSettings()

        await preferences.setLoadFailing(true)
        await viewModel.loadNotificationSettings()

        #expect(viewModel.notificationLoadState == .loaded)
        #expect(viewModel.isEnabled(.memories) == false)
    }

    @Test func restoreCancelledByUserShowsNothing() async {
        let storeKit = SettingsFakeStoreKit(restoreResult: .failure(PaeoniaPurchaseError.cancelled))
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: SettingsFakePushAuthorization(),
            userID: "user-123",
            storeKitService: storeKit
        )

        let restored = await viewModel.restorePurchases()

        #expect(!restored)
        #expect(viewModel.notice == nil)
        #expect(!viewModel.isRestoringPurchases)
    }

    @Test func restoreOfAnotherAccountsSubscriptionSaysSo() async {
        let storeKit = SettingsFakeStoreKit(
            restoreResult: .failure(PaeoniaPurchaseError.purchaseLinkedToAnotherAccount)
        )
        let viewModel = SettingsViewModel(
            preferences: nil,
            authorization: SettingsFakePushAuthorization(),
            userID: "user-123",
            storeKitService: storeKit
        )

        _ = await viewModel.restorePurchases()

        #expect(viewModel.notice == .purchaseLinkedToAnotherAccount)
    }
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 where !(await condition()) {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
