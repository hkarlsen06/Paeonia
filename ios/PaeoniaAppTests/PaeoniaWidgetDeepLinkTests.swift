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

    @Test func parsesDailyChatURL() throws {
        let questionID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let url = PaeoniaDeepLink.dailyChatURL(questionID: questionID)

        #expect(url.absoluteString == "paeonia://daily/chat?questionId=11111111-1111-1111-1111-111111111111")
        #expect(PaeoniaDeepLink(url) == .dailyChat(questionID: questionID))
    }

    @Test func parsesHomeURL() throws {
        let url = try #require(URL(string: "paeonia://home"))

        #expect(PaeoniaDeepLink(url) == .home)
    }

    @Test func parsesStreakURL() {
        let url = PaeoniaDeepLink.streakURL

        #expect(url.absoluteString == "paeonia://streak")
        #expect(PaeoniaDeepLink(url) == .streak)
    }

    @Test func parsesMemoriesURL() {
        let url = PaeoniaDeepLink.memoriesURL

        #expect(url.absoluteString == "paeonia://memories")
        #expect(PaeoniaDeepLink(url) == .memories)
    }

    @Test func parsesSubscriptionURL() {
        let url = PaeoniaDeepLink.subscriptionURL

        #expect(url.absoluteString == "paeonia://settings/subscription")
        #expect(PaeoniaDeepLink(url) == .subscription)
    }

    @Test func notificationPayloadParsesDeeplink() throws {
        let instanceID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleDayID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let questionID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))

        #expect(
            PaeoniaDeepLink(notificationUserInfo: [
                "type": "partner_answered",
                "deeplink": "paeonia://daily/reveal?instanceId=\(instanceID.uuidString)&coupleDayId=\(coupleDayID.uuidString)",
            ]) == .dailyReveal(instanceID: instanceID, coupleDayID: coupleDayID)
        )
        #expect(
            PaeoniaDeepLink(notificationUserInfo: [
                "deeplink": "paeonia://daily/chat?questionId=\(questionID.uuidString)",
            ]) == .dailyChat(questionID: questionID)
        )
        #expect(
            PaeoniaDeepLink(notificationUserInfo: [
                "deeplink": "paeonia://daily/today?coupleDayId=\(coupleDayID.uuidString)",
            ]) == .dailyToday(coupleDayID: coupleDayID)
        )
        #expect(PaeoniaDeepLink(notificationUserInfo: ["deeplink": "paeonia://widget/drawing"]) == .widgetDrawing)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["deeplink": "paeonia://memories"]) == .memories)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["deeplink": "paeonia://streak"]) == .streak)
        #expect(
            PaeoniaDeepLink(notificationUserInfo: ["deeplink": "paeonia://settings/subscription"]) == .subscription
        )
    }

    @Test func notificationPayloadWithoutUsableDeeplinkIsIgnored() {
        #expect(PaeoniaDeepLink(notificationUserInfo: ["type": "streak_reminder"]) == nil)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["route": "memories"]) == nil)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["deeplink": "https://example.com"]) == nil)
        #expect(PaeoniaDeepLink(notificationUserInfo: ["deeplink": ""]) == nil)
    }

    @MainActor
    @Test func notificationRouterRoutesPayloadsToPendingDeepLink() {
        let router = PaeoniaNotificationRouter.shared
        router.consumePendingDeepLink()

        router.routeNotification(userInfo: ["type": "streak_reminder", "deeplink": "paeonia://streak"])

        #expect(router.pendingDeepLink == .streak)
        router.consumePendingDeepLink()
    }

    @MainActor
    @Test func notificationRouterRoutesThreadMessagesToQuestionChat() throws {
        let questionID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let router = PaeoniaNotificationRouter.shared
        router.consumePendingDeepLink()

        router.routeNotification(userInfo: [
            "type": "thread_message_sent",
            "deeplink": "paeonia://daily/chat?questionId=\(questionID.uuidString)",
        ])

        #expect(router.pendingDeepLink == .dailyChat(questionID: questionID))
        router.consumePendingDeepLink()
    }
}
