import Foundation
import Observation

/// What came of tapping Send.
enum LetterSendOutcome: Equatable {
    /// The server has the letter. Nil when its author deleted it before a retry arrived.
    case sent(Letter?)
    /// The server has the letter from an earlier try whose answer was lost, so it lacks what
    /// the author changed since. The draft stays as a new letter with those changes, and the
    /// author is told.
    case sentWithoutLastChanges(Letter)
    /// The letter being changed had arrived or been unsent, so the change was not saved. The
    /// draft stays as a new letter with everything the author wrote, and the author is told.
    case notChanged(MailError)
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
    /// author changed stays, otherwise the new card's first line replaces the old one. A time
    /// the author did not pick goes back to now, and the delivery step sets the new card's.
    func choose(_ template: LetterTemplate) {
        guard !isSending else { return }
        guard var current = draft else {
            startDraft(LetterDraft(content: LetterContent(templateKey: template.key, body: template.startingBody)))
            return
        }
        let previous = LetterTemplate(current.content.templateKey)
        if current.content.trimmedBody.isEmpty || current.content.body == previous.startingBody {
            current.content.body = template.startingBody
        }
        current.content.templateKey = template.key
        if !current.deliveryIsChosen { current.content.delivery = .now }
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
        current.deliveryIsChosen = true
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
        current.content.storedPhotoID = nil
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
        current.content.storedPhotoID = nil
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

    /// A set time the author picked that has passed moves to an hour from now, and
    /// `movedPastTime` says so. True when it moved. A birthday time the author did not pick is
    /// left to `suggestDelivery`, or to Send, which sends it at once.
    @discardableResult
    func moveTimeIfPassed(now: Date = .now) -> Bool {
        guard !isSending, var current = draft, current.deliveryIsChosen, case let .at(date) = current.content.delivery,
              date <= now
        else { return false }
        current.content.delivery = .at(now.addingTimeInterval(3_600))
        movedPastTime = true
        change(current)
        return true
    }

    /// Settles a draft whose pending send is one of `sent`, the letters the server has, as after
    /// the answer was lost or the app closed before it came. The draft is forgotten when that
    /// letter says what the draft says. Otherwise it stays as a new letter. `.ignored` when no
    /// pending send is in `sent`, and while a picked photo is still being prepared, so the
    /// draft is not forgotten just before the photo joins it.
    @discardableResult
    func forgetSent(_ sent: [Letter]) -> LetterSendOutcome {
        guard !isSending, !isPreparingPhoto, let current = draft, current.changing == nil,
              let pending = current.pendingSend, let letter = sent.first(where: { $0.id == pending.id })
        else { return .ignored }
        let asItIsNow = LetterSend(id: pending.id, content: current.content, operations: pending.operations)
        return settle(asItIsNow, with: letter)
    }

    // MARK: Sending

    /// Sends the letter being written to the couple `coupleID`. The send's letter id and
    /// operations reach the phone's storage before the request, so trying again, also after
    /// the app closed, sends the same letter and the server stores it once.
    func send(coupleID: UUID?, now: Date = .now) async -> LetterSendOutcome {
        guard !isSending, var current = draft, current.content.canSend else { return .ignored }
        if let passed = timePassed(now: now) { return .failed(passed) }
        guard let session, let coupleID, let gateway else { return .failed(.sendFailed) }
        if current.content.photo != nil, photo == nil { return .failed(.photoMissing) }
        let media = uploadMedia(for: current.content.photo)
        isSending = true
        defer { isSending = false }
        let isRetry = current.pendingSend != nil
        current.pendingSend = current.nextSend(makeOperation: operationProvider.makeOperation)
        draft = current
        guard await persist(current).value, let attempt = current.pendingSend else { return .failed(.sendFailed) }
        if current.changing != nil {
            return await sendChange(attempt, photo: media, coupleID: coupleID, gateway: gateway, session: session)
        }
        do {
            let letter = try await gateway.send(attempt, photo: media, coupleID: coupleID)
            guard self.session == session else { return .sent(letter) }
            return settle(attempt, isRetry: isRetry, with: letter)
        } catch {
            return .failed(MailError(sending: error))
        }
    }

    /// Ends the send `attempt` now that the server has `letter` under its id. When the letter
    /// says what the draft says, the draft is forgotten. When an earlier try stored it without
    /// the author's later changes, the draft stays without its pending send, so the next Send
    /// makes a new letter and nothing the author wrote is lost. Only a retry can meet a letter
    /// an earlier try stored.
    private func settle(_ attempt: LetterSend, isRetry: Bool = true, with letter: Letter?) -> LetterSendOutcome {
        guard isRetry, let letter, !attempt.content.matches(letter) else {
            finishSend(attempt.id)
            return .sent(letter)
        }
        if var current = draft {
            current.pendingSend = nil
            change(current)
        }
        return .sentWithoutLastChanges(letter)
    }

    private func uploadMedia(for picked: LetterPhoto?) -> MemoryUploadMedia? {
        guard let picked, let photo else { return nil }
        return MemoryUploadMedia(
            data: photo,
            purpose: .letter,
            mimeType: picked.mimeType,
            fileExtension: picked.fileExtension,
            width: picked.width,
            height: picked.height
        )
    }

    /// `sentLetterID` names only a letter that the draft being written sent.
    private func startDraft(_ new: LetterDraft) {
        movedPastTime = false
        sentLetterID = nil
        change(new)
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

// MARK: Defaults and changes to a sent letter

extension LetterComposer {
    /// Sets when the letter arrives until the author picks it: a birthday card on the partner's
    /// next birthday morning when their birthday is saved, and now otherwise. A birthday card
    /// waits for the partner's time zone before it moves.
    func suggestDelivery(partnerBirthday: String?, timeZone: TimeZone?, now: Date = .now) {
        guard !isSending, var current = draft, !current.deliveryIsChosen else { return }
        var suggested = LetterDelivery.now
        if current.content.templateKey == .birthday, let partnerBirthday {
            guard let timeZone else { return }
            suggested = LetterDelivery.birthdayMorning(partnerBirthday, in: timeZone, after: now) ?? .now
        }
        guard current.content.delivery != suggested else { return }
        current.content.delivery = suggested
        change(current)
    }

    /// Starts changing `letter`, which this person sent and which has not arrived. False while
    /// another letter is being written, which stays as it is, or before the stored draft was
    /// read. A change to the same letter goes on where it was.
    func startChange(of letter: Letter) -> Bool {
        guard !isSending, session != nil else { return false }
        if let current = draft { return current.changing == letter.id }
        guard let changing = LetterDraft(changing: letter) else { return false }
        startDraft(changing)
        return true
    }

    /// Settles a change from `sent`, the letters the server has. A change the letter already
    /// holds, as after a save whose answer was lost, is done. A change that was never sent, to a
    /// letter that arrived, stays as a new letter. A sent change to a letter that arrived without
    /// it is left to its next save, whose answer says whether it landed first.
    func settleChange(_ sent: [Letter]) -> LetterSendOutcome {
        guard !isSending, !isPreparingPhoto, let current = draft, let letterID = current.changing,
              let letter = sent.first(where: { $0.id == letterID })
        else { return .ignored }
        if current.landed(in: letter) {
            finishSend(letterID)
            return .sent(letter)
        }
        guard current.pendingSend == nil, letter.state != .sealed else { return .ignored }
        let failure = MailError.changeTooLate
        return .notChanged(keepAsNewLetter() ? failure.withPhotoLeftBehind : failure)
    }

    /// Ends the change to `letter` once its author unsent it. A change with nothing new goes, and
    /// one with new words or a new photo stays as a new letter.
    func endChange(of letter: Letter) {
        guard !isSending, let current = draft, current.changing == letter.id else { return }
        if LetterDraft(changing: letter)?.content == current.content {
            discard()
        } else {
            keepAsNewLetter()
        }
    }

    /// Puts `photoID`, the photo the letter has now, in place of a kept photo another phone
    /// replaced or removed since the change started. Nil leaves the change without a photo.
    func keepLetterPhoto(_ photoID: UUID?) {
        guard !isSending, var current = draft, current.changing != nil, current.content.photo == nil else { return }
        current.content.storedPhotoID = photoID
        change(current)
    }

    /// The reason Send stops when the time has passed, after moving it: a picked time moves an
    /// hour ahead, and a birthday time a default set now goes at once, which the author confirms
    /// by sending again.
    private func timePassed(now: Date) -> MailError? {
        if moveTimeIfPassed(now: now) { return .timePassed }
        guard var current = draft, !current.deliveryIsChosen, case let .at(date) = current.content.delivery,
              date <= now
        else { return nil }
        current.content.delivery = .now
        current.deliveryIsChosen = true
        change(current)
        return .birthdayPassed
    }

    /// Saves the change `attempt` to a letter that has not arrived. The answer, also a replay's,
    /// says the change landed, whatever the letter says now. A letter that arrived or was unsent
    /// first leaves the draft as a new letter.
    private func sendChange(
        _ attempt: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID, gateway: any MailGateway, session: Session
    ) async -> LetterSendOutcome {
        do {
            let letter = try await gateway.change(attempt, photo: photo, coupleID: coupleID)
            guard self.session == session else { return .sent(letter) }
            return settle(attempt, isRetry: false, with: letter)
        } catch {
            guard self.session == session else { return .failed(MailError(changing: error)) }
            return settleFailedChange(MailError(changing: error))
        }
    }

    /// A refusal because the letter arrived or was unsent leaves the change as a new letter. A
    /// save that may have landed is marked so, and keeps its operation, so saving again is a
    /// replay that the server stores once.
    private func settleFailedChange(_ failure: MailError) -> LetterSendOutcome {
        switch failure {
        case .changeTooLate, .changeLetterGone:
            return .notChanged(keepAsNewLetter() ? failure.withPhotoLeftBehind : failure)
        case .changeUnconfirmed, .changeUnconfirmedOffline:
            if var current = draft, !current.unconfirmed {
                current.unconfirmed = true
                change(current)
            }
            return .failed(failure)
        case .changePhotoChanged where draft?.content.storedPhotoID == nil:
            return .failed(.changeFailed)
        default:
            return .failed(failure)
        }
    }

    /// Turns a change that could not be saved into a new letter with the same card, note, new
    /// photo and time. A photo the old letter kept on the server stays with that letter. True
    /// when the change kept such a photo.
    @discardableResult
    private func keepAsNewLetter() -> Bool {
        guard var current = draft else { return false }
        let leftPhoto = current.content.storedPhotoID != nil
        current.changing = nil
        current.pendingSend = nil
        current.content.storedPhotoID = nil
        current.keepsMeeting = false
        current.unconfirmed = false
        change(current)
        return leftPhoto
    }
}
