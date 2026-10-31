import Foundation

@MainActor
struct ThreadChatVoiceDraftEditing {
    let draft: ThreadChatVoiceDraft?
    let save: (ThreadChatVoiceDraft) -> Bool
    let discard: () -> Void
}

extension ThreadChatViewModel {
    private var voiceDraftKey: ThreadChatVoiceDraftKey? {
        participants.currentUserID.map {
            ThreadChatVoiceDraftKey(ownerUserID: $0, coupleID: coupleID, subject: subject)
        }
    }

    func beginVoiceDraftEditing() -> ThreadChatVoiceDraftEditing? {
        guard let key = voiceDraftKey,
              let writerID = voiceDraftStore.beginEditing(key, generation: voiceDraftGeneration)
        else { return nil }
        var draft: ThreadChatVoiceDraft?
        do {
            draft = try voiceDraftStore.read(key, generation: voiceDraftGeneration)
        } catch {
            notice = .voiceDraftReadFailed
        }
        return ThreadChatVoiceDraftEditing(
            draft: draft,
            save: { self.saveVoiceDraft($0, key: key, writerID: writerID) },
            discard: { self.discardVoiceDraft(key: key, writerID: writerID) }
        )
    }

    private func saveVoiceDraft(
        _ draft: ThreadChatVoiceDraft, key: ThreadChatVoiceDraftKey, writerID: UUID
    ) -> Bool {
        do {
            return try voiceDraftStore.save(draft, for: key, generation: voiceDraftGeneration, writerID: writerID)
        } catch {
            notice = .voiceDraftSaveFailed
            return false
        }
    }

    private func discardVoiceDraft(key: ThreadChatVoiceDraftKey, writerID: UUID) {
        do {
            try voiceDraftStore.remove(key, generation: voiceDraftGeneration, writerID: writerID)
        } catch {
            notice = .voiceDraftSaveFailed
        }
    }
}
