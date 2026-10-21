import ExyteChat
import SwiftUI

/// The long-press menu on a chat row, like Tidex's. The menu only gets ExyteChat's
/// message, so the choice rests on the row id, who sent it, its text, and whether
/// the server has it yet (see `ThreadChatProjection.make`).
enum ThreadChatMenuAction: MessageMenuAction, Sendable {
    case reply
    case edit
    case copy
    case delete
    case report
    /// Stars an answer. The star is private to this person (see `FavoritesStore`).
    case favorite
    case unfavorite

    func title() -> String {
        switch self {
        case .reply: String(localized: .dailyChatActionReply)
        case .edit: String(localized: .dailyChatActionEdit)
        case .copy: String(localized: .dailyChatActionCopy)
        case .delete: String(localized: .dailyChatActionDelete)
        case .report: String(localized: .dailyChatActionReport)
        case .favorite: String(localized: .favoritesStar)
        case .unfavorite: String(localized: .favoritesRemoveStar)
        }
    }

    func icon() -> Image {
        switch self {
        case .reply: Image(systemName: "arrowshape.turn.up.left")
        case .edit: Image(systemName: "pencil")
        case .copy: Image(systemName: "doc.on.doc")
        case .delete: Image(systemName: "trash")
        case .report: Image(systemName: "flag")
        case .favorite: Image(systemName: "star")
        case .unfavorite: Image(systemName: "star.slash")
        }
    }

    func isDestructive() -> Bool {
        self == .report || self == .delete
    }

    /// The answer a row id stands for, `answer-<id>`.
    private static func answerID(ofRow rowID: String) -> UUID? {
        UUID(uuidString: String(rowID.dropFirst(ThreadChatProjection.answerRowPrefix.count)))
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func menuItems(for message: ExyteChat.Message) -> [Self] {
        let hasText = !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPartner = !message.user.isCurrentUser
        var items: [Self] = []
        if ThreadChatProjection.isDecorationRowID(message.id) { return [] }
        if message.id.hasPrefix(ThreadChatProjection.questionRowPrefix) {
            return hasText ? [.copy] : []
        }
        // A message its sender took back has nothing left to reply to, copy, or report.
        if message.id.hasPrefix(ThreadChatProjection.deletedRowPrefix) { return [] }
        let isAnswer = message.id.hasPrefix(ThreadChatProjection.answerRowPrefix)
        // Only a message the server has can be replied to or reported. Answers on the page
        // can always be replied to.
        let isOnServer = message.status == .sent
        if isAnswer || isOnServer {
            items.append(.reply)
        }
        // Your own text, for five minutes after the server has it. Answers never.
        if !isAnswer, !isPartner, isOnServer, hasText,
           Date.now.timeIntervalSince(message.createdAt) <= ThreadChatMessage.editWindow {
            items.append(.edit)
        }
        if hasText {
            items.append(.copy)
        }
        if isAnswer, let answerID = answerID(ofRow: message.id) {
            items.append(FavoritesStore.shared.isFavorite(.answer(answerID)) ? .unfavorite : .favorite)
        }
        // Your own message, whatever it holds and however old it is. One that is still
        // sending or failed is taken out of the send queue instead.
        if !isAnswer, !isPartner {
            items.append(.delete)
        }
        if isPartner, isAnswer || isOnServer {
            items.append(.report)
        }
        return items
    }
}
