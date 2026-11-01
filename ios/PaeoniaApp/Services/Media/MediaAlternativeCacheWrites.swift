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
        let widgetRevisionVersion: Int64?
        let task: Task<Void, Error>
    }
    private var latest: [Key: Write] = [:]

    func perform(ownerUserID: UUID, edit: MediaAlternativeEdit, operation: SyncClientOperation,
                 privacyToken: LocalPrivacyWriteGuard.Token, widgetRevisionVersion: Int64? = nil,
                 update: @escaping @Sendable () async throws -> Void) async throws {
        let key = Key(owner: ownerUserID, target: edit.target)
        let previous = latest[key]
        if let previous, previous.privacyToken == privacyToken, previous.operation.clientID == operation.clientID,
           previous.operation.clientSequence > operation.clientSequence { return }
        let task = Task {
            // A failed write must not block this retry or a newer edit.
            _ = try? await previous?.task.value
            try await update()
        }
        latest[key] = Write(operation: operation, privacyToken: privacyToken, text: edit.text,
                            widgetRevisionVersion: widgetRevisionVersion, task: task)
        try await task.value
    }

    func clear(ownerUserID: UUID) { latest = latest.filter { $0.key.owner != ownerUserID } }

    func acceptedWidgetDescription(ownerUserID: UUID, target: MediaAlternativeTarget)
        -> (text: String, version: Int64)? {
        guard let write = latest[Key(owner: ownerUserID, target: target)],
              LocalPrivacyWriteGuard.shared.isCurrent(write.privacyToken),
              let version = write.widgetRevisionVersion else { return nil }
        return (write.text, version)
    }

    func acceptedText(ownerUserID: UUID, target: MediaAlternativeTarget) -> String? {
        guard let write = latest[Key(owner: ownerUserID, target: target)],
              LocalPrivacyWriteGuard.shared.isCurrent(write.privacyToken) else { return nil }
        return write.text
    }
}
