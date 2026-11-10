import Foundation
import Observation

/// A request to show an in-app banner for a notification that arrived while
/// the app was open, in place of the suppressed system banner.
struct PaeoniaForegroundNotice: Equatable, Identifiable {
    let id = UUID()
    let title: String?
    let message: String
    let deepLink: PaeoniaDeepLink?
    let showsPartnerAvatar: Bool
    var messageID: UUID?
}

/// Bridges a tapped notification (handled in the UIKit app delegate) to the
/// SwiftUI deep-link state. The delegate cannot reach the app's `@State`
/// directly, so it routes through this shared, observable relay. It also relays
/// a foreground notice so a partner's update shows as an in-app banner instead
/// of the system notification while the app is open.
@Observable
final class PaeoniaNotificationRouter {
    static let shared = PaeoniaNotificationRouter()

    private(set) var pendingDeepLink: PaeoniaDeepLink?
    private(set) var pendingForegroundNotice: PaeoniaForegroundNotice?

    private init() {}

    func route(_ deepLink: PaeoniaDeepLink) {
        pendingDeepLink = deepLink
    }

    func consumePendingDeepLink() {
        pendingDeepLink = nil
    }

    func presentForegroundNotice(
        title: String?, message: String, deepLink: PaeoniaDeepLink?, showsPartnerAvatar: Bool, messageID: UUID? = nil
    ) {
        pendingForegroundNotice = PaeoniaForegroundNotice(
            title: title, message: message, deepLink: deepLink,
            showsPartnerAvatar: showsPartnerAvatar, messageID: messageID
        )
    }

    func consumeForegroundNotice() {
        pendingForegroundNotice = nil
    }
}
