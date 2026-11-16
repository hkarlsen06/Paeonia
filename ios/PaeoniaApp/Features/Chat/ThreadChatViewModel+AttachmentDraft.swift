import Foundation

struct ThreadChatAttachmentDraftEditing {
    let draft: ThreadChatAttachmentDraft?
    let save: (ThreadChatAttachmentDraft) -> Bool
}

extension ThreadChatViewModel {
    private var attachmentDraftKey: ThreadChatAttachmentDraftKey? {
        participants.currentUserID.map {
            ThreadChatAttachmentDraftKey(ownerUserID: $0, coupleID: coupleID, subject: subject)
        }
    }

    func beginAttachmentDraftEditing() -> ThreadChatAttachmentDraftEditing? {
        guard let key = attachmentDraftKey,
              let writerID = attachmentDraftStore.beginEditing(key, generation: attachmentDraftGeneration)
        else { return nil }
        var draft: ThreadChatAttachmentDraft?
        do {
            draft = try attachmentDraftStore.read(key, generation: attachmentDraftGeneration)
            if draft?.lostMedia == true { notice = .draftMediaMissing }
        } catch {
            notice = .photoDraftReadFailed
        }
        return ThreadChatAttachmentDraftEditing(draft: draft) { draft in
            self.saveAttachmentDraft(draft, key: key, writerID: writerID)
        }
    }

    private func saveAttachmentDraft(
        _ draft: ThreadChatAttachmentDraft, key: ThreadChatAttachmentDraftKey, writerID: UUID
    ) -> Bool {
        do {
            if draft.isEmpty {
                try attachmentDraftStore.remove(key, generation: attachmentDraftGeneration, writerID: writerID)
                return true
            }
            return try attachmentDraftStore.save(
                draft, for: key, generation: attachmentDraftGeneration, writerID: writerID
            )
        } catch {
            notice = .photoDraftSaveFailed
            return false
        }
    }
}
