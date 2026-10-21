import Foundation

/// Keeps the summaries of every chat current while the app is open: a question's chat, a
/// memory's comments and a story's replies. The summaries drive the last-message previews,
/// the unread marks, and the thread lookup for a chat that the partner just started. Each
/// result goes into the chat cache, then the screens re-read it. Messages of an open chat
/// arrive through `ThreadChatServicing.liveMessageUpdates`.
nonisolated struct ThreadChatLiveFeed: LiveFeed {
    let name = "daily_question_chat"

    private let cache: any ThreadChatCaching

    init(cache: any ThreadChatCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe(
            "threads:get_conversation_threads",
            as: [ConversationThreadRow].self
        )
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(rows) = result else {
                continue
            }
            guard !Task.isCancelled else {
                return
            }
            // An unchanged result writes nothing, and the screens have nothing new to read.
            let summaries = rows.compactMap(\.summary)
            let changed = await cache.saveSummaries(summaries, ownerUserID: session.userID)
            if changed { LocalStoreChanges.post(.threadChat, ownerUserID: session.userID) }
        }
    }
}
