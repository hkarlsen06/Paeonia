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
