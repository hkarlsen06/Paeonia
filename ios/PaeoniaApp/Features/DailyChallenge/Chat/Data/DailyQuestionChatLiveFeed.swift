import Foundation

/// Keeps the daily question chat summaries current while the app is open. The
/// summaries drive the last-message previews and the thread lookup for a chat that
/// the partner just started. Each result goes into the chat cache, then the daily
/// screens re-read it. Messages of an open chat arrive through
/// `DailyQuestionChatServicing.liveMessageUpdates`.
nonisolated struct DailyQuestionChatLiveFeed: LiveFeed {
    let name = "daily_question_chat"

    private let cache: any DailyQuestionChatCaching

    init(cache: any DailyQuestionChatCaching) {
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
            let summaries = rows.compactMap(\.dailyQuestionSummary)
            let changed = await cache.saveSummaries(summaries, ownerUserID: session.userID)
            if changed { LocalStoreChanges.post(.dailyChat, ownerUserID: session.userID) }
        }
    }
}
