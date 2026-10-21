import Foundation

// The newest page of a chat replaces only the newest part of the cache, and older cached
// messages stay because earlier loads of older pages put them there. A message deleted
// meanwhile would keep its text and files on this phone. Opening the chat reads the older
// pages again, as far back as the cache goes, so the server's deleted markers replace them.
extension ThreadChatService {
    /// How many pages of older messages one open of the chat reads again. The cache can hold
    /// far more than that. Past the limit the older cached messages are dropped, and
    /// scrolling up loads them again from the server.
    static let revalidationPageLimit = 20

    func revalidateOlderCachedMessages(
        ownerUserID: UUID,
        subjectID: UUID,
        threadID: UUID,
        newestPage: ThreadChatMessagePage,
        purgeGeneration generation: Int
    ) async {
        guard newestPage.hasMore,
              let first = newestPage.messages.min(by: Self.isOlder),
              let oldestCached = await oldestConfirmedCursor(ownerUserID: ownerUserID, subjectID: subjectID)
        else { return }
        var cursor = ThreadChatMessageCursor(createdAt: first.createdAt, messageID: first.id)
        var pagesRead = 0
        while Self.isBefore(oldestCached, cursor) {
            guard !Task.isCancelled else { return }
            guard pagesRead < Self.revalidationPageLimit else {
                await cache.trimMessages(
                    before: cursor,
                    ownerUserID: ownerUserID,
                    subjectID: subjectID,
                    unlessPurgedSince: generation
                )
                return
            }
            // A failed read leaves the older messages as they are, and the next open tries again.
            guard let page = try? await gateway.loadMessages(
                threadID: threadID,
                subjectID: subjectID,
                before: cursor
            ) else { return }
            pagesRead += 1
            let cached = await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
            await cache.mergeOlderMessages(
                await withDeletions(page.messages, cached: cached, ownerUserID: ownerUserID),
                ownerUserID: ownerUserID,
                subjectID: subjectID,
                unlessPurgedSince: generation
            )
            guard page.hasMore, let oldest = page.messages.min(by: Self.isOlder) else { return }
            cursor = ThreadChatMessageCursor(createdAt: oldest.createdAt, messageID: oldest.id)
        }
    }

    private func oldestConfirmedCursor(ownerUserID: UUID, subjectID: UUID) async -> ThreadChatMessageCursor? {
        let cached = await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
        return cached
            .filter { !$0.isSending && !$0.sendFailed }
            .min(by: Self.isOlder)
            .map { ThreadChatMessageCursor(createdAt: $0.createdAt, messageID: $0.id) }
    }

    private nonisolated static func isOlder(_ lhs: ThreadChatMessage, _ rhs: ThreadChatMessage) -> Bool {
        (lhs.createdAt, lhs.id.uuidString) < (rhs.createdAt, rhs.id.uuidString)
    }

    private nonisolated static func isBefore(_ lhs: ThreadChatMessageCursor, _ rhs: ThreadChatMessageCursor) -> Bool {
        (lhs.createdAt, lhs.messageID.uuidString) < (rhs.createdAt, rhs.messageID.uuidString)
    }
}
