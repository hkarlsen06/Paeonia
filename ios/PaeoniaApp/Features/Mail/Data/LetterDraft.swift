import Foundation

/// What a letter says and when it arrives, as the composer builds it.
nonisolated struct LetterContent: Codable, Equatable, Sendable {
    var templateKey: LetterTemplate.Key
    var body: String
    var delivery: LetterDelivery = .now
    /// A new id each time a different photo is picked. Nil without a photo.
    var photoID: UUID?

    init(templateKey: LetterTemplate.Key, body: String) {
        self.templateKey = templateKey
        self.body = body
    }

    var trimmedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSend: Bool {
        !trimmedBody.isEmpty && trimmedBody.count <= Letter.maxBodyLength
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

/// The letter being written. The phone keeps it until it is sent, so closing the composer
/// or a failed send loses nothing.
nonisolated struct LetterDraft: Codable, Equatable, Sendable {
    var content: LetterContent
    /// The send that failed last. Trying again with the same content sends it again, so the
    /// server stores it once even if its first answer was lost.
    var failedSend: LetterSend?

    func nextSend(makeOperation: () -> SyncClientOperation) -> LetterSend {
        if let failedSend, failedSend.content == content { return failedSend }
        return LetterSend(
            id: UUID(),
            content: content,
            operations: LetterSendOperations(reserve: makeOperation(), finalize: makeOperation(), send: makeOperation())
        )
    }
}
