#if DEBUG
  import SwiftUI
  import UserNotifications

  /// Robin answers today's question while Home is open, and the push about it arrives while the app
  /// is open. With Robin in the app the news shows in Robin's picture, and without it as a banner.
  nonisolated extension DeveloperScenario {
    static let foregroundNotices: [DeveloperScenario] = [foregroundDailyAnswerPresence, foregroundDailyAnswerBanner]

    static let foregroundDailyAnswerPresence = DeveloperScenario(
      "foreground-daily-answer", "Notifications · Robin answers while Us is open",
      "Robin, who is in the app, answers today's question while you look at Us", .deepLinks
    ) { _ in
      DeveloperLocalFlowHost(
        seed: .paired, avatarStories: .noStory, presence: DeveloperPresenceFixture.model(partner: PartnerPresence()),
        partnerAnswersAfter: .seconds(12))
    }

    static let foregroundDailyAnswerBanner = DeveloperScenario(
      "foreground-daily-answer-banner", "Notifications · Robin answers and leaves",
      "Robin answers today's question and leaves the app while you look at Us", .deepLinks
    ) { _ in DeveloperLocalFlowHost(seed: .paired, avatarStories: .noStory, partnerAnswersAfter: .seconds(12)) }
  }

  /// Pushes as the server sends them, for scenarios that show what the open app does with one.
  nonisolated enum DeveloperForegroundPush {
    static func partnerAnsweredToday(coupleDayID: UUID?) -> UNNotificationContent {
      let content = UNMutableNotificationContent()
      content.title = "Robin answered today's question"
      content.body = "Answer it to see what they said."
      content.threadIdentifier = "daily"
      content.userInfo = [
        "type": "daily_challenge_completed",
        "route": "daily",
        "actor_user_id": DeveloperScenarioFixture.partnerUserID.uuidString,
        "deeplink": "paeonia://daily/today" + (coupleDayID.map { "?coupleDayId=\($0.uuidString)" } ?? ""),
      ]
      return content
    }
  }
#endif
