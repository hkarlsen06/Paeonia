import SwiftUI

// MARK: - Replies and reactions

extension DailyQuestionChatView {
    var replyPreview: DailyChatReplyPreview? {
        switch viewModel.replyTarget {
        case let .message(message):
            DailyChatProjection.preview(of: message, id: message.id, input: projectionInput)
        case let .answer(answer):
            DailyChatProjection.answerPreview(of: answer.answerID, input: projectionInput)
        case nil:
            nil
        }
    }

    /// Swiping a message or an answer toward the middle starts a reply to it.
    func replyAction(for row: DailyChatRow) -> (() -> Void)? {
        if let message = row.message, viewModel.canReply(to: message) {
            return { viewModel.setReplyTarget(message) }
        }
        if let answer = row.answer, viewModel.canReply(to: answer) {
            return { viewModel.setReplyTarget(answer) }
        }
        return nil
    }

    /// Like Tidex, every pick moves the emoji to the front of the reaction row.
    func react(_ emoji: String, to item: DailyChatItemID) {
        DailyChatReactionPalette.shared.recordSelection(emoji)
        Task { await viewModel.toggleReaction(emoji, on: item) }
    }

    /// The message or answer on a row, when the user can react to it.
    func reactableItem(_ row: DailyChatRow?) -> DailyChatItemID? {
        if let message = row?.message, viewModel.canReact(to: message) {
            return .message(message.id)
        }
        if let answer = row?.answer, viewModel.canReact(to: answer) {
            return .answer(answer.answerID)
        }
        return nil
    }
}
