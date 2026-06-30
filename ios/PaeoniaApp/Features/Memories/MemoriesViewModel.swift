import Foundation
import Observation
#if DEBUG
import OSLog
#endif

@MainActor
@Observable
final class MemoriesViewModel {
    /// A recoverable failure surfaced through the shared top banner. Copy is
    /// human-outcome focused; the underlying error is logged in debug only.
    enum Notice: Equatable {
        case createFailed
        case photoUploadFailed
        case deleteFailed
        case noteFailed

        var title: LocalizedStringResource {
            switch self {
            case .createFailed:
                .memoriesNoticeCreateFailedTitle
            case .photoUploadFailed:
                .memoriesNoticePhotoFailedTitle
            case .deleteFailed:
                .memoriesNoticeDeleteFailedTitle
            case .noteFailed:
                .memoriesNoticeNoteFailedTitle
            }
        }

        var message: LocalizedStringResource {
            switch self {
            case .photoUploadFailed:
                .memoriesNoticePhotoFailedMessage
            case .createFailed, .deleteFailed, .noteFailed:
                .memoriesNoticeRetryMessage
            }
        }
    }

    private let memoryService: any MemoryDataServicing
    private let operationProvider: any SyncClientOperationProviding
    private let mediaUploader: (any MemoryMediaUploading)?
    private var localChangeSyncHandler: (@MainActor @Sendable () async -> Void)?
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Memories"
    )
    #endif

    private var currentUserID: UUID?
    private var coupleID: UUID?

    private(set) var timeline: [MemoryTimelineDay] = []
    private(set) var isLoading = false
    /// Whether the first cached load has settled, so the empty state never flashes
    /// before we've read what's on the device.
    private(set) var hasLoadedOnce = false
    var notice: Notice?

    init(
        memoryService: (any MemoryDataServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        mediaUploader: (any MemoryMediaUploading)? = MemoriesViewModel.makeDefaultUploader()
    ) {
        self.memoryService = memoryService ?? MemoryDataServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.mediaUploader = mediaUploader
    }

    private nonisolated static func makeDefaultUploader() -> (any MemoryMediaUploading)? {
        try? LiveMemoryMediaUploadService.live()
    }

    /// Whether photo attachment is possible. False in previews/tests with no uploader,
    /// so those surfaces can hide the photo controls instead of failing on tap.
    var canAttachPhotos: Bool {
        mediaUploader != nil && coupleID != nil
    }

    /// Wires the tab to the app's sync engine so a just-saved memory is pushed promptly
    /// and the server's canonical copy is pulled back (mirrors the daily-challenge and
    /// location patterns).
    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        localChangeSyncHandler = handler
    }

    // MARK: - Configuration

    /// Configures the tab with the signed-in user and active couple. Only a change of
    /// the signed-in user reloads — the couple id can refresh without re-reading the
    /// list (it only affects creating new memories). Keep this the load-bearing input
    /// for `.task(id:)`; route cosmetic refreshes through `updateContext`.
    func configure(currentUserID: UUID?, coupleID: UUID?) async {
        self.coupleID = coupleID

        guard self.currentUserID != currentUserID else { return }
        self.currentUserID = currentUserID
        timeline = []
        hasLoadedOnce = false

        guard currentUserID != nil else { return }

        await load()
        // Show what's on the device first, then pull the server's memories in the
        // background and reload once they land.
        syncInBackground()
    }

    /// Updates context that does not change what's loaded (the active couple id used
    /// for new memories). Safe to call from `.onChange` without triggering a reload.
    func updateContext(coupleID: UUID?) {
        self.coupleID = coupleID
    }

    // MARK: - Loading

    func load() async {
        guard let currentUserID else {
            timeline = []
            hasLoadedOnce = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        let records = (try? await memoryService.loadCachedMemories(
            ownerUserID: currentUserID,
            includeHidden: false
        )) ?? []
        timeline = MemoryTimeline.grouped(records)
        hasLoadedOnce = true
    }

    /// Pull-to-refresh: flush any pending local memory writes and pull the latest from
    /// the server, then re-read the local cache.
    func refresh() async {
        await localChangeSyncHandler?()
        await load()
    }

    // MARK: - Mutations

    /// Saves a new memory. Title is required, plus at least a note or one photo (the UI
    /// enforces both before enabling Save; the guards here are a backstop). Photos are
    /// uploaded first so the created memory references real assets; if any upload fails
    /// nothing is saved and the form stays put so the user can retry — content is never
    /// silently dropped. Returns whether the memory was saved.
    func createMemory(title: String, date: String, note: String, photos: [Data]) async -> Bool {
        guard let currentUserID, let coupleID else {
            notice = .createFailed
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedNote.isEmpty || !photos.isEmpty else {
            return false
        }

        let optimisticMedia: [MemoryMediaSnapshot]
        if photos.isEmpty {
            optimisticMedia = []
        } else if let uploaded = await uploadPhotos(
            photos,
            coupleID: coupleID,
            ownerUserID: currentUserID,
            startingSortOrder: 0
        ) {
            optimisticMedia = uploaded
        } else {
            notice = .photoUploadFailed
            return false
        }

        let input = NewMemoryInput(
            ownerUserID: currentUserID,
            coupleID: coupleID,
            title: trimmedTitle,
            date: date,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            media: optimisticMedia
        )
        guard await performCreate(input) else { return false }

        PaeoniaHaptics.memorySaved()
        await load()
        syncInBackground()
        return true
    }

    /// The resolved inputs for a new memory, after validation and any photo uploads.
    private struct NewMemoryInput {
        let ownerUserID: UUID
        let coupleID: UUID
        let title: String
        let date: String
        let note: String?
        let media: [MemoryMediaSnapshot]
    }

    private func performCreate(_ input: NewMemoryInput) async -> Bool {
        do {
            _ = try await memoryService.createMemory(
                ownerUserID: input.ownerUserID,
                coupleID: input.coupleID,
                memoryID: UUID(),
                title: input.title,
                memoryDate: input.date,
                noteBody: input.note,
                optimisticMedia: input.media,
                operation: operationProvider.makeOperation()
            )
            return true
        } catch {
            logFailure("Saving a new memory failed", error)
            notice = .createFailed
            return false
        }
    }

    /// Updates a memory's title and date (revision-checked by the data layer). Returns
    /// whether the edit was saved.
    func updateDetails(for record: MemoryRecord, title: String, date: String) async -> Bool {
        guard let currentUserID else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        do {
            _ = try await memoryService.updateMemory(
                ownerUserID: currentUserID,
                memoryID: record.snapshot.memoryID,
                expectedRevision: record.snapshot.revision,
                title: trimmedTitle,
                memoryDate: date,
                operation: operationProvider.makeOperation()
            )
        } catch {
            logFailure("Saving memory details failed", error)
            notice = .createFailed
            return false
        }

        await load()
        syncInBackground()
        return true
    }

    /// Saves or updates the current user's own note on a memory. Returns whether it was
    /// saved.
    func saveNote(for record: MemoryRecord, body: String) async -> Bool {
        guard let currentUserID else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            _ = try await memoryService.upsertMemoryNote(
                ownerUserID: currentUserID,
                memoryID: record.snapshot.memoryID,
                expectedRevision: record.snapshot.ownNote?.revision,
                body: trimmed,
                operation: operationProvider.makeOperation()
            )
        } catch {
            logFailure("Saving a memory note failed", error)
            notice = .noteFailed
            return false
        }

        await load()
        syncInBackground()
        return true
    }

    /// Adds photos to an existing memory. Uploads first, then attaches; on any upload
    /// failure nothing is attached and a notice is shown. Returns whether photos were
    /// added.
    func addPhotos(to record: MemoryRecord, photos: [Data]) async -> Bool {
        guard let currentUserID, !photos.isEmpty else { return false }

        let startingSortOrder = (record.snapshot.media.map(\.sortOrder).max() ?? -1) + 1
        guard let uploaded = await uploadPhotos(
            photos,
            coupleID: record.snapshot.coupleID,
            ownerUserID: currentUserID,
            startingSortOrder: startingSortOrder
        ) else {
            notice = .photoUploadFailed
            return false
        }

        do {
            _ = try await memoryService.attachMemoryMedia(
                ownerUserID: currentUserID,
                memoryID: record.snapshot.memoryID,
                optimisticMedia: uploaded,
                operation: operationProvider.makeOperation()
            )
        } catch {
            logFailure("Attaching photos to a memory failed", error)
            notice = .photoUploadFailed
            return false
        }

        PaeoniaHaptics.memorySaved()
        await load()
        syncInBackground()
        return true
    }

    /// Removes one of the user's own photos from a memory.
    func removePhoto(from record: MemoryRecord, media: MemoryMediaSnapshot) async {
        guard let currentUserID else { return }

        do {
            _ = try await memoryService.removeMemoryMedia(
                ownerUserID: currentUserID,
                memoryID: record.snapshot.memoryID,
                memoryMediaID: media.memoryMediaID,
                operation: operationProvider.makeOperation()
            )
        } catch {
            logFailure("Removing a memory photo failed", error)
            notice = .deleteFailed
            return
        }

        await load()
        syncInBackground()
    }

    /// Deletes (hides) a memory for both partners. Hidden immediately on the device and
    /// removed on the server by the same revision-checked path.
    func deleteMemory(_ record: MemoryRecord) async {
        guard let currentUserID else { return }

        do {
            _ = try await memoryService.hideMemory(
                ownerUserID: currentUserID,
                memoryID: record.snapshot.memoryID,
                expectedRevision: record.snapshot.revision,
                operation: operationProvider.makeOperation()
            )
        } catch {
            logFailure("Deleting a memory failed", error)
            notice = .deleteFailed
            return
        }

        PaeoniaHaptics.destructiveActionConfirmed()
        await load()
        syncInBackground()
    }

    func dismissNotice() {
        notice = nil
    }

    /// The current record for a memory id, re-derived from the loaded timeline so a
    /// detail screen keeps showing the latest state after edits and disappears when the
    /// memory is deleted.
    func record(for memoryID: UUID) -> MemoryRecord? {
        for day in timeline {
            if let match = day.memories.first(where: { $0.snapshot.memoryID == memoryID }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// Compresses and uploads each photo in order, returning optimistic snapshots that
    /// already carry their backend `mediaAssetID`. Returns nil if any photo fails so the
    /// caller can abort without partially attaching.
    private func uploadPhotos(
        _ photos: [Data],
        coupleID: UUID,
        ownerUserID: UUID,
        startingSortOrder: Int
    ) async -> [MemoryMediaSnapshot]? {
        guard let mediaUploader else { return nil }

        var snapshots: [MemoryMediaSnapshot] = []
        for (index, data) in photos.enumerated() {
            guard let compressed = ImageCompressor.compress(data) else { return nil }

            let media = MemoryUploadMedia(
                data: compressed.data,
                purpose: .photo,
                mimeType: compressed.mediaType,
                fileExtension: compressed.fileExtension,
                width: compressed.width,
                height: compressed.height
            )

            do {
                let result = try await mediaUploader.uploadMedia(
                    media,
                    memoryMediaID: UUID(),
                    coupleID: coupleID,
                    reserveOperation: operationProvider.makeOperation(),
                    finalizeOperation: operationProvider.makeOperation()
                )
                snapshots.append(
                    result.optimisticSnapshot(
                        ownerUserID: ownerUserID,
                        sortOrder: startingSortOrder + index
                    )
                )
            } catch {
                logFailure("Uploading a memory photo failed", error)
                return nil
            }
        }
        return snapshots
    }

    /// Queued writes are already durable locally, so the UI never waits on sync. Flush
    /// in the background, then reload so the server's canonical copy replaces the
    /// optimistic one once it lands.
    private func syncInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await localChangeSyncHandler?()
            await load()
        }
    }

    private func logFailure(_ context: String, _ error: Error) {
        #if DEBUG
        logger.error("\(context, privacy: .public): \(String(describing: error))")
        #endif
    }
}
