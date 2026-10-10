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
            await cache.saveSummaries(rows.compactMap(\.dailyQuestionSummary), ownerUserID: session.userID)
            LocalStoreChanges.post(.dailyChat, ownerUserID: session.userID)
        }
    }
}
