import Foundation

extension FileThreadChatCache {
    @discardableResult
    func markDeleted(ownerUserID: UUID, subjectID: UUID, messageID: UUID, at date: Date) -> [UUID] {
        var mediaAssetIDs: [UUID] = []
        updateSubject(ownerUserID, subjectID.uuidString) { document in
            guard let index = document.messages.firstIndex(where: { $0.id == messageID && !$0.isDeleted })
            else { return }
            let message = document.messages[index]
            mediaAssetIDs = message.mediaAssetIDs
            var gone = message.takenBack
            gone.deletedAt = date
            document.messages[index] = gone
        }
        updateCore(ownerUserID) { $0.clearLastMessage(ifID: messageID) }
        return mediaAssetIDs
    }

    @discardableResult
    func markDeletedInAnyChat(ownerUserID: UUID, messageID: UUID, at date: Date) -> [UUID] {
        let key = subjectKeys(ownerUserID).first { key in
            subjectDocument(ownerUserID, key).messages.contains { $0.id == messageID }
        }
        guard let key, let subjectID = UUID(uuidString: key) else { return [] }
        return markDeleted(ownerUserID: ownerUserID, subjectID: subjectID, messageID: messageID, at: date)
    }
}
