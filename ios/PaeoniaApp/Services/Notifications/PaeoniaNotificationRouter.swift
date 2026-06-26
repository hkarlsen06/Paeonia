import Observation

/// Bridges a tapped notification (handled in the UIKit app delegate) to the
/// SwiftUI deep-link state. The delegate cannot reach the app's `@State`
/// directly, so it routes through this shared, observable relay; `PaeoniaApp`
/// observes it and feeds the existing widget deep-link path.
@MainActor
@Observable
final class PaeoniaNotificationRouter {
    static let shared = PaeoniaNotificationRouter()

    private(set) var pendingWidgetDeepLink: PaeoniaWidgetDeepLink?

    private init() {}

    func route(_ deepLink: PaeoniaWidgetDeepLink) {
        pendingWidgetDeepLink = deepLink
    }

    func consumePendingWidgetDeepLink() {
        pendingWidgetDeepLink = nil
    }
}
