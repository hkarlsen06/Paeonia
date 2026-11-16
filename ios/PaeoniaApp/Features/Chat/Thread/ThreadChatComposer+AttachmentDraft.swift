import SwiftUI

extension ThreadChatComposer {
    func restoreAttachmentDraft() {
        guard let editing = beginAttachmentDraft() else { return }
        if staging.staged.isEmpty, let draft = editing.draft {
            staging.restore(draft)
            if editingMessage == nil, text.wrappedValue.isEmpty {
                text.wrappedValue = draft.caption
            }
        }
        // Capture the view model callback, rather than this view and its staging object.
        let saveDraft = editing.save
        staging.onDraftChange = { draft in _ = saveDraft(draft) }
        // Saving also forgets a video whose file is gone, so its notice shows once.
        if !staging.staged.isEmpty || !text.wrappedValue.isEmpty || editing.draft?.lostMedia == true {
            saveAttachmentDraftCaption()
        }
    }

    func saveAttachmentDraftCaption() {
        guard editingMessage == nil else { return }
        staging.updateCaption(text.wrappedValue)
    }
}
