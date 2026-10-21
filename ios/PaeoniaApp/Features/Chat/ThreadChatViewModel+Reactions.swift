import Foundation

// MARK: - Reactions

extension ThreadChatViewModel {
    /// Like Tidex, any message the server has can get a reaction, the user's own too.
    func canReact(to message: ThreadChatMessage) -> Bool {
        canReply(to: message)
    }

    /// Either answer can get a reaction once the user can read it.
    func canReact(to answer: DailyQuestionAnswerDetail) -> Bool {
        answer.canViewAnswer && isChatAvailable
    }

    /// The reactions saved on this phone, by item.
    private var savedReactions: [ThreadChatItemID: [EmojiReaction]] {
        var reactions = Dictionary(grouping: savedAnswerReactions, by: { ThreadChatItemID.answer($0.answerID) })
            .mapValues { $0.map(\.reaction) }
        for message in messages where !message.reactions.isEmpty {
            reactions[.message(message.id)] = message.reactions
        }
        return reactions
    }

    /// Every reaction on the page's messages and answers, with the user's unconfirmed
    /// changes in place of their saved reactions.
    var chatReactions: [ThreadChatItemID: [EmojiReaction]] {
        guard let ownerUserID = participants.currentUserID else { return [:] }
        let saved = savedReactions
        var reactions = saved
        for target in reactionEditor.pending.keys {
            guard let item = ThreadChatItemID(reactionTarget: target) else { continue }
            let list = reactionEditor.reactions(on: target, saved: saved[item] ?? [], userID: ownerUserID)
            reactions[item] = list.isEmpty ? nil : list
        }
        return reactions
    }

    /// The user's own reaction to a message or an answer, as the page shows it.
    func ownReaction(to item: ThreadChatItemID) -> String? {
        reactionEditor.ownReaction(
            on: item.reactionTarget,
            saved: savedReactions[item] ?? [],
            userID: participants.currentUserID
        )
    }

    /// Puts `emoji` on a message or an answer. Choosing the reaction already there takes
    /// it back. The change shows at once, and the earlier reaction comes back if the
    /// server turns it down.
    func toggleReaction(_ emoji: String, on item: ThreadChatItemID) async {
        guard let ownerUserID = participants.currentUserID else { return }
        let failure = await reactionEditor.toggle(
            emoji,
            on: item.reactionTarget,
            saved: savedReactions[item] ?? [],
            userID: ownerUserID
        ) { [service, coupleID, subject, threadID] next in
            try await service.setReaction(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                subjectID: subject.id,
                threadID: threadID,
                item: item,
                emoji: next
            )
        }
        if let failure {
            notice = .reactionFailed(failure)
        } else {
            await readStore(ownerUserID: ownerUserID)
        }
    }

    /// Forgets the unconfirmed reactions the saved copy now shows.
    func dropSavedPendingReactions(ownerUserID: UUID) {
        let saved = savedReactions
        reactionEditor.settle(userID: ownerUserID) { target in
            ThreadChatItemID(reactionTarget: target).flatMap { saved[$0] } ?? []
        }
    }
}
