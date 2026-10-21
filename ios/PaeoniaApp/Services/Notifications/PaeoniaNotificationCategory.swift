import UserNotifications

/// The categories the server puts in `aps.category` (`NOTIFICATION_CATEGORY` in
/// `backend/convex/lib/apns.ts`). Keep the two lists the same.
///
/// A category does three things:
/// - With Show Previews set to Never or When Unlocked, iOS shows the category's placeholder
///   line instead of only "Notification".
/// - A person who chose "Show details on the lock screen" gets the `detailSuffix` twin of
///   the category. It also keeps the title (who it is from and what they did) on the
///   locked screen. Nothing the partner wrote is ever in the title.
/// - It holds the buttons under the notification (`PaeoniaNotificationActionID`).
nonisolated enum PaeoniaNotificationCategory: String, CaseIterable {
    case message
    case drawing
    case answer
    case game
    case partner
    case reminder

    /// Added to the id of a category for a person who chose to see details on the lock screen.
    /// Mirrors `DESCRIPTIVE_CATEGORY_SUFFIX` in `backend/convex/lib/apns.ts`.
    static let detailSuffix = ".detail"

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

    /// A message can be answered with a typed reply or a heart, and a drawing with a heart.
    /// An answer, a memory or a story gets no heart here, because those are worth opening
    /// first. Both buttons need an unlocked phone, so a lock screen alone cannot send as the person.
    private var actions: [UNNotificationAction] {
        switch self {
        case .message: [Self.replyAction, Self.heartAction]
        case .drawing: [Self.heartAction]
        case .answer, .game, .partner, .reminder: []
        }
    }

    private static var replyAction: UNNotificationAction {
        UNTextInputNotificationAction(
            identifier: PaeoniaNotificationActionID.reply,
            title: String(localized: .notificationsActionReply),
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
            textInputButtonTitle: String(localized: .notificationsActionReplySend),
            textInputPlaceholder: String(localized: .notificationsActionReplyPlaceholder)
        )
    }

    private static var heartAction: UNNotificationAction {
        UNNotificationAction(
            identifier: PaeoniaNotificationActionID.heart,
            title: String(localized: .notificationsActionHeart),
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "heart")
        )
    }

    private func category(showsDetails: Bool) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: showsDetails ? rawValue + Self.detailSuffix : rawValue,
            actions: actions,
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: hiddenPreviewsPlaceholder),
            options: showsDetails ? [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle] : []
        )
    }

    /// Call at launch, before any alert can arrive.
    static func registerAll() {
        let categories = allCases.flatMap { category in
            [category.category(showsDetails: false), category.category(showsDetails: true)]
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }
}
