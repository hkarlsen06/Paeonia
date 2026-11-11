import Foundation
import Observation

/// What came of tapping Send.
enum LetterSendOutcome: Equatable {
    /// The server has the letter. Nil when its author deleted it before a retry arrived.
    case sent(Letter?)
    case failed(MailError)
    /// Nothing to send, or a send is already running.
    case ignored
}

/// The letter this person is writing, and its send. It is the only writer of the stored draft.
///
/// The draft is read from the phone once per account and couple, and memory is the source
/// after that, so a refresh never brings back a letter that was sent or thrown away. Every
/// change is written in the order it was made, through one chain of writes, and each write
/// carries the draft generation the draft was read in, so a late write never lands after a
/// privacy purge. Editing stops while a send runs.
@Observable
final class LetterComposer {
    private(set) var draft: LetterDraft?
    /// The picked photo, compressed once. Nil without a photo, or when its file was lost.
    private(set) var photo: Data?
    private(set) var isSending = false
    private(set) var isPreparingPhoto = false
    /// True after a set time that had passed was moved forward, until the author picks again.
    private(set) var movedPastTime = false
    /// The letter this composer last saw reach the server, by a send or in the sent list.
    private(set) var sentLetterID: UUID?

    @ObservationIgnored private let cache: any MailCaching
    @ObservationIgnored private let gateway: (any MailGateway)?
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var loads = 0
    @ObservationIgnored private var lastWrite: Task<Bool, Never>?

    /// The account a draft was read for, and the draft generation it was read in.
    private struct Session: Equatable {
        let ownerUserID: UUID
        let generation: Int
        let load: Int
    }

    init(cache: any MailCaching, gateway: (any MailGateway)?, operationProvider: any SyncClientOperationProviding) {
        self.cache = cache
        self.gateway = gateway
        self.operationProvider = operationProvider
    }

    /// The draft has a photo that could not be read back, so Send stops until it is picked again or removed.
    var isPhotoMissing: Bool {
        draft?.content.photo != nil && photo == nil
    }

    /// Reads the stored draft of `ownerUserID`, after the writes still queued.
    func load(ownerUserID: UUID?) async {
        loads += 1
        let load = loads
        session = nil
        draft = nil
        photo = nil
        movedPastTime = false
        guard let ownerUserID else { return }
        _ = await lastWrite?.value
        let stored = await cache.storedDraft(ownerUserID: ownerUserID)
        guard load == loads else { return }
        session = Session(ownerUserID: ownerUserID, generation: stored.generation, load: load)
        draft = stored.draft
        photo = stored.photo
    }

    /// Reads the draft again when drafts were purged since it was read, as when the couple
    /// changed just before a leave purge ran.
    func reloadIfPurged() async {
        guard let session, await cache.draftGeneration != session.generation, self.session == session else { return }
        await load(ownerUserID: session.ownerUserID)
    }

    // MARK: Writing

    /// Starts a letter on `template`, or moves the one being written onto it. A note the
    /// author changed stays, otherwise the new card's first line replaces the old one.
    func choose(_ template: LetterTemplate) {
        guard !isSending else { return }
        guard var current = draft else {
            change(LetterDraft(content: LetterContent(templateKey: template.key, body: template.startingBody)))
            return
        }
        let previous = LetterTemplate(current.content.templateKey)
        if current.content.trimmedBody.isEmpty || current.content.body == previous.startingBody {
            current.content.body = template.startingBody
        }
        current.content.templateKey = template.key
        change(current)
    }

    func updateBody(_ body: String) {
        guard !isSending, var current = draft else { return }
        current.content.body = LetterBody.limited(body)
        change(current)
    }

    func updateStep(_ step: LetterComposerStep) {
        guard !isSending, var current = draft, current.step != step else { return }
        current.step = step
        change(current)
    }

    func updateDelivery(_ delivery: LetterDelivery) {
        guard !isSending, var current = draft else { return }
        current.content.delivery = delivery
        movedPastTime = false
        change(current)
    }

