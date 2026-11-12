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

/// The Mail sheet, the mailbox with `path` pushed on top. Each request is its own value, so
/// asking for the same letter twice opens it twice.
struct MailPresentation: Identifiable {
    let id = UUID()
    var path: [MailRoute] = []
    var tab: MailboxTab = .received
}

/// A problem to tell the person about. Each one is new, so the same problem twice shows twice.
struct MailNotice: Identifiable, Equatable {
    let id = UUID()
    let error: MailError
}

/// This person's Mail for the Mail card and the mailbox, and the letter they are writing.
///
/// The waiting letters and the newest page of each list come from the cache, so both show
/// offline. Older pages load while the mailbox is open and go when it closes. Sending and
/// opening need a connection. A letter's photo stays on this phone only while the letter is
/// on one of its lists.
@Observable
final class MailViewModel {
    private(set) var snapshot = MailSnapshot()
    /// The lists as the mailbox shows them, with the older pages loaded so far.
    private(set) var lists: [MailboxTab: MailPage] = [:]
    private(set) var loadingOlder: Set<MailboxTab> = []
    /// What the composer's delivery step offers. Nil until the composer read it.
    private(set) var deliveryOptions: MailDeliveryOptions?
    /// Why the last read of the delivery options failed. Nil once one succeeds.
    private(set) var deliveryOptionsFailure: PaeoniaFailure?
    private(set) var openingLetterID: UUID?
    private(set) var notice: MailNotice?
    var presentation: MailPresentation? {
        didSet {
            if presentation?.id != oldValue?.id { pendingLetterID = nil }
            if presentation == nil, oldValue != nil { dropOlderPages() }
        }
    }

    let composer: LetterComposer

