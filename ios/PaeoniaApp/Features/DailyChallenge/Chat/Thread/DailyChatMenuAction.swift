import ExyteChat
import SwiftUI

/// The long-press menu on a chat row, like Tidex's. The menu only gets ExyteChat's
/// message, so the choice rests on the row id, who sent it, its text, and whether
/// the server has it yet (see `DailyChatProjection.make`).
enum DailyChatMenuAction: MessageMenuAction, Sendable {
    case reply
    case edit
    case copy
    case report
    /// Stars an answer. The star is private to this person (see `FavoritesStore`).
    case favorite
    case unfavorite

    func title() -> String {
        switch self {
        case .reply: String(localized: .dailyChatActionReply)
        case .edit: String(localized: .dailyChatActionEdit)
        case .copy: String(localized: .dailyChatActionCopy)
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
        case .report: Image(systemName: "flag")
        case .favorite: Image(systemName: "star")
        case .unfavorite: Image(systemName: "star.slash")
        }
    }

    func isDestructive() -> Bool {
        self == .report
    }

    /// The answer a row id stands for, `answer-<id>`.
    private static func answerID(ofRow rowID: String) -> UUID? {
        UUID(uuidString: String(rowID.dropFirst(DailyChatProjection.answerRowPrefix.count)))
    }

    static func menuItems(for message: ExyteChat.Message) -> [Self] {
        let hasText = !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPartner = !message.user.isCurrentUser
        var items: [Self] = []
        if DailyChatProjection.isDecorationRowID(message.id) { return [] }
        if message.id.hasPrefix(DailyChatProjection.questionRowPrefix) {
            return hasText ? [.copy] : []
        }
        let isAnswer = message.id.hasPrefix(DailyChatProjection.answerRowPrefix)
        // Only a message the server has can be replied to or reported. Answers on the page
        // can always be replied to.
        let isOnServer = message.status == .sent
        if isAnswer || isOnServer {
            items.append(.reply)
        }
        // Your own text, for five minutes after the server has it. Answers never.
        if !isAnswer, !isPartner, isOnServer, hasText,
           Date.now.timeIntervalSince(message.createdAt) <= DailyQuestionChatMessage.editWindow {
            items.append(.edit)
        }
        if hasText {
            items.append(.copy)
        }
        if isAnswer, let answerID = answerID(ofRow: message.id) {
            items.append(FavoritesStore.shared.isFavorite(.answer(answerID)) ? .unfavorite : .favorite)
        }
        if isPartner, isAnswer || isOnServer {
            items.append(.report)
        }
        return items
    }
}
