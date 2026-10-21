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

    @Test func memoryAndStoryLinksCarryTheirIDAndTheConversationFlag() throws {
        let id = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

        #expect(PaeoniaDeepLink(PaeoniaDeepLink.memoryURL(memoryID: id)) == .memory(memoryID: id, showsComments: false))
        #expect(
            PaeoniaDeepLink(PaeoniaDeepLink.memoryURL(memoryID: id, showsComments: true))
                == .memory(memoryID: id, showsComments: true)
        )
        #expect(PaeoniaDeepLink(PaeoniaDeepLink.storyURL(storyID: id)) == .story(storyID: id, showsReplies: false))
        #expect(
            PaeoniaDeepLink(notificationUserInfo: ["deeplink": "paeonia://stories/story?storyId=\(id.uuidString)&replies=1"])
                == .story(storyID: id, showsReplies: true)
        )
        // A link without an id is not a link to a memory, and the host alone still opens the tab.
        #expect(PaeoniaDeepLink(URL(string: "paeonia://memories/memory")!) == nil)
        #expect(PaeoniaDeepLink(URL(string: "paeonia://stories/story?storyId=nope")!) == nil)
        #expect(PaeoniaDeepLink(URL(string: "paeonia://memories")!) == .memories)
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
}
