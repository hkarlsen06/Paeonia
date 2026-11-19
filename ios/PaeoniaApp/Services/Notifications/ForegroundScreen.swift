import Foundation

/// What the paired app has in front of the person right now. A push that arrives while the app is
/// open needs no notice when this screen already shows what it says, because the screen changes
/// as it happens. `MainTabView` keeps `PaeoniaNotificationRouter.screen` up to date.
nonisolated enum ForegroundScreen: Equatable, Sendable {
    /// Any other screen, Us included.
    case elsewhere
    /// The Questions tab's list, with the daily questions and the Topics card.
    case questions
    /// The answer flow for one question, which shows the partner's answer as it arrives. Nil ids
    /// while today's question loads.
    case answering(instanceID: UUID?, coupleDayID: UUID?)
    /// The Topics shelf or one topic.
    case topics
    case chat(ThreadChatSubject)

    /// True when this screen shows where `link` leads.
    func showsLive(_ link: PaeoniaDeepLink) -> Bool {
        switch (self, link) {
        case (.questions, .dailyToday), (.questions, .dailyReveal), (.questions, .topics), (.topics, .topics):
            true
        case let (.answering(_, coupleDayID), .dailyToday(linkDayID)):
            coupleDayID != nil && (linkDayID == nil || linkDayID == coupleDayID)
        case let (.answering(instanceID, _), .dailyReveal(linkInstanceID, _)):
            instanceID == linkInstanceID
        case let (.chat(subject), .dailyChat(questionID)):
            subject == .question(questionID)
        case (.chat(.couple), .coupleChat):
            true
        case let (.chat(.game(chat)), .gameChat(kind)):
            chat.kind == kind
        default:
            false
        }
    }
}
