import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum Notice: Equatable {
        case saveFailed
    }

    private let preferences: (any NotificationPreferencesProviding)?
    private let authorization: any PushAuthorizationProviding

    /// The widget drawing alert toggle. Defaults to the server default (on) until
    /// the real value loads, so the control never flickers off.
    private(set) var widgetAlertsEnabled = true
    private(set) var isLoaded = false
    /// True when the user has turned notifications off in iOS Settings, so the
    /// in-app toggle can explain why nothing arrives.
    private(set) var systemNotificationsDenied = false
    private(set) var notice: Notice?

    init(
        preferences: (any NotificationPreferencesProviding)? = NotificationPreferencesServiceFactory.makeDefault(),
        authorization: any PushAuthorizationProviding = PushAuthorizationService()
    ) {
        self.preferences = preferences
        self.authorization = authorization
    }

    func load() async {
        systemNotificationsDenied = await authorization.isDenied()

        guard let preferences else {
            isLoaded = true
            return
        }

        do {
            widgetAlertsEnabled = try await preferences.loadWidgetAlertsEnabled()
        } catch {
            // Keep the optimistic default visible; the next save still works.
        }
        isLoaded = true
    }

    func setWidgetAlertsEnabled(_ enabled: Bool) async {
        guard enabled != widgetAlertsEnabled else {
            return
        }

        let previous = widgetAlertsEnabled
        widgetAlertsEnabled = enabled

        guard let preferences else {
            return
        }

        do {
            try await preferences.setWidgetAlertsEnabled(enabled)
        } catch {
            widgetAlertsEnabled = previous
            notice = .saveFailed
        }
    }

    func dismissNotice() {
        notice = nil
    }
}
