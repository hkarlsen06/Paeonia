import Foundation

// MARK: - Reactions

/// The user's reaction to a message or an answer while the server hasn't confirmed it.
/// A nil emoji means the user took their reaction back.
struct PendingReaction: Equatable {
    let emoji: String?
    /// Tells this change apart from a later one on the same item.
    let id = UUID()
}

extension DailyQuestionChatViewModel {
    /// Like Tidex, any message the server has can get a reaction, the user's own too.
    func canReact(to message: DailyQuestionChatMessage) -> Bool {
        canReply(to: message)
    }

    /// Either answer can get a reaction once the user can read it.
    func canReact(to answer: DailyQuestionAnswerDetail) -> Bool {
        answer.canViewAnswer && isChatAvailable
    }

    /// The reactions saved on this phone, by item.
    private var savedReactions: [DailyChatItemID: [DailyChatReaction]] {
        var reactions = Dictionary(grouping: savedAnswerReactions, by: { DailyChatItemID.answer($0.answerID) })
            .mapValues { $0.map(\.reaction) }
        for message in messages where !message.reactions.isEmpty {
            reactions[.message(message.id)] = message.reactions
        }
        return reactions
    }

    /// Every reaction on the page's messages and answers, with the user's unconfirmed
    /// changes in place of their saved reactions.
    var chatReactions: [DailyChatItemID: [DailyChatReaction]] {
        guard let ownerUserID = participants.currentUserID else { return [:] }
        var reactions = savedReactions
        for (item, pending) in pendingReactions {
            var list = (reactions[item] ?? []).filter { $0.userID != ownerUserID }
            if let emoji = pending.emoji { list.append(DailyChatReaction(userID: ownerUserID, emoji: emoji)) }
            reactions[item] = list.isEmpty ? nil : list
        }
        return reactions
    }

    /// The user's own reaction to a message or an answer, as the page shows it.
    func ownReaction(to item: DailyChatItemID) -> String? {
        if let pending = pendingReactions[item] { return pending.emoji }
        return savedReactions[item]?.first { $0.userID == participants.currentUserID }?.emoji
    }

    /// Puts `emoji` on a message or an answer. Choosing the reaction already there takes
    /// it back. The change shows at once, and the earlier reaction comes back if the
    /// server turns it down.
    func toggleReaction(_ emoji: String, on item: DailyChatItemID) async {
        guard let ownerUserID = participants.currentUserID else { return }
        let next = ownReaction(to: item) == emoji ? nil : emoji
        let pending = PendingReaction(emoji: next)
        pendingReactions[item] = pending
        PaeoniaHaptics.selection()
        do {
            try await service.setReaction(
                ownerUserID: ownerUserID,
                coupleID: question.coupleID,
                questionID: question.questionID,
                threadID: threadID,
                item: item,
                emoji: next
            )
            await readStore(ownerUserID: ownerUserID)
        } catch {
            guard pendingReactions[item] == pending else { return }
            pendingReactions[item] = nil
            notice = .reactionFailed(PaeoniaFailure(error))
        }
    }

    /// Forgets the unconfirmed reactions the saved copy now shows.
    func dropSavedPendingReactions(ownerUserID: UUID) {
        let saved = savedReactions
        for (item, pending) in pendingReactions {
            let own = saved[item]?.first { $0.userID == ownerUserID }?.emoji
            if own == pending.emoji { pendingReactions[item] = nil }
        }
    }
}
