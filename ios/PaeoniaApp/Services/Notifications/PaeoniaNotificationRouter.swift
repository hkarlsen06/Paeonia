import Foundation
import Observation

/// A request to show an in-app banner for a notification that arrived while
/// the app was open, in place of the suppressed system banner.
nonisolated struct PaeoniaForegroundNotice: Equatable, Identifiable, Sendable {
    let id = UUID()
    let title: String?
    let message: String
    let deepLink: PaeoniaDeepLink?
    /// It is about the partner, so it shows their picture.
    let showsPartnerAvatar: Bool
    /// The partner did it, such as sending a letter, so it can show in their avatar. A reminder about
    /// the partner's birthday shows their picture but is not their doing.
    var isPartnersDoing = false
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
    /// What the paired app has in front of the person. `MainTabView` sets it.
    @ObservationIgnored
    var screen = ForegroundScreen.elsewhere
    /// Takes a notice from the partner before it becomes a banner, and says whether it did. The
    /// paired app's partner avatar sets it while it is mounted. The owner lets one that goes away
    /// remove only its own, not one that mounted after it.
    @ObservationIgnored
    private var partnerNoticeTaker: (owner: ObjectIdentifier, take: (PaeoniaForegroundNotice) -> Bool)?

    private init() {}

    func route(_ deepLink: PaeoniaDeepLink) {
        pendingDeepLink = deepLink
    }

    func consumePendingDeepLink() {
        pendingDeepLink = nil
    }

    /// Shows `notice` in the partner's picture or as a banner, unless the screen in front already
    /// shows where it leads.
    func presentForegroundNotice(_ notice: PaeoniaForegroundNotice) {
        if let deepLink = notice.deepLink, screen.showsLive(deepLink) { return }
        if notice.isPartnersDoing, partnerNoticeTaker?.take(notice) == true { return }
        pendingForegroundNotice = notice
    }

    func takePartnerNotices(for owner: AnyObject, with take: @escaping (PaeoniaForegroundNotice) -> Bool) {
        partnerNoticeTaker = (ObjectIdentifier(owner), take)
    }

    func stopTakingPartnerNotices(for owner: AnyObject) {
        if partnerNoticeTaker?.owner == ObjectIdentifier(owner) { partnerNoticeTaker = nil }
    }

    func consumeForegroundNotice() {
        pendingForegroundNotice = nil
    }
}
