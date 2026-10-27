import Foundation
import Testing
@testable import PaeoniaApp

struct DeliveredNotificationsLiveFeedTests {
    fileprivate actor NotificationCenterStub {
        var references: [DeliveredNotificationReference]

        init(_ references: [DeliveredNotificationReference]) {
            self.references = references
        }
    }

    private struct Transport: LiveQueryTransport {
        let obsolete: [String]
        var failure: URLError?

        func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
            AsyncThrowingStream { continuation in
                if let failure {
                    continuation.finish(throwing: failure)
                    return
                }
                if let data = try? JSONEncoder().encode(obsolete) {
                    continuation.yield(data)
                }
            }
        }
    }

    @Test
    func removesResolvedAlertsAndKeepsUnresolvedAlerts() async throws {
        let resolved = reference("resolved")
        let unread = reference("unread")
        let center = NotificationCenterStub([resolved, unread])
        let live = LiveQueryService(transport: Transport(obsolete: [try #require(resolved.notificationID)]))
        let feed = DeliveredNotificationsLiveFeed(center: center)
        let task = Task { await feed.run(session: SyncSession(userID: UUID(), activeCoupleID: UUID()), live: live) }
        await waitUntil { await center.notifications() == [unread] }
        task.cancel()
        await task.value
        #expect(await center.notifications() == [unread])
    }

    @Test
    func expiresDeliveredAlertsOfflineAtTheirDeadline() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let expired = reference("expired", expiresAt: now)
        let future = reference("future", expiresAt: now.addingTimeInterval(1))
        let center = NotificationCenterStub([expired, future])
        let feed = DeliveredNotificationsLiveFeed(center: center, now: { now })
        let live = LiveQueryService(transport: Transport(obsolete: [], failure: URLError(.notConnectedToInternet)))
        let task = Task { await feed.run(session: SyncSession(userID: UUID(), activeCoupleID: nil), live: live) }
        await waitUntil { await center.notifications() == [future] }
        task.cancel()
        await task.value
        #expect(await center.notifications() == [future])
    }

    @Test
    func staleServerResponseCannotRemoveANewerAlertWithTheSameCollapseIdentifier() async {
        let previous = reference("game:ludo")
        let newer = reference("game:ludo")
        let center = NotificationCenterStub([newer])
        await DeliveredNotifications.remove([previous], from: center)
        #expect(await center.notifications() == [newer])
    }

    private func reference(_ identifier: String, expiresAt: Date? = nil) -> DeliveredNotificationReference {
        DeliveredNotificationReference(
            identifier: identifier, notificationID: UUID().uuidString.lowercased(), expiresAt: expiresAt
        )
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Notification cleanup did not finish")
    }
}

extension DeliveredNotificationsLiveFeedTests.NotificationCenterStub: DeliveredNotificationCenter {
    func notifications() -> [DeliveredNotificationReference] { references }

    func remove(identifiers: [String]) {
        references.removeAll { identifiers.contains($0.identifier) }
    }
}
