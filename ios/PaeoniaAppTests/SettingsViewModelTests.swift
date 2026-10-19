import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
struct SettingsViewModelTests {
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
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 where !(await condition()) {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
