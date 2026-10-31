import Foundation

extension ThreadChatViewModel {
    /// Loads the page of messages before the oldest one on this phone. A failed load
    /// leaves the list as it is, and scrolling to the top again tries once more.
    func loadOlderMessages() async {
        guard hasOlderMessages, !isLoadingOlderMessages,
              let ownerUserID = participants.currentUserID else { return }
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        if case let .game(game) = subject {
            try? await service.loadOlderGameTimeline(ownerUserID: ownerUserID, subject: game)
            await readStore(ownerUserID: ownerUserID)
            return
        }
        guard let threadID else { return }
        guard let hasMore = try? await service.loadOlderMessages(
            ownerUserID: ownerUserID,
            subjectID: subject.id,
            threadID: threadID
        ) else { return }
        if !hasMore { hasReachedChatStart = true }
        await readStore(ownerUserID: ownerUserID)
    }
}
