import Foundation

/// The photo in a letter being written, compressed once when it was picked. Its bytes live in
/// their own file, named by `id`, so typing never writes them again.
nonisolated struct LetterPhoto: Codable, Equatable, Sendable {
    /// New each time a photo is picked, so a different photo is a different send.
    let id: UUID
    let mimeType: String
    let fileExtension: String
    let width: Int
    let height: Int
}

/// What a letter says and when it arrives, as the composer builds it.
nonisolated struct LetterContent: Codable, Equatable, Sendable {
    var templateKey: LetterTemplate.Key
    var body: String
    var delivery: LetterDelivery = .now
    var photo: LetterPhoto?

    init(templateKey: LetterTemplate.Key, body: String) {
        self.templateKey = templateKey
        self.body = body
    }

    /// The note as the server stores it.
    var trimmedBody: String {
        LetterBody.trimmed(body)
    }

    var canSend: Bool {
        LetterBody.canSend(body)
    }
}

/// The client operations of one send. A retry reuses them, so the server sees the same
/// photo reservation and the same send again.
nonisolated struct LetterSendOperations: Codable, Equatable, Sendable {
    let reserve: SyncClientOperation
    let finalize: SyncClientOperation
    let send: SyncClientOperation
}

nonisolated struct LetterSend: Codable, Equatable, Sendable {
    let id: UUID
    let content: LetterContent
    let operations: LetterSendOperations
}

/// The letter one person is writing. There is at most one per person on a phone, and only
/// `LetterComposer` writes it.
nonisolated struct LetterDraft: Codable, Equatable, Sendable {
    var content: LetterContent
    /// The last send that started and was not seen to finish. It is saved before the request
    /// goes out, so a send cut off by a lost answer or by the app closing goes out again with
    /// the same letter id and operations, and the server stores the letter once.
    var pendingSend: LetterSend?

    /// The send to make now. It is the pending one while the letter is unchanged, otherwise a new one.
    func nextSend(makeOperation: () -> SyncClientOperation) -> LetterSend {
        if let pendingSend, pendingSend.content == content { return pendingSend }
        return LetterSend(
            id: UUID(),
            content: content,
            operations: LetterSendOperations(reserve: makeOperation(), finalize: makeOperation(), send: makeOperation())
        )
    }
}

/// A draft as the phone stored it, with the purge generation it was read in. Writes made from
/// it carry that generation, so none of them lands after a privacy purge.
nonisolated struct StoredLetterDraft: Sendable {
    var draft: LetterDraft?
    /// Nil when the draft has no photo, or when its photo file is gone.
    var photo: Data?
    var generation: Int
}
