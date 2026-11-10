import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// A screen inside the Mail sheet, over the mailbox.
enum MailRoute: Hashable {
    case reader(UUID)
    case composer
}

enum MailboxTab: Hashable {
    case received
    case sent
}

/// The Mail sheet: the mailbox, with `path` pushed on top. Each request is its own value,
/// so asking for the same letter twice opens it twice.
struct MailPresentation: Identifiable {
    let id = UUID()
    var path: [MailRoute] = []
    var tab: MailboxTab = .received
}

/// The couple's letters for the Mail card and the mailbox, and the letter this person is writing.
///
/// `letters` is the cached server list, so both show offline. Sending and opening need a
/// connection. A letter being written stays on the phone until it is sent, so a failed send
/// or a closed composer loses nothing.
@Observable
final class MailViewModel {
    private(set) var letters: [Letter] = []
    /// The zone the partner's morning letters follow, from the server.
    private(set) var partnerTimeZone: TimeZone?
    private(set) var draft: LetterDraft?
    private(set) var draftPhoto: Data?
    private(set) var isSending = false
    private(set) var openingLetterID: UUID?
    private(set) var error: MailError?
    var presentation: MailPresentation?

    @ObservationIgnored private let cache: any MailCaching
    /// Nil when the server client can't be set up (previews), so a send reports a failure.
    @ObservationIgnored private let gateway: (any MailGateway)?
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private var ownerUserID: UUID?
    @ObservationIgnored private var coupleID: UUID?
    @ObservationIgnored private var reloadGeneration = 0
    #if DEBUG
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Mail"
    )
    #endif

    init(
        cache: (any MailCaching)? = nil,
        gateway: (any MailGateway)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.cache = cache ?? FileMailCache.shared
        self.gateway = gateway ?? (try? LiveMailGateway.live())
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    var received: [Letter] { MailTimeline.received(letters, by: ownerUserID) }
    var sent: [Letter] { MailTimeline.sent(letters, by: ownerUserID) }
    /// Letters that arrived and wait to be opened, oldest first. The Us tab badge counts them.
    var waiting: [Letter] { MailTimeline.waiting(letters, for: ownerUserID) }

    func letter(id: UUID) -> Letter? {
        letters.first { $0.id == id }
    }

    func present(_ presentation: MailPresentation = MailPresentation()) {
        self.presentation = presentation
    }

    /// Opens Mail for a push or link: on `letterID` when this phone has it, otherwise on the
    /// mailbox, where the live feed brings it. False when a newer link took over meanwhile.
    func presentLink(_ letterID: UUID?, isCurrent: () -> Bool) async -> Bool {
        await reload()
        guard isCurrent() else { return false }
        let letter = letterID.flatMap(letter(id:))
        present(MailPresentation(path: letter.map { [.reader($0.id)] } ?? []))
        return true
    }

    func configure(ownerUserID: UUID?, coupleID: UUID?) async {
        // The first account needs no reset, so a sheet asked for before it keeps showing.
        if self.ownerUserID != nil, self.ownerUserID != ownerUserID {
            letters = []
            draft = nil
            draftPhoto = nil
            presentation = nil
        }
        self.ownerUserID = ownerUserID
        self.coupleID = coupleID
        await reload()
    }

    func updateCoupleID(_ coupleID: UUID?) {
        if self.coupleID != coupleID { presentation = nil }
        self.coupleID = coupleID
    }

    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .mail) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await reload()
        }
    }

    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        guard let ownerUserID else {
            letters = []
            return
        }
        let snapshot = await cache.snapshot(ownerUserID: ownerUserID)
        let storedDraft = await cache.draft(ownerUserID: ownerUserID)
        let storedPhoto = await cache.draftPhoto(ownerUserID: ownerUserID)
        guard generation == reloadGeneration, self.ownerUserID == ownerUserID else { return }
        letters = snapshot.letters
        partnerTimeZone = snapshot.partnerTimeZoneID.flatMap(TimeZone.init(identifier:))
        if draft == nil {
            draft = storedDraft
            draftPhoto = storedDraft?.content.photoID == nil ? nil : storedPhoto
        }
    }

    // MARK: Writing

    /// Starts a letter on `template`, or moves the one being written onto it. A note the
    /// author changed stays, otherwise the new card's first line replaces the old one.
    func choose(_ template: LetterTemplate) {
        guard var current = draft else {
            let content = LetterContent(templateKey: template.key, body: template.startingBody)
            updateDraft(LetterDraft(content: content), photo: nil)
            return
        }
        let previous = LetterTemplate(current.content.templateKey)
        if current.content.trimmedBody.isEmpty || current.content.body == previous.startingBody {
            current.content.body = template.startingBody
        }
        current.content.templateKey = template.key
        updateDraft(current, photo: draftPhoto)
    }

    func updateBody(_ body: String) {
        guard var current = draft else { return }
        current.content.body = String(body.prefix(Letter.maxBodyLength))
        updateDraft(current, photo: draftPhoto)
    }

    func updateDelivery(_ delivery: LetterDelivery) {
        guard var current = draft else { return }
        current.content.delivery = delivery
        updateDraft(current, photo: draftPhoto)
    }

    /// Attaches `photo`, or removes the photo when nil. The bytes stay on the phone until the send.
    func updatePhoto(_ photo: Data?) {
        guard var current = draft else { return }
        current.content.photoID = photo == nil ? nil : UUID()
        updateDraft(current, photo: photo)
    }

    func discardDraft() {
        draft = nil
        draftPhoto = nil
        guard let ownerUserID else { return }
        Task { await cache.clearDraft(ownerUserID: ownerUserID) }
    }

    private func updateDraft(_ updated: LetterDraft, photo: Data?) {
        draft = updated
        draftPhoto = photo
        guard let ownerUserID else { return }
        Task {
            let generation = await cache.purgeGeneration
            await cache.saveDraft(updated, photo: photo, ownerUserID: ownerUserID, ifGeneration: generation)
        }
    }

    /// Sends the letter being written. Returns false and sets `error` when it could not be
    /// sent, and the letter stays as it was, so trying again sends the same one.
    func send() async -> Bool {
        guard !isSending, let current = draft, current.content.canSend else { return false }
        guard let ownerUserID, let coupleID, let gateway else {
            error = .sendFailed
            return false
        }
        isSending = true
        defer { isSending = false }
        let stamp = await writeStamp()
        let attempt = current.nextSend(makeOperation: operationProvider.makeOperation)
        var photo: MemoryUploadMedia?
        if let draftPhoto {
            guard let prepared = await Self.uploadMedia(draftPhoto) else {
                error = .photoUnreadable
                return false
            }
            photo = prepared
        }
        do {
            let letter = try await gateway.send(attempt, photo: photo, coupleID: coupleID)
            guard self.ownerUserID == ownerUserID else { return false }
            await finishSend(letter, ownerUserID: ownerUserID, stamp: stamp)
            return true
        } catch {
            #if DEBUG
            logger.error("Sending a letter failed: \(String(describing: error))")
            #endif
            var failed = current
            failed.failedSend = attempt
            if self.ownerUserID == ownerUserID { updateDraft(failed, photo: draftPhoto) }
            self.error = PaeoniaFailure(error) == .offline ? .sendOffline : .sendFailed
            return false
        }
    }

    /// Forgets the letter that was sent and shows it in the sent list at once, before the live feed brings it.
    private func finishSend(_ letter: Letter?, ownerUserID: UUID, stamp: WriteStamp) async {
        draft = nil
        draftPhoto = nil
        await cache.clearDraft(ownerUserID: ownerUserID)
        guard let letter else { return }
        await save(stamp: stamp) { snapshot in
            snapshot.letters.removeAll { $0.id == letter.id }
            snapshot.letters.insert(letter, at: 0)
        }
    }

    // MARK: Reading

    /// Opens a letter this person received. Returns it with its note and photo, or nil and
    /// sets `error` when it could not be opened.
    func open(_ letter: Letter) async -> Letter? {
        if letter.state == .opened { return letter }
        guard letter.recipientUserID == ownerUserID, openingLetterID == nil, let gateway else { return nil }
        openingLetterID = letter.id
        defer { openingLetterID = nil }
        let stamp = await writeStamp()
        do {
            let opened = try await gateway.open(id: letter.id)
            await save(stamp: stamp) { snapshot in
                guard let index = snapshot.letters.firstIndex(where: { $0.id == opened.id }) else { return }
                snapshot.letters[index] = opened
            }
            return opened
        } catch {
            #if DEBUG
            logger.error("Opening a letter failed: \(String(describing: error))")
            #endif
            if PaeoniaFailure(error) == .offline {
                self.error = .openOffline
            } else if String(describing: error).contains("letter is not available") {
                // Its author deleted it while it showed here.
                self.error = .letterGone
            } else {
                self.error = .openFailed
            }
            return nil
        }
    }

    /// Deletes one of this person's letters for both partners. A sealed one is unsent.
    func delete(_ letter: Letter) async -> Bool {
        guard letter.authorUserID == ownerUserID, let gateway else { return false }
        let stamp = await writeStamp()
        do {
            try await gateway.delete(id: letter.id, operation: operationProvider.makeOperation())
            await save(stamp: stamp) { snapshot in snapshot.letters.removeAll { $0.id == letter.id } }
            return true
        } catch {
            self.error = PaeoniaFailure(error) == .offline ? .deleteOffline : .deleteFailed
            return false
        }
    }

    func clearError() {
        error = nil
    }

    private struct WriteStamp {
        let ownerUserID: UUID?
        let generation: Int
    }

    private func writeStamp() async -> WriteStamp {
        WriteStamp(ownerUserID: ownerUserID, generation: await cache.purgeGeneration)
    }

    /// Writes a change this phone made into the cache, unless the account changed or a
    /// privacy purge ran since `stamp` was taken.
    private func save(stamp: WriteStamp, _ change: @escaping @Sendable (inout MailSnapshot) -> Void) async {
        guard let owner = stamp.ownerUserID, owner == ownerUserID else { return }
        guard await cache.update(ownerUserID: owner, ifGeneration: stamp.generation, change) else { return }
        LocalStoreChanges.post(.mail, ownerUserID: owner)
        await reload()
    }

    /// Compressing a camera photo takes a moment, so it runs off the main actor.
    @concurrent
    private nonisolated static func uploadMedia(_ photo: Data) async -> MemoryUploadMedia? {
        guard let compressed = ImageCompressor.compress(photo) else { return nil }
        return MemoryUploadMedia(
            data: compressed.data,
            purpose: .letter,
            mimeType: compressed.mediaType,
            fileExtension: compressed.fileExtension,
            width: compressed.width,
            height: compressed.height
        )
    }
}

nonisolated enum MailError: Equatable, Sendable {
    case sendOffline
    case sendFailed
    case photoUnreadable
    case openOffline
    case openFailed
    case letterGone
    case deleteOffline
    case deleteFailed

    var message: String {
        switch self {
        case .sendOffline: String(localized: .mailErrorSendOffline)
        case .sendFailed: String(localized: .mailErrorSendFailed)
        case .photoUnreadable: String(localized: .mailErrorPhotoUnreadable)
        case .openOffline: String(localized: .mailErrorOpenOffline)
        case .openFailed: String(localized: .mailErrorOpenFailed)
        case .letterGone: String(localized: .mailErrorLetterGone)
        case .deleteOffline: String(localized: .mailErrorDeleteOffline)
        case .deleteFailed: String(localized: .mailErrorDeleteFailed)
        }
    }
}
