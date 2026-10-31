import Foundation

/// Keeps the multi-cache change in order even when an older queue or network response resumes late.
/// A clock change cannot reorder writes from the same client. Different clients keep server ordering.
actor MediaAlternativeCacheWrites {
    static let shared = MediaAlternativeCacheWrites()
    private struct Key: Hashable { let owner: UUID; let target: MediaAlternativeTarget }
    private struct Write {
        let operation: SyncClientOperation
        let privacyToken: LocalPrivacyWriteGuard.Token
        let text: String
        let task: Task<Void, Never>
    }
    private var latest: [Key: Write] = [:]

    func perform(ownerUserID: UUID, edit: MediaAlternativeEdit, operation: SyncClientOperation,
                 privacyToken: LocalPrivacyWriteGuard.Token,
                 update: @escaping @Sendable () async -> Void) async {
        let key = Key(owner: ownerUserID, target: edit.target)
        let previous = latest[key]
        if let previous, previous.privacyToken == privacyToken, previous.operation.clientID == operation.clientID,
           previous.operation.clientSequence > operation.clientSequence { return }
        let task = Task {
            await previous?.task.value
            await update()
        }
        latest[key] = Write(operation: operation, privacyToken: privacyToken, text: edit.text, task: task)
        await task.value
    }

    func clear(ownerUserID: UUID) { latest = latest.filter { $0.key.owner != ownerUserID } }

    func acceptedText(ownerUserID: UUID, target: MediaAlternativeTarget) -> String? {
        guard let write = latest[Key(owner: ownerUserID, target: target)],
              LocalPrivacyWriteGuard.shared.isCurrent(write.privacyToken) else { return nil }
        return write.text
    }
}