    @ObservationIgnored private let cache: any MailCaching
    /// Nil when the server client can't be set up (previews), so a send reports a failure.
    @ObservationIgnored private let gateway: (any MailGateway)?
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private let evictPhotos: @Sendable ([UUID]) async -> Void
    @ObservationIgnored private var ownerUserID: UUID?
    @ObservationIgnored private var coupleID: UUID?
    @ObservationIgnored private var reloadGeneration = 0
    /// A letter a push or link asked for before this phone had it. It opens when it arrives.
    @ObservationIgnored private var pendingLetterID: UUID?
    #if DEBUG
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Mail"
    )
    #endif

    private static let olderPageSize = 25

    init(
        cache: (any MailCaching)? = nil,
        gateway: (any MailGateway)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        evictPhotos: (@Sendable ([UUID]) async -> Void)? = nil
    ) {
        let cache = cache ?? FileMailCache.shared
        let gateway = gateway ?? (try? LiveMailGateway.live())
        let operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.cache = cache
        self.gateway = gateway
        self.operationProvider = operationProvider
        self.evictPhotos = evictPhotos ?? MailLetterPhotoCache.evict
        composer = LetterComposer(cache: cache, gateway: gateway, operationProvider: operationProvider)
    }

    func list(_ tab: MailboxTab) -> MailPage {
        lists[tab] ?? snapshot[tab]
    }

    var received: [Letter] { list(.received).letters }
    var sent: [Letter] { list(.sent).letters }
    /// Letters that arrived and wait to be opened, oldest first. The Us tab badge counts them.
    var waiting: [Letter] { MailTimeline.waiting(snapshot.waiting, for: ownerUserID) }

    func letter(id: UUID) -> Letter? {
        received.first { $0.id == id } ?? sent.first { $0.id == id } ?? snapshot.waiting.first { $0.id == id }
    }

    func present(_ presentation: MailPresentation = MailPresentation()) {
        self.presentation = presentation
    }

    /// Opens Mail for a push or link, on `letterID` when this phone has it. Otherwise the
    /// mailbox shows, and the letter opens over it when the live feed brings it. False when a
    /// newer link took over meanwhile.
    func presentLink(_ letterID: UUID?, isCurrent: () -> Bool) async -> Bool {
        await reload()
        guard isCurrent() else { return false }
        let known = letterID.flatMap(letter(id:))
        present(MailPresentation(path: known.map { [.reader($0.id)] } ?? []))
        if known == nil { pendingLetterID = letterID }
        return true
    }

    func configure(ownerUserID: UUID?, coupleID: UUID?) async {
        // The first account needs no reset, so a sheet asked for before it keeps showing.
        if self.ownerUserID != nil, self.ownerUserID != ownerUserID {
            snapshot = MailSnapshot()
            lists = [:]
            deliveryOptions = nil
            deliveryOptionsFailure = nil
            notice = nil
            presentation = nil
        }
        self.ownerUserID = ownerUserID
        self.coupleID = coupleID
        await composer.load(ownerUserID: ownerUserID)
        await reload()
    }

    /// A couple that arrives after launch keeps a sheet a push opened. A change of couple closes
    /// it and reads the letter being written again, which a privacy purge may have removed.
    func updateCoupleID(_ coupleID: UUID?) async {
        guard self.coupleID != coupleID else { return }
        let hadCouple = self.coupleID != nil
        self.coupleID = coupleID
        guard hadCouple else { return }
        presentation = nil
        deliveryOptions = nil
        deliveryOptionsFailure = nil
        await composer.load(ownerUserID: ownerUserID)
    }

    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .mail) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await reload()
        }
    }

    /// Reads the cache again. The letter being written is the composer's, which reads it again
    /// only after a purge.
    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        guard let ownerUserID else {
            snapshot = MailSnapshot()
            lists = [:]
            return
        }
        let stored = await cache.snapshot(ownerUserID: ownerUserID)
        guard generation == reloadGeneration, self.ownerUserID == ownerUserID else { return }
        snapshot = stored
        for tab in Array(lists.keys) {
            lists[tab] = MailTimeline.merged(stored[tab], keeping: lists[tab] ?? stored[tab], in: tab)
        }
        await composer.reloadIfPurged()
        if case .sentWithoutLastChanges = composer.forgetSent(stored.sent.letters) { post(.changesNotAdded) }
        if let pendingLetterID, letter(id: pendingLetterID) != nil, presentation != nil {
            presentation?.path.append(.reader(pendingLetterID))
            self.pendingLetterID = nil
        }
        await evictPhotosNoLongerShown()
    }

    /// Loads the page after the last letter of `tab` the mailbox shows.
    func loadOlder(_ tab: MailboxTab) async {
        guard let before = list(tab).nextBefore, let gateway, !loadingOlder.contains(tab) else { return }
        loadingOlder.insert(tab)
        defer { loadingOlder.remove(tab) }
        do {
            let page = try await gateway.olderLetters(in: tab, before: before, limit: Self.olderPageSize)
            // The list as it is now, since a letter on it may have changed during the request.
            let latest = list(tab)
            guard latest.nextBefore == before else { return }
            let shown = Set(latest.letters.map(\.id))
            lists[tab] = MailPage(
                letters: latest.letters + page.letters.filter { !shown.contains($0.id) },
                nextBefore: page.nextBefore
            )
            await evictPhotosNoLongerShown()
        } catch {
            post(PaeoniaFailure(error) == .offline ? .loadOffline : .loadFailed)
        }
    }

    /// Reads what the delivery step offers. Without it the morning option shows no time, and the
    /// option for the next meeting shows only on a draft that already chose it, which can't be
    /// sent until a read succeeds. A failed read drops the options read before, since the server
    /// may have just refused them.
    func loadDeliveryOptions() async {
        guard let gateway else { return }
        do {
            deliveryOptions = try await gateway.deliveryOptions(at: .now)
            deliveryOptionsFailure = nil
        } catch {
            deliveryOptions = nil
            deliveryOptionsFailure = PaeoniaFailure(error)
        }
    }

    // MARK: Reading

    /// Opens a letter this person received. Returns it with its note and photo, or nil and
    /// posts a notice when it could not be opened.
    func open(_ letter: Letter) async -> Letter? {
        if letter.state == .opened { return letter }
        guard letter.recipientUserID == ownerUserID, openingLetterID == nil, let gateway else { return nil }
        openingLetterID = letter.id
        defer { openingLetterID = nil }
        let stamp = await writeStamp()
        do {
            let opened = try await gateway.open(id: letter.id)
            await save(stamp: stamp) { snapshot in
                snapshot.waiting.removeAll { $0.id == opened.id }
                if let index = snapshot.received.letters.firstIndex(where: { $0.id == opened.id }) {
                    snapshot.received.letters[index] = opened
                }
            }
            replaceShown(opened)
            return opened
        } catch {
            #if DEBUG
            logger.error("Opening a letter failed: \(String(describing: error))")
            #endif
            let failure = MailError(opening: error)
            if failure == .letterGone {
                await forget(letter.id, stamp: stamp)
            }
            post(failure)
            return nil
        }
    }

    /// Deletes one of this person's letters for both partners. A sealed one is unsent.
    func delete(_ letter: Letter) async -> Bool {
        guard letter.authorUserID == ownerUserID, let gateway else { return false }
        let stamp = await writeStamp()
        do {
            try await gateway.delete(id: letter.id, operation: operationProvider.makeOperation())
            await forget(letter.id, stamp: stamp)
            return true
        } catch {
            post(PaeoniaFailure(error) == .offline ? .deleteOffline : .deleteFailed)
            return false
        }
    }

    // MARK: Notices

    func post(_ error: MailError) {
        notice = MailNotice(error: error)
    }

    /// The notice `id`, once. Whichever Mail screen is showing takes it.
    func takeNotice(_ id: UUID) -> MailError? {
        guard let notice, notice.id == id else { return nil }
        self.notice = nil
        return notice.error
    }

    // MARK: Storage

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

    /// Takes a letter that is gone off every list on this phone.
    private func forget(_ letterID: UUID, stamp: WriteStamp) async {
        for tab in Array(lists.keys) {
            lists[tab]?.letters.removeAll { $0.id == letterID }
        }
        await save(stamp: stamp) { snapshot in
            snapshot.waiting.removeAll { $0.id == letterID }
            snapshot.received.letters.removeAll { $0.id == letterID }
            snapshot.sent.letters.removeAll { $0.id == letterID }
        }
        await evictPhotosNoLongerShown()
    }

    private func replaceShown(_ letter: Letter) {
        for tab in Array(lists.keys) {
            guard let index = lists[tab]?.letters.firstIndex(where: { $0.id == letter.id }) else { continue }
            lists[tab]?.letters[index] = letter
        }
    }

    private func dropOlderPages() {
        lists = [:]
        Task { await evictPhotosNoLongerShown() }
    }

    /// Records the photos of every letter on a list, the older pages too, and removes from this
    /// phone the ones whose letter left every list.
    private func evictPhotosNoLongerShown() async {
        guard let ownerUserID else { return }
        let lettersShown = snapshot.letters + lists.values.flatMap(\.letters)
        let gone = await cache.trackPhotos(Set(lettersShown.compactMap(\.mediaAssetID)), ownerUserID: ownerUserID)
        if !gone.isEmpty { await evictPhotos(Array(gone)) }
    }
}

