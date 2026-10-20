import UserNotifications

/// The categories the server puts in `aps.category` (`NOTIFICATION_CATEGORY` in
/// `backend/convex/lib/apns.ts`). Keep the two lists the same. With Show Previews
/// set to Never, iOS shows a category's placeholder line instead of only
/// "Notification".
nonisolated enum PaeoniaNotificationCategory: String, CaseIterable {
    case message
    case drawing
    case answer
    case game
    case partner
    case reminder

    private var hiddenPreviewsPlaceholder: LocalizedStringResource {
        switch self {
        case .message: .notificationsHiddenPreviewMessage
        case .drawing: .notificationsHiddenPreviewDrawing
        case .answer: .notificationsHiddenPreviewAnswer
        case .game: .notificationsHiddenPreviewGame
        case .partner: .notificationsHiddenPreviewPartner
        case .reminder: .notificationsHiddenPreviewReminder
        }
    }

    /// Call at launch, before any alert can arrive.
    static func registerAll() {
        let categories = allCases.map { category in
            UNNotificationCategory(
                identifier: category.rawValue,
                actions: [],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: String(localized: category.hiddenPreviewsPlaceholder),
                options: []
            )
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }
}
