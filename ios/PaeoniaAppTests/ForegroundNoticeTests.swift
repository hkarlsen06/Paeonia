import Foundation
import Testing
import UserNotifications
@testable import PaeoniaApp

struct ForegroundNoticeTests {
    private static let partnerID = "22222222-2222-2222-2222-222222222222"
    private static let dayID = UUID()
    private static let instanceID = UUID()

    private static func push(_ type: String, deeplink: String? = nil) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Robin"
        content.body = "Something happened"
        var userInfo: [String: Any] = ["type": type, "actor_user_id": partnerID]
        userInfo["deeplink"] = deeplink
        content.userInfo = userInfo
        return content
    }

    @Test(arguments: [
        ("daily_challenge_completed", "paeonia://daily/today?coupleDayId=\(dayID.uuidString)"),
        ("partner_answered", "paeonia://daily/reveal?instanceId=\(instanceID.uuidString)&coupleDayId=\(dayID.uuidString)"),
        ("topics_waiting", "paeonia://topics"),
    ])
    func partnersAnswerBecomesANoticeFromThePartner(type: String, deeplink: String) throws {
        let notice = try #require(PaeoniaAppDelegate.foregroundNotice(for: Self.push(type, deeplink: deeplink)))

        #expect(notice.showsPartnerAvatar)
        #expect(notice.isPartnersDoing)
        #expect(notice.deepLink == URL(string: deeplink).flatMap(PaeoniaDeepLink.init))
    }

    /// The open app shows these wherever the person is: the chat feed, the pairing celebration, the
    /// restore question and the call screen.
    @Test(arguments: ["thread_message_sent", "partner_joined", "relationship_restore", "missed_call", "badge_update"])
    func pushTheAppShowsAnywayMakesNoNotice(type: String) {
        #expect(PaeoniaAppDelegate.foregroundNotice(for: Self.push(type, deeplink: "paeonia://chat")) == nil)
    }

    @Test func chatPushWithoutATypeMakesNoNotice() {
        let content = UNMutableNotificationContent()
        content.title = "Robin"
        content.body = "Sent you a message"
        content.threadIdentifier = "chat:55555555-5555-5555-5555-555555555555"

        #expect(PaeoniaAppDelegate.foregroundNotice(for: content) == nil)
    }

    @Test func todaysAnswerIsNewsOnUsButNotWhereTheQuestionShows() {
        let today = PaeoniaDeepLink.dailyToday(coupleDayID: Self.dayID)

        #expect(!ForegroundScreen.elsewhere.showsLive(today))
        #expect(ForegroundScreen.questions.showsLive(today))
        #expect(ForegroundScreen.answering(instanceID: Self.instanceID, coupleDayID: Self.dayID).showsLive(today))
        #expect(!ForegroundScreen.answering(instanceID: UUID(), coupleDayID: UUID()).showsLive(today))
        #expect(!ForegroundScreen.topics.showsLive(today))
        #expect(!ForegroundScreen.chat(.couple).showsLive(today))
    }

    @Test func revealIsHeldBackOnlyOnItsOwnQuestion() {
        let reveal = PaeoniaDeepLink.dailyReveal(instanceID: Self.instanceID, coupleDayID: Self.dayID)

        #expect(ForegroundScreen.questions.showsLive(reveal))
        #expect(ForegroundScreen.answering(instanceID: Self.instanceID, coupleDayID: Self.dayID).showsLive(reveal))
        #expect(!ForegroundScreen.answering(instanceID: UUID(), coupleDayID: Self.dayID).showsLive(reveal))
        #expect(!ForegroundScreen.elsewhere.showsLive(reveal))
    }

    @Test func topicAnswersShowOnTheQuestionsListAndInTopics() {
        #expect(ForegroundScreen.questions.showsLive(.topics))
        #expect(ForegroundScreen.topics.showsLive(.topics))
        #expect(!ForegroundScreen.elsewhere.showsLive(.topics))
        #expect(!ForegroundScreen.answering(instanceID: Self.instanceID, coupleDayID: Self.dayID).showsLive(.topics))
    }

    @Test func chatLinkIsHeldBackOnlyInThatChat() {
        let questionID = UUID()

        #expect(ForegroundScreen.chat(.question(questionID)).showsLive(.dailyChat(questionID: questionID)))
        #expect(!ForegroundScreen.chat(.question(UUID())).showsLive(.dailyChat(questionID: questionID)))
        #expect(ForegroundScreen.chat(.couple).showsLive(.coupleChat))
        #expect(!ForegroundScreen.questions.showsLive(.coupleChat))
    }
}
