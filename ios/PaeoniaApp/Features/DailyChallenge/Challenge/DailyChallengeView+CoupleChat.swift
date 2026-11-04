import SwiftUI

/// The couple chat ("Just us") on the Chats tab: its pinned card and how it opens.
extension DailyChallengeScreen {
    /// Above everything else on the tab, so the couple's own chat is always one tap away.
    @ViewBuilder
    var coupleChatCard: some View {
        if chatContext.isAvailable {
            CoupleChatCard(
                participants: viewModel.participants,
                summary: chatContext.summaries?.summary(for: .couple),
                isUnread: chatContext.summaries?.isUnread(.couple) ?? false,
                onOpen: openCoupleChat
            )
        }
    }

    /// Reads the chat from the phone first, then pushes it, like the other conversations. It has
    /// no header card, because it is not about anything in particular.
    func openCoupleChat() {
        guard !isOpeningChat, conversationChat?.viewModel.subject != .couple else { return }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { isOpeningChat = true }
        Task {
            guard let chat = await chatContext.makeViewModel(subject: .couple, header: nil) else {
                isOpeningChat = false
                return
            }
            await Task.yield()
            chatQuestion.wrappedValue = nil
            conversationChat = ConversationChatDestination(coupleChat: chat)
        }
    }

    static func analyticsScreenName(of kind: ThreadChatSubject.Kind) -> String {
        switch kind {
        case .game: "game_conversation"
        case .memory: "memory_comments"
        case .story: "story_replies"
        case .couple: "couple_chat"
        case .question: "daily_chat"
        }
    }
}
