import Foundation

@MainActor
struct ThreadChatPhotoDraftEditing {
    let draft: ThreadChatPhotoDraft?
    let save: (ThreadChatPhotoDraft) -> Bool
}

extension ThreadChatViewModel {
    private var photoDraftKey: ThreadChatPhotoDraftKey? {
        participants.currentUserID.map {
            ThreadChatPhotoDraftKey(ownerUserID: $0, coupleID: coupleID, subject: subject)
        }
    }

    func beginPhotoDraftEditing() -> ThreadChatPhotoDraftEditing? {
        guard let key = photoDraftKey,
              let writerID = photoDraftStore.beginEditing(key, generation: photoDraftGeneration)
        else { return nil }
        var draft: ThreadChatPhotoDraft?
        do {
            draft = try photoDraftStore.read(key, generation: photoDraftGeneration)
        } catch {
            notice = .photoDraftReadFailed
        }
        return ThreadChatPhotoDraftEditing(draft: draft) { draft in
            self.savePhotoDraft(draft, key: key, writerID: writerID)
        }
    }

    private func savePhotoDraft(
        _ draft: ThreadChatPhotoDraft, key: ThreadChatPhotoDraftKey, writerID: UUID
    ) -> Bool {
        do {
            if draft.isEmpty {
                try photoDraftStore.remove(key, generation: photoDraftGeneration, writerID: writerID)
                return true
            }
            return try photoDraftStore.save(draft, for: key, generation: photoDraftGeneration, writerID: writerID)
        } catch {
            notice = .photoDraftSaveFailed
            return false
        }
    }
}
