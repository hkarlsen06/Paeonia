import Foundation

extension DailyQuestionChatViewModel {
    /// Loads the page of messages before the oldest one on this phone. A failed load
    /// leaves the list as it is, and scrolling to the top again tries once more.
    func loadOlderMessages() async {
        guard hasOlderMessages, !isLoadingOlderMessages,
              let ownerUserID = participants.currentUserID, let threadID else { return }
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        guard let hasMore = try? await service.loadOlderMessages(
            ownerUserID: ownerUserID,
            questionID: question.questionID,
            threadID: threadID
        ) else { return }
        if !hasMore { hasReachedChatStart = true }
        await readStore(ownerUserID: ownerUserID)
    }
}
