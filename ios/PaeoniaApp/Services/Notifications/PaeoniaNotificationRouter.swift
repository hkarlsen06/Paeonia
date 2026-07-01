import Foundation
import Observation

/// A request to show an in-app top banner for a notification that arrived while
/// the app was open, in place of the suppressed system banner.
struct PaeoniaForegroundNotice: Equatable, Identifiable {
    let id = UUID()
    let title: String?
    let message: String
}

/// Bridges a tapped notification (handled in the UIKit app delegate) to the
/// SwiftUI deep-link state. The delegate cannot reach the app's `@State`
/// directly, so it routes through this shared, observable relay. It also relays
/// a foreground notice so a partner's update shows as an in-app banner instead
/// of the system notification while the app is open.
@MainActor
@Observable
final class PaeoniaNotificationRouter {
    static let shared = PaeoniaNotificationRouter()

    private(set) var pendingDeepLink: PaeoniaDeepLink?
    private(set) var pendingForegroundNotice: PaeoniaForegroundNotice?

    private init() {}

    func route(_ deepLink: PaeoniaDeepLink) {
        pendingDeepLink = deepLink
    }

    func route(_ widgetDeepLink: PaeoniaWidgetDeepLink) {
        if let deepLink = PaeoniaDeepLink(widgetDeepLink) {
            route(deepLink)
        }
    }

    func routeNotification(userInfo: [AnyHashable: Any]) {
        guard let deepLink = PaeoniaDeepLink(notificationUserInfo: userInfo) else {
            return
        }

        route(deepLink)
    }

    func consumePendingDeepLink() {
        pendingDeepLink = nil
    }

    func presentForegroundNotice(title: String?, message: String) {
        pendingForegroundNotice = PaeoniaForegroundNotice(title: title, message: message)
    }

    func consumeForegroundNotice() {
        pendingForegroundNotice = nil
    }
}
