import Foundation

// MARK: - Replies

extension DailyQuestionChatViewModel {
    /// Only messages the server has can be replied to. A message still sending has no id there yet.
    func canReply(to message: DailyQuestionChatMessage) -> Bool {
        !message.isSending && !message.sendFailed && message.threadID != nil
    }

    /// Either answer on the page can be replied to, once the user can read it.
    func canReply(to answer: DailyQuestionAnswerDetail) -> Bool {
        answer.canViewAnswer && isChatAvailable
    }

    func setReplyTarget(_ message: DailyQuestionChatMessage) {
        guard canReply(to: message) else { return }
        startReply(.message(message))
    }

    func setReplyTarget(_ answer: DailyQuestionAnswerDetail) {
        guard canReply(to: answer) else { return }
        startReply(.answer(answer))
    }

    private func startReply(_ target: DailyChatReplyTarget) {
        // The composer holds the edited text, so a reply waits until the edit is done.
        guard editTarget == nil else { return }
        replyTarget = target
        composerFocusRequest += 1
    }

    func cancelReply() {
        replyTarget = nil
    }

    /// The message a reply points at, when it is still in the chat.
    func message(withID id: UUID) -> DailyQuestionChatMessage? {
        messages.first { $0.id == id }
    }
}
