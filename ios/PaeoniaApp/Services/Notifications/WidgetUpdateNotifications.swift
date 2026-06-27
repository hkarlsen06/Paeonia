import UserNotifications

/// Clears already-delivered partner widget-update alerts from Notification
/// Center once the user has seen the update in-app — opening the home (the
/// couple's shared surface) or the drawing screen — so stale alerts don't pile
/// up after the user has clearly already noticed the change.
enum WidgetUpdateNotifications {
    /// Removes every delivered widget-update alert. Matches on the same `type`
    /// the push and the notification service extension use, so unrelated
    /// notifications are left untouched.
    static func clearDelivered() async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered
            .filter { ($0.request.content.userInfo["type"] as? String) == "widget_updated" }
            .map { $0.request.identifier }

        guard !identifiers.isEmpty else {
            return
        }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        // The widget alert is the only badging notification, so clear the dot too.
        try? await center.setBadgeCount(0)
    }
}
