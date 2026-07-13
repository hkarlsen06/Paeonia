import Foundation
import Testing
@testable import PaeoniaApp

struct PaeoniaWidgetDeepLinkTests {
    @Test func drawingURLUsesWidgetDrawingRoute() {
        let url = PaeoniaWidgetDeepLink.drawingURL

        #expect(url.absoluteString == "paeonia://widget/drawing")
        #expect(PaeoniaWidgetDeepLink(url) == .drawing)
        #expect(PaeoniaWidgetDeepLink.handles(url))
        #expect(PaeoniaDeepLink(url) == .widgetDrawing)
    }

    @Test func rejectsNonWidgetURLs() throws {
        let joinURL = try #require(URL(string: "https://paeonia.no/join/01ABCD"))
        let authURL = try #require(URL(string: "paeonia://auth/callback"))
        let widgetRootURL = try #require(URL(string: "paeonia://widget"))

        #expect(!PaeoniaWidgetDeepLink.handles(joinURL))
        #expect(!PaeoniaWidgetDeepLink.handles(authURL))
        #expect(!PaeoniaWidgetDeepLink.handles(widgetRootURL))
        #expect(!PaeoniaDeepLink.handles(joinURL))
        #expect(!PaeoniaDeepLink.handles(authURL))
        #expect(!PaeoniaDeepLink.handles(widgetRootURL))
    }
}

struct PaeoniaDeepLinkTests {
    @Test func parsesDailyRevealURL() throws {
        let instanceID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleDayID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let url = PaeoniaDeepLink.dailyRevealURL(instanceID: instanceID, coupleDayID: coupleDayID)

        #expect(url.absoluteString == "paeonia://daily/reveal?instanceId=11111111-1111-1111-1111-111111111111&coupleDayId=22222222-2222-2222-2222-222222222222")
        #expect(PaeoniaDeepLink(url) == .dailyReveal(instanceID: instanceID, coupleDayID: coupleDayID))
    }

    @Test func parsesDailyTodayURL() throws {
        let coupleDayID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let url = PaeoniaDeepLink.dailyTodayURL(coupleDayID: coupleDayID)

        #expect(url.absoluteString == "paeonia://daily/today?coupleDayId=22222222-2222-2222-2222-222222222222")
        #expect(PaeoniaDeepLink(url) == .dailyToday(coupleDayID: coupleDayID))
    }

    @Test func parsesStreakURL() {
        let url = PaeoniaDeepLink.streakURL

        #expect(url.absoluteString == "paeonia://streak")
        #expect(PaeoniaDeepLink(url) == .streak)
    }

    @Test func parsesSubscriptionURL() {
        let url = PaeoniaDeepLink.subscriptionURL

        #expect(url.absoluteString == "paeonia://settings/subscription")
        #expect(PaeoniaDeepLink(url) == .subscription)
    }

    @Test func notificationPayloadPrefersCanonicalDeeplink() throws {
        let instanceID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleDayID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let userInfo: [AnyHashable: Any] = [
            "type": "partner_answered",
            "deeplink": "paeonia://daily/reveal?instanceId=\(instanceID.uuidString)&coupleDayId=\(coupleDayID.uuidString)",
        ]

        #expect(PaeoniaDeepLink(notificationUserInfo: userInfo) == .dailyReveal(instanceID: instanceID, coupleDayID: coupleDayID))
    }

    @Test func notificationPayloadFallsBackFromTypeAndIDs() throws {
        let instanceID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleDayID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let userInfo: [AnyHashable: Any] = [
            "type": "partner_answered",
            "instance_id": instanceID.uuidString,
            "couple_day_id": coupleDayID.uuidString,
        ]

        #expect(PaeoniaDeepLink(notificationUserInfo: userInfo) == .dailyReveal(instanceID: instanceID, coupleDayID: coupleDayID))
    }

    @Test func notificationPayloadMapsKnownTypes() {
        #expect(PaeoniaDeepLink(notificationUserInfo: ["type": "widget_updated"]) == .widgetDrawing)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["type": "daily_challenge_completed"]) == .dailyToday(coupleDayID: nil))
        #expect(PaeoniaDeepLink(notificationUserInfo: ["type": "streak_reminder"]) == .streak)
        #expect(
            PaeoniaDeepLink(notificationUserInfo: ["type": "subscription_trial_reminder"])
                == .subscription
        )
    }

    @Test func notificationPayloadUsesKnownTypeBeforeConflictingDeeplink() {
        let userInfo: [AnyHashable: Any] = [
            "type": "streak_reminder",
            "deeplink": "paeonia://daily/today?coupleDayId=22222222-2222-2222-2222-222222222222",
        ]

        #expect(PaeoniaDeepLink(notificationUserInfo: userInfo) == .streak)
    }

    @Test func notificationPayloadFallsBackToRouteMetadata() {
        #expect(PaeoniaDeepLink(notificationUserInfo: ["route": "widget"]) == .widgetDrawing)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["route": "streak"]) == .streak)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["route": "subscription"]) == .subscription)
    }

    @Test func notificationThreadIdentifierFallsBackToWidgetDrawing() {
        #expect(PaeoniaDeepLink(notificationThreadIdentifier: "widget:partner-id") == .widgetDrawing)
        #expect(PaeoniaDeepLink(notificationThreadIdentifier: "daily:couple-id") == nil)
    }

    @MainActor
    @Test func notificationRouterRoutesPayloadsToPendingDeepLink() {
        let router = PaeoniaNotificationRouter.shared
        router.consumePendingDeepLink()

        router.routeNotification(userInfo: ["type": "streak_reminder"])

        #expect(router.pendingDeepLink == .streak)
        router.consumePendingDeepLink()
    }
}
