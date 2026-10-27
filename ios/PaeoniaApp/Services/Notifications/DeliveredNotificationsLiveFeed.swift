@preconcurrency import ConvexMobile
import Foundation
import UserNotifications

nonisolated struct DeliveredNotificationReference: Equatable, Sendable {
    let identifier: String
    let notificationID: String?
    let expiresAt: Date?

    init(identifier: String, notificationID: String?, expiresAt: Date?) {
        self.identifier = identifier
        self.notificationID = notificationID
        self.expiresAt = expiresAt
    }

    init(_ notification: UNNotification) {
        identifier = notification.request.identifier
        let info = notification.request.content.userInfo
        notificationID = (info["notification_id"] as? String).flatMap(UUID.init(uuidString:))?.uuidString.lowercased()
        expiresAt = (info["notification_expires_at"] as? String).flatMap {
            try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
    }
}

nonisolated protocol DeliveredNotificationCenter: Sendable {
    func notifications() async -> [DeliveredNotificationReference]
    func remove(identifiers: [String]) async
}

nonisolated struct SystemDeliveredNotificationCenter: DeliveredNotificationCenter {
    func notifications() async -> [DeliveredNotificationReference] {
        await UNUserNotificationCenter.current().deliveredNotifications().map(DeliveredNotificationReference.init)
    }

    func remove(identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Follows the server state of alerts still in Notification Center, including reads on another phone.
/// Rescans each minute for alerts delivered while suspended and for deadlines that pass while offline.
nonisolated struct DeliveredNotificationsLiveFeed: LiveFeed {
    let name = "delivered-notifications"
    var center: any DeliveredNotificationCenter = SystemDeliveredNotificationCenter()
    var now: @Sendable () -> Date = { Date() }
    var sleep: @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(60)) }

    func run(session: SyncSession, live: LiveQueryService) async {
        while !Task.isCancelled {
            let instant = now()
            let references = await center.notifications()
            await DeliveredNotifications.remove(
                references.filter { $0.expiresAt.map { $0 <= instant } ?? false }, from: center
            )
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                let ids = Array(Set(references.compactMap(\.notificationID)))
                for start in stride(from: 0, to: ids.count, by: 100) {
                    let batch = Array(ids[start..<min(start + 100, ids.count)])
                    group.addTask {
                        let results = live.subscribe(
                            "notificationState:get_obsolete_notifications",
                            args: [
                                "p_notification_ids": batch.map { $0 as ConvexEncodable? },
                                "p_now": instant.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
                            ],
                            as: [String].self
                        )
                        for await result in results {
                            guard !Task.isCancelled else { return }
                            guard case let .value(obsolete) = result else { continue }
                            let obsoleteIDs = Set(obsolete)
                            await DeliveredNotifications.remove(
                                references.filter { $0.notificationID.map(obsoleteIDs.contains) ?? false }, from: center
                            )
                        }
                    }
                }
                try? await sleep()
                group.cancelAll()
            }
        }
    }
}

extension DeliveredNotifications {
    static func remove(
        _ references: [DeliveredNotificationReference], from center: any DeliveredNotificationCenter
    ) async {
        // A new alert may have replaced one under the same collapse identifier during the server check.
        let current = await center.notifications()
        let identifiers = current.filter(references.contains).map(\.identifier)
        guard !Task.isCancelled, !identifiers.isEmpty else { return }
        await center.remove(identifiers: identifiers)
    }

    /// A foreground activation may precede the next feed rescan.
    static func reconcile() async {
        let center = SystemDeliveredNotificationCenter()
        let instant = Date()
        let references = await center.notifications()
        await DeliveredNotifications.remove(
            references.filter { $0.expiresAt.map { $0 <= instant } ?? false }, from: center
        )
        let ids = Array(Set(references.compactMap(\.notificationID)))
        struct Arguments: Encodable {
            let notificationIDs: [String]
            let now: Date

            enum CodingKeys: String, CodingKey {
                case notificationIDs = "p_notification_ids"
                case now = "p_now"
            }
        }
        for start in stride(from: 0, to: ids.count, by: 100) {
            guard !Task.isCancelled else { return }
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            guard let obsolete: [String] = try? await PaeoniaConvexClientProvider.shared.client().query(
                "notificationState:get_obsolete_notifications",
                args: Arguments(notificationIDs: batch, now: instant)
            ) else { continue }
            let obsoleteIDs = Set(obsolete)
            await DeliveredNotifications.remove(
                references.filter { $0.notificationID.map(obsoleteIDs.contains) ?? false }, from: center
            )
        }
    }
}
