import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// The couple's stories for the Home ring and the Stories archive in Memories, and both
/// partners' notes for the bubbles over the Home avatars.
///
/// `stories` is the cached server list, newest first, so both screens show it offline and
/// either partner's story arrives through the live feed. Posting and deleting need a
/// connection: the photo goes up first, and a failed post keeps the composer open so
/// nothing is lost. Opening the partner's story marks it seen on this phone at once and
/// tells the server in the background.
@MainActor
@Observable
final class StoriesViewModel {
    private(set) var stories: [Story] = []
    private(set) var notes: [StoryNote] = []
    private(set) var isSavingNote = false
    private(set) var isPosting = false
    private(set) var error: StoriesError?

    @ObservationIgnored private let cache: any StoriesCaching
    /// Nil when the server client can't be set up (previews), so posting reports a failure.
    @ObservationIgnored private let gateway: (any StoriesGateway)?
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ownerUserID: UUID?
    @ObservationIgnored private var coupleID: UUID?
    /// The last post that failed, so trying again sends the same story and the server
    /// runs it once even when the first answer was lost on the way back.
    @ObservationIgnored private var failedPost: FailedPost?
    /// Drops a reload that finished after a newer one started or the account changed.
    @ObservationIgnored private var reloadGeneration = 0
    #if DEBUG
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Stories"
    )
    #endif

    private static let hasPostedKey = "stories.hasPosted"

    init(
        cache: (any StoriesCaching)? = nil,
        gateway: (any StoriesGateway)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.cache = cache ?? FileStoriesCache.shared
        self.gateway = gateway ?? (try? LiveStoriesGateway.live())
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.defaults = defaults
    }

    /// False until this person has shared a story, so the composer explains how stories work once.
    var hasPostedBefore: Bool {
        defaults.bool(forKey: Self.hasPostedKey)
    }

    func configure(ownerUserID: UUID?, coupleID: UUID?) async {
        if self.ownerUserID != ownerUserID {
            stories = []
            notes = []
            failedPost = nil
        }
        self.ownerUserID = ownerUserID
        self.coupleID = coupleID
        await reload()
    }

    func updateCoupleID(_ coupleID: UUID?) {
        self.coupleID = coupleID
    }

    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .stories) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await reload()
        }
    }

    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        guard let ownerUserID else {
            stories = []
            notes = []
            return
        }
        let cached = await cache.snapshot(ownerUserID: ownerUserID)
        guard generation == reloadGeneration, self.ownerUserID == ownerUserID else { return }
        stories = cached.stories
        notes = cached.notes
    }

    /// Shares `photo` with an optional caption. Returns false and sets `error` when it
    /// could not be sent, so the composer stays open with the photo and caption.
    func post(photo: Data, caption: String) async -> Bool {
        guard !isPosting else { return false }
        guard ownerUserID != nil, let coupleID, let gateway else {
            error = .postFailed
            return false
        }
        let caption = Self.cleanCaption(caption)
        isPosting = true
        defer { isPosting = false }

        let stamp = await writeStamp()
        guard let compressed = await Self.compress(photo) else {
            error = .photoUnreadable
            return false
        }
        let attempt = postAttempt(photo: photo, caption: caption)
        do {
            let story = try await gateway.post(
                id: attempt.id,
                photo: MemoryUploadMedia(
                    data: compressed.data,
                    purpose: .story,
                    mimeType: compressed.mediaType,
                    fileExtension: compressed.fileExtension,
                    width: compressed.width,
                    height: compressed.height
                ),
                caption: caption,
                coupleID: coupleID,
                operations: attempt.operations
            )
            await finishPost(story, stamp: stamp)
            return true
        } catch {
            #if DEBUG
            logger.error("Posting a story failed: \(String(describing: error))")
            #endif
            failedPost = attempt
            self.error = PaeoniaFailure(error) == .offline ? .postOffline : .postFailed
            return false
        }
    }

    /// Shows the new story at once, before the live feed brings it. The photo itself
    /// downloads like any other, so nothing is written outside the purgeable cache.
    private func finishPost(_ story: Story?, stamp: WriteStamp) async {
        failedPost = nil
        defaults.set(true, forKey: Self.hasPostedKey)
        guard let story else { return }
        await save(stamp: stamp) { snapshot in
            snapshot.stories.removeAll { $0.id == story.id }
            snapshot.stories.insert(story, at: 0)
        }
    }

    /// Deletes one of this person's stories for both partners.
    func delete(_ story: Story) async -> Bool {
        guard story.authorUserID == ownerUserID, let gateway else { return false }
        let stamp = await writeStamp()
        do {
            try await gateway.delete(id: story.id, operation: operationProvider.makeOperation())
            await save(stamp: stamp) { snapshot in snapshot.stories.removeAll { $0.id == story.id } }
            return true
        } catch {
            #if DEBUG
            logger.error("Deleting a story failed: \(String(describing: error))")
            #endif
            self.error = PaeoniaFailure(error) == .offline ? .deleteOffline : .deleteFailed
            return false
        }
    }

    /// Marks the partner's story as opened. The ring updates at once. A failed send undoes
    /// the mark, so the ring stays bright and the next open tries again.
    func markSeen(_ story: Story) {
        guard story.authorUserID != ownerUserID, story.seenAt == nil, let gateway else { return }
        let seenAt = Date()
        Task {
            let stamp = await writeStamp()
            await save(stamp: stamp) { snapshot in
                if let index = snapshot.stories.firstIndex(where: { $0.id == story.id }),
                   snapshot.stories[index].seenAt == nil {
                    snapshot.stories[index].seenAt = seenAt
                }
            }
            do {
                try await gateway.markSeen(id: story.id)
            } catch {
                await save(stamp: stamp) { snapshot in
                    if let index = snapshot.stories.firstIndex(where: { $0.id == story.id }),
                       snapshot.stories[index].seenAt == seenAt {
                        snapshot.stories[index].seenAt = nil
                    }
                }
            }
        }
    }

    func clearError() {
        error = nil
    }

    /// Sets this person's note, or removes it when `text` is blank. Returns false and sets
    /// `error` when it could not be sent, so the editor stays open with the text.
    func setNote(_ text: String) async -> Bool {
        guard !isSavingNote, let ownerUserID, let gateway else { return false }
        let text = Self.cleanNote(text)
        isSavingNote = true
        defer { isSavingNote = false }
        let stamp = await writeStamp()
        do {
            let note = try await gateway.setNote(text, operation: operationProvider.makeOperation())
            await save(stamp: stamp) { snapshot in
                snapshot.notes.removeAll { $0.userID == ownerUserID }
                if let note { snapshot.notes.append(note) }
            }
            return true
        } catch {
            #if DEBUG
            logger.error("Saving a note failed: \(String(describing: error))")
            #endif
            self.error = PaeoniaFailure(error) == .offline ? .noteOffline : .noteFailed
            return false
        }
    }

    /// Who started a write and which purge it saw, read before the server call.
    private struct WriteStamp {
        let ownerUserID: UUID?
        let generation: Int
    }

    private func writeStamp() async -> WriteStamp {
        WriteStamp(ownerUserID: ownerUserID, generation: await cache.purgeGeneration)
    }

    /// Writes a change this phone made into the cache, unless the account changed or a
    /// privacy purge ran since `stamp` was taken.
    private func save(stamp: WriteStamp, _ change: @escaping @Sendable (inout StoriesSnapshot) -> Void) async {
        guard let owner = stamp.ownerUserID, owner == ownerUserID else { return }
        guard await cache.update(ownerUserID: owner, ifGeneration: stamp.generation, change) else { return }
        LocalStoreChanges.post(.stories, ownerUserID: owner)
    }

    /// The failed post again when the photo and caption are unchanged, otherwise a new one.
    private func postAttempt(photo: Data, caption: String?) -> FailedPost {
        if let failedPost, failedPost.matches(photo: photo, caption: caption) {
            return failedPost
        }
        return FailedPost(photo: photo, caption: caption, id: UUID(), operations: makeOperations())
    }

    private func makeOperations() -> StoryPostOperations {
        StoryPostOperations(
            reserve: operationProvider.makeOperation(),
            finalize: operationProvider.makeOperation(),
            post: operationProvider.makeOperation()
        )
    }

    nonisolated static func cleanNote(_ note: String) -> String? {
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(StoryNote.maxLength))
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func cleanCaption(_ caption: String) -> String? {
        let trimmed = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Story.maxCaptionLength))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Compressing a full camera photo takes a noticeable moment, so it runs off the
    /// main actor and the post spinner keeps moving.
    @concurrent
    private nonisolated static func compress(_ photo: Data) async -> ImageCompressor.CompressedImage? {
        ImageCompressor.compress(photo)
    }

    private struct FailedPost {
        let photo: Data
        let caption: String?
        let id: UUID
        let operations: StoryPostOperations

        func matches(photo: Data, caption: String?) -> Bool {
            self.photo == photo && self.caption == caption
        }
    }
}

nonisolated enum StoriesError: Equatable, Sendable {
    case postOffline
    case postFailed
    case photoUnreadable
    case deleteOffline
    case deleteFailed
    case noteOffline
    case noteFailed

    var message: String {
        switch self {
        case .postOffline:
            String(localized: .storiesErrorPostOffline)
        case .postFailed:
            String(localized: .storiesErrorPostFailed)
        case .photoUnreadable:
            String(localized: .storiesErrorPhotoUnreadable)
        case .deleteOffline:
            String(localized: .storiesErrorDeleteOffline)
        case .deleteFailed:
            String(localized: .storiesErrorDeleteFailed)
        case .noteOffline:
            String(localized: .storiesErrorNoteOffline)
        case .noteFailed:
            String(localized: .storiesErrorNoteFailed)
        }
    }
}