// MARK: Sending

extension MailViewModel {
    /// Sends the letter being written. Posts a notice when it was not sent, and the letter
    /// stays as it was, so trying again sends the same one. The composer's `sentLetterID`
    /// tells the screen it went. Also posts a notice when the letter had already gone without
    /// the author's last changes, which stay in the composer as a new letter.
    func send() async {
        let stamp = await writeStamp()
        var outcome = await composer.send(coupleID: coupleID)
        if case .failed = outcome {
            // A lost answer is not a lost letter. The live feed may have shown it while the send ran.
            let seen = composer.forgetSent(snapshot.sent.letters)
            if seen != .ignored { outcome = seen }
        }
        switch outcome {
        case let .sent(letter):
            guard let letter else { return }
            await storeSent(letter, stamp: stamp)
        case let .sentWithoutLastChanges(letter):
            await storeSent(letter, stamp: stamp)
            post(.changesNotAdded)
        case let .failed(error):
            #if DEBUG
            logger.error("Sending a letter failed: \(String(describing: error))")
            #endif
            post(error)
            // The delivery step then says why the next meeting can't be picked now.
            if error == .meetingUnavailable { await loadDeliveryOptions() }
        case .ignored:
            break
        }
    }

    private func storeSent(_ letter: Letter, stamp: WriteStamp) async {
        await save(stamp: stamp) { snapshot in
            snapshot.sent.letters.removeAll { $0.id == letter.id }
            snapshot.sent.letters.insert(letter, at: 0)
        }
    }

    /// Attaches a photo the picker loaded, or tells the person it could not be read.
    func pickPhoto(_ data: Data?) async {
        guard let data, await composer.pickPhoto(data) else {
            post(.photoUnreadable)
            return
        }
    }
}
