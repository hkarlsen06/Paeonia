import Foundation

extension FileThreadChatCache {
    func updateMediaAlternative(_ edit: MediaAlternativeEdit, ownerUserID: UUID, unlessPurgedSince generation: Int) {
        guard generation == purgeGeneration() else { return }
        var changed = false
        for key in subjectKeys(ownerUserID) {
            changed = updateSubject(ownerUserID, key) {
                $0.applyMediaAlternative(edit, ownerUserID: ownerUserID)
            } || changed
        }
        if changed { LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID) }
    }
}
