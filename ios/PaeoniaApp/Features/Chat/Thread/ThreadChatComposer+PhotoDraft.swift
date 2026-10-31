import SwiftUI

extension ThreadChatComposer {
    func restorePhotoDraft() {
        guard let editing = beginPhotoDraft() else { return }
        if staging.staged.isEmpty, let draft = editing.draft {
            staging.restore(draft)
            if editingMessage == nil, text.wrappedValue.isEmpty {
                text.wrappedValue = draft.caption
            }
        }
        // Capture the view model callback, rather than this view and its staging object.
        let saveDraft = editing.save
        staging.onDraftChange = { draft in _ = saveDraft(draft) }
        if !staging.staged.isEmpty || !text.wrappedValue.isEmpty {
            savePhotoDraftCaption()
        }
    }

    func savePhotoDraftCaption() {
        guard editingMessage == nil else { return }
        staging.updateCaption(text.wrappedValue)
    }
}
