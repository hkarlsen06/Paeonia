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
    /// The photo a sent letter already has on the server, kept as it is while the letter is
    /// changed. Never set together with `photo`, which replaces it.
    var storedPhotoID: UUID?

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

    /// Whether `letter`, as its author reads it from the server, holds what the author made
    /// here: the card, the note, and a photo or none. A letter an earlier try already stored
    /// keeps what that try sent. When it arrives is left out on purpose. The server and the app
    /// both move a set time that has passed, and a letter that went at another time lost
    /// nothing the author wrote.
    func matches(_ letter: Letter) -> Bool {
        letter.templateKey == templateKey && letter.body == trimmedBody
            && (letter.mediaAssetID != nil) == (photo != nil)
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
    var changing: UUID?
    /// True once the author picked when the letter arrives, so a default never moves it again.
    var deliveryIsChosen = false
    /// The letter being changed waits for the next meeting, so keeping that needs no new check.
    var keepsMeeting = false
    /// A save of this change may have reached the server, but no answer said so. The letter may
    /// already hold it, so discarding the change cannot promise the letter stays as it was.
    var unconfirmed = false

    /// The send to make now. A draft that started a send keeps that send's letter id, even when
    /// the letter changed since, as when a set time that passed was moved. An operation is reused
    /// while its part of the letter is unchanged and is new otherwise, because the server refuses
    /// an operation sent again with another request.
    func nextSend(makeOperation: () -> SyncClientOperation) -> LetterSend {
        guard let pendingSend else {
            return LetterSend(
                id: changing ?? UUID(),
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

nonisolated extension LetterDraft {
    /// A change to `letter`, which this person sent and which has not arrived, starting from
    /// what it says now. Nil for a letter that arrived or that this phone cannot read.
    init?(changing letter: Letter) {
        guard letter.state == .sealed, let templateKey = letter.templateKey, let body = letter.body,
              let kind = letter.deliveryKind
        else { return nil }
        var content = LetterContent(templateKey: templateKey, body: body)
        content.storedPhotoID = letter.mediaAssetID
        switch kind {
        case .now:
            content.delivery = .now
        case .morning:
            content.delivery = .morning
        case .together:
            content.delivery = .together
        case .at:
            guard let deliverAt = letter.deliverAt else { return nil }
            content.delivery = .at(deliverAt)
        }
        self.init(content: content)
        changing = letter.id
        deliveryIsChosen = true
        keepsMeeting = kind == .together
    }

    /// Whether `letter`, the letter being changed as the server has it, already holds this change:
    /// the card, the note, and the kept photo or none. Only a change that was sent can have
    /// landed. A change with a newly picked photo is left to its next save, since a letter that
    /// still has the old photo looks the same.
    func landed(in letter: Letter) -> Bool {
        letter.id == changing && pendingSend != nil && content.photo == nil && content.matches(letter)
            && letter.mediaAssetID == content.storedPhotoID
    }

    /// When a birthday card arrives because its author has not picked a time, so the delivery
    /// step can name the day. Nil otherwise.
    var birthdayArrival: Date? {
        guard !deliveryIsChosen, content.templateKey == .birthday, case let .at(date) = content.delivery else {
            return nil
        }
        return date
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