    /// Compresses `data` and attaches it. Its bytes are written once, before the draft that
    /// names them. False when the photo cannot be read as an image.
    func pickPhoto(_ data: Data) async -> Bool {
        guard !isSending, draft != nil else { return false }
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        guard let compressed = await Self.compress(data) else { return false }
        guard !isSending, var current = draft else { return false }
        let picked = LetterPhoto(
            id: UUID(),
            mimeType: compressed.mediaType,
            fileExtension: compressed.fileExtension,
            width: compressed.width,
            height: compressed.height
        )
        current.content.photo = picked
        enqueue { cache, owner, generation in
            await cache.saveDraftPhoto(compressed.data, id: picked.id, ownerUserID: owner, ifGeneration: generation)
        }
        photo = compressed.data
        change(current)
        return true
    }

    func removePhoto() {
        guard !isSending, var current = draft else { return }
        current.content.photo = nil
        photo = nil
        change(current)
    }

    func discard() {
        guard !isSending else { return }
        draft = nil
        photo = nil
        movedPastTime = false
        persist(nil)
    }

    /// A set time that has passed moves to an hour from now, and `movedPastTime` says so.
    /// True when it moved.
    @discardableResult
    func moveTimeIfPassed(now: Date = .now) -> Bool {
        guard !isSending, var current = draft, case let .at(date) = current.content.delivery, date <= now else {
            return false
        }
        current.content.delivery = .at(now.addingTimeInterval(3_600))
        movedPastTime = true
        change(current)
        return true
    }

    /// Forgets a draft whose pending send the server has, as after the answer was lost or the
    /// app closed before it came. The letter went out, so edits made since go with the draft.
    func forgetSent(_ sentIDs: Set<UUID>) {
        guard !isSending, let pending = draft?.pendingSend, sentIDs.contains(pending.id) else { return }
        finishSend(pending.id)
    }

    // MARK: Sending

    /// Sends the letter being written to the couple `coupleID`. The send's letter id and
    /// operations reach the phone's storage before the request, so trying again, also after
    /// the app closed, sends the same letter and the server stores it once.
    func send(coupleID: UUID?, now: Date = .now) async -> LetterSendOutcome {
        guard !isSending, var current = draft, current.content.canSend else { return .ignored }
        if moveTimeIfPassed(now: now) { return .failed(.timePassed) }
        guard let session, let coupleID, let gateway else { return .failed(.sendFailed) }
        var media: MemoryUploadMedia?
        if let picked = current.content.photo {
            guard let photo else { return .failed(.photoMissing) }
            media = MemoryUploadMedia(
                data: photo,
                purpose: .letter,
                mimeType: picked.mimeType,
                fileExtension: picked.fileExtension,
                width: picked.width,
                height: picked.height
            )
        }
        isSending = true
        defer { isSending = false }
        current.pendingSend = current.nextSend(makeOperation: operationProvider.makeOperation)
        draft = current
        guard await persist(current).value, let attempt = current.pendingSend else { return .failed(.sendFailed) }
        do {
            let letter = try await gateway.send(attempt, photo: media, coupleID: coupleID)
            if self.session == session { finishSend(attempt.id) }
            return .sent(letter)
        } catch {
            return .failed(MailError(sending: error))
        }
    }

    private func finishSend(_ letterID: UUID) {
        draft = nil
        photo = nil
        movedPastTime = false
        sentLetterID = letterID
        persist(nil)
    }

    // MARK: Storage

    private func change(_ updated: LetterDraft) {
        draft = updated
        persist(updated)
    }

    @discardableResult
    private func persist(_ draft: LetterDraft?) -> Task<Bool, Never> {
        enqueue { cache, owner, generation in
            await cache.saveDraft(draft, ownerUserID: owner, ifGeneration: generation)
        }
    }

    /// Runs `write` after every write queued before it. A write refused because drafts were
    /// purged since the draft was read makes the composer read the phone's draft again.
    @discardableResult
    private func enqueue(
        _ write: @escaping @Sendable (any MailCaching, UUID, Int) async -> Bool
    ) -> Task<Bool, Never> {
        guard let session else { return Task { false } }
        let previous = lastWrite
        let cache = cache
        let task = Task {
            _ = await previous?.value
            if await write(cache, session.ownerUserID, session.generation) { return true }
            if await cache.draftGeneration != session.generation, self.session == session {
                Task { await self.load(ownerUserID: session.ownerUserID) }
            }
            return false
        }
        lastWrite = task
        return task
    }

    /// Compressing a camera photo takes a moment, so it runs off the main actor.
    @concurrent
    private nonisolated static func compress(_ data: Data) async -> ImageCompressor.CompressedImage? {
        ImageCompressor.compress(data)
    }
}
