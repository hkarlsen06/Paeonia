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

/// The four steps of writing a letter, in order.
nonisolated enum LetterComposerStep: Int, Codable, CaseIterable, Sendable {
    case template
    case note
    case photo
    case delivery
}

/// The letter one person is writing. There is at most one per person on a phone, and only
/// `LetterComposer` writes it.
nonisolated struct LetterDraft: Codable, Equatable, Sendable {
    var content: LetterContent
    /// The step the author was on, where the composer opens again.
    var step: LetterComposerStep = .note
    /// The last send that started and was not seen to finish. It is saved before the request
    /// goes out and stays until the server is seen to have the letter, so every later send of
    /// this draft carries the same letter id and the server stores the letter once.
    var pendingSend: LetterSend?

    /// The send to make now. A draft that started a send keeps that send's letter id, even when
    /// the letter changed since, as when a set time that passed was moved. An operation is reused
    /// while its part of the letter is unchanged and is new otherwise, because the server refuses
    /// an operation sent again with another request.
    func nextSend(makeOperation: () -> SyncClientOperation) -> LetterSend {
        guard let pendingSend else {
            return LetterSend(
                id: UUID(),
                content: content,
                operations: LetterSendOperations(
                    reserve: makeOperation(), finalize: makeOperation(), send: makeOperation()
                )
            )
        }
        if pendingSend.content == content { return pendingSend }
        let samePhoto = pendingSend.content.photo == content.photo
        let operations = pendingSend.operations
        return LetterSend(
            id: pendingSend.id,
            content: content,
            operations: LetterSendOperations(
                reserve: samePhoto ? operations.reserve : makeOperation(),
                finalize: samePhoto ? operations.finalize : makeOperation(),
                send: makeOperation()
            )
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
