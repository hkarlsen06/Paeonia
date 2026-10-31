import Foundation

extension FileThreadChatCache {
    func gameTimeline(ownerUserID: UUID, subjectID: UUID) -> GameChatTimeline? {
        subjectDocument(ownerUserID, subjectID.uuidString).gameTimeline
    }

    @discardableResult
    func saveGameTimeline(
        _ timeline: GameChatTimeline, ownerUserID: UUID, subjectID: UUID,
        older: Bool, unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == purgeGeneration() else { return false }
        updateSubject(ownerUserID, subjectID.uuidString) { document in
            let merged = document.gameTimeline?.merging(timeline, older: older) ?? timeline
            document.gameTimeline = merged
            document.messages = ThreadChatMessage.visibleOrdered(
                remote: merged.messages, optimistic: document.messages)
        }
        LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
        return true
    }

    func gameResult(ownerUserID: UUID, subjectID: UUID) -> GameConversationResult? {
        subjectDocument(ownerUserID, subjectID.uuidString).gameResult
    }

    @discardableResult
    func saveGameResult(
        _ result: GameConversationResult?, ownerUserID: UUID, subjectID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == purgeGeneration() else { return false }
        updateSubject(ownerUserID, subjectID.uuidString) { $0.gameResult = result }
        return true
    }

}
