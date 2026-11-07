import Foundation
import Observation
#if DEBUG
import OSLog
#endif

enum MemoryDraftFailure: Equatable {
    case read
    case write
}

@Observable
final class MemoriesViewModel {
    let memoryService: any MemoryDataServicing
    let operationProvider: any SyncClientOperationProviding
    let photoUploads: MemoryPhotoUploads
    private let imageProvider: (any MemoryMediaImageProviding)?
    private let photoSaver: any PhotoLibrarySaving
    let draftStore: any MemoryDraftStoring
    private var localChangeSyncHandler: (@MainActor @Sendable () async -> Void)?
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Memories"
    )
    #endif

    private(set) var currentUserID: UUID?
    private var coupleID: UUID?
    /// Bumped by every load, so a slow read that finishes after a newer one (or after
    /// the user changed) can't put older memories back on screen.
    private var loadGeneration = 0

    private(set) var timeline: [MemoryTimelineDay] = []
    /// Whether the first cached load has settled, so the empty state never flashes
    /// before we've read what's on the device.
    private(set) var hasLoadedOnce = false
    private(set) var loadFailure: PaeoniaFailure?
    var draftFailure: MemoryDraftFailure?
    var draftNeedsSaving = false
    /// True while a new memory or an edit is being saved. A second save is refused
    /// until it finishes, so a double tap (or reopening the form mid-save) can't
    /// create the same memory twice.
    private(set) var isSaving = false
    private var queuedCacheWrite: MemoryRecord?
    var notice: MemoriesNotice?
    /// Set by a comment push (`PaeoniaDeepLink.memory` with `showsComments`) to the memory whose
    /// comments should open. The memory's detail screen clears it once it shows them.
    var commentsRequestedMemoryID: UUID?
    /// Set by Siri's "open this photo" (`PaeoniaDeepLink.memoryPhoto`) to the photo the open
    /// memory should show. The memory's detail screen clears it once it shows the photo.
    var requestedPhotoID: UUID?
    /// Set when Siri brought photos for a new memory. The Memories screen opens the form and clears it.
    var isNewMemoryRequested = false

    /// The in-progress new-memory form. It lives here, not in the sheet or the screen,
    /// so a swipe-down or the tab being torn down keeps the work. Changes are saved per
    /// user on the device and restored when the user's session loads. A successful save
    /// or a deliberate discard clears it.
    var draft = MemoryDraft()
    @ObservationIgnored var pendingImportedPhotos: [UUID: [MemoryDraftPhoto]] = [:]
    @ObservationIgnored var pendingDraftSave: Task<Void, Never>?

    init(
        memoryService: (any MemoryDataServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        mediaUploader: (any MemoryMediaUploading)? = MemoriesViewModel.makeDefaultUploader(),
        mediaImageCache: (any MemoryMediaImageCacheWriting)? = MemoryMediaImageDiskCache(),
        imageProvider: (any MemoryMediaImageProviding)? = MemoryMediaImageProviderFactory.shared,
        photoSaver: any PhotoLibrarySaving = PhotoLibrarySaver(),
        draftStore: (any MemoryDraftStoring)? = nil
    ) {
        let operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.memoryService = memoryService ?? MemoryDataServiceFactory.makeDefault()
        self.operationProvider = operationProvider
        self.photoUploads = MemoryPhotoUploads(
            uploader: mediaUploader,
            imageCache: mediaImageCache,
            operationProvider: operationProvider
        )
        self.imageProvider = imageProvider
        self.photoSaver = photoSaver
        self.draftStore = draftStore ?? LocalMemoryDraftStore.shared
    }

    private nonisolated static func makeDefaultUploader() -> (any MemoryMediaUploading)? {
        try? LiveMemoryMediaUploadService.live()
    }

    /// Whether photo attachment is possible. False in previews/tests with no uploader,
    /// so those surfaces can hide the photo controls instead of failing on tap.
    var canAttachPhotos: Bool {
        photoUploads.isAvailable && coupleID != nil
    }

    /// Which photo a running save is sending, for the save button.
    var photoUploadProgress: MemoryPhotoUploadProgress? {
        photoUploads.progress
    }

    /// Wires the tab to the app's sync engine so a just-saved memory is pushed promptly
    /// and the server's canonical copy is pulled back (mirrors the daily-challenge and
    /// location patterns).
    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        localChangeSyncHandler = handler
    }

    // MARK: - Configuration

    /// Configures the tab with the signed-in user and active couple. Only a change of
    /// the signed-in user reloads. The couple id can refresh without re-reading the
    /// list (it only affects creating new memories). Keep this the load-bearing input
    /// for `.task(id:)`; route cosmetic refreshes through `updateContext`.
    func configure(currentUserID: UUID?, coupleID: UUID?) async {
        if self.coupleID != coupleID { queuedCacheWrite = nil }
        self.coupleID = coupleID

        guard self.currentUserID != currentUserID else { return }
        // Text typed for the previous user is saved to that user before switching.
        flushDraft()
        queuedCacheWrite = nil
        self.currentUserID = currentUserID
        if currentUserID == nil { pendingImportedPhotos.removeAll() }
        timeline = []
        hasLoadedOnce = false
        loadFailure = nil
        photoUploads.reset()
        restoreDraft()

        guard currentUserID != nil else { return }

        await load()
        // Show what's on the device first, then send any queued writes. The live
        // feed brings in the partner's changes and `observeStoreChanges` reloads.
        syncInBackground()
    }

    /// Updates context that does not change what's loaded (the active couple id used
    /// for new memories). Safe to call from `.onChange` without triggering a reload.
    func updateContext(coupleID: UUID?) {
        if self.coupleID != coupleID { queuedCacheWrite = nil }
        self.coupleID = coupleID
    }

    // MARK: - Loading

    func load() async {
        guard let currentUserID else {
            timeline = []
            hasLoadedOnce = true
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        do {
            let records = try await memoryService.loadCachedMemories(
                ownerUserID: currentUserID,
                includeHidden: false
            )
            guard generation == loadGeneration, currentUserID == self.currentUserID else { return }
            timeline = MemoryTimeline.grouped(records)
            hasLoadedOnce = true
            loadFailure = nil
        } catch {
            guard generation == loadGeneration, currentUserID == self.currentUserID else { return }
            loadFailure = PaeoniaFailure(error)
            if hasLoadedOnce { notice = .loadFailed }
            logFailure("Reading saved memories failed", error)
        }
    }

    /// Re-reads the timeline whenever the local memory store changes, so a partner's new
    /// memory, edit, note, photo, or delete shows up without a refresh. Runs until the
    /// calling task is cancelled. Call it from a task tied to the screen.
    func observeStoreChanges() async {
        let changes = LocalStoreChanges.changes(in: .memories)
        // `configure` does the first load. If it already finished, a write may have landed
        // before this subscription started, so read again.
        if hasLoadedOnce {
            await load()
        }
        for await change in changes where change.ownerUserID == currentUserID {
            await load()
        }
    }

    /// Pull-to-refresh: send any queued local memory writes, then re-read the local
    /// cache. Partner changes arrive on their own through the live feed.
    func refresh() async {
        await localChangeSyncHandler?()
        await load()
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

    // MARK: - Changes

    /// Saves a new memory. Title is required, plus at least a note or one photo (the UI
    /// enforces both before enabling Save; the guards here are a backstop). Photos are
    /// uploaded first so the created memory references real assets; if any upload fails
    /// nothing is saved and the form stays put so the user can retry. Content is never
    /// silently dropped. Returns whether the memory was saved.
    func createMemory(
        title: String,
        date: String,
        note: String,
        photos: [Data],
        photoDescriptions: [String] = [],
        place: MemoryPlace? = nil
    ) async -> Bool {
        guard !isSaving else { return false }
        guard let currentUserID, let coupleID else {
            notice = .createFailed
            return false
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedNote.isEmpty || !photos.isEmpty else { return false }

        isSaving = true
        defer { isSaving = false }

        guard let media = await photoUploads.upload(
            MemoryDraftPhoto.photos(photos, descriptions: photoDescriptions),
            coupleID: coupleID,
            ownerUserID: currentUserID,
            startingSortOrder: 0
        ) else {
            notice = .photoUploadFailed
            return false
        }
        let created = await perform("Saving a new memory failed", notice: .createFailed) {
            _ = try await self.memoryService.createMemory(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                memoryID: UUID(),
                title: trimmedTitle,
                memoryDate: date,
                noteBody: trimmedNote.isEmpty ? nil : trimmedNote,
                optimisticMedia: media,
                place: place,
                operation: self.operationProvider.makeOperation()
            )
        }
        guard created else { return false }

        photoUploads.reset()
        PaeoniaHaptics.memorySaved()
        updateDraft(MemoryDraft())
        await load()
        syncInBackground()
        return true
    }

    /// Saves the edit form for an existing memory. A title or date the person didn't
    /// touch keeps whatever is current now, so a change the partner made while the
    /// form was open isn't undone. Steps that already went through are skipped when the
    /// person retries after a failure. A partial result carries the saved baseline
    /// so the form can retain only the remaining changes.
    func saveEdits(_ edit: MemoryEdit) async -> MemorySaveResult {
        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving, let currentUserID, !title.isEmpty else { return .failed }
        isSaving = true
        defer { isSaving = false }

        var changed = false
        defer {
            if changed {
                PaeoniaHaptics.memorySaved()
                syncInBackground()
            }
        }
        do {
            if let queued = queuedCacheWrite {
                try await memoryService.repairQueuedCacheWrite(queued)
                queuedCacheWrite = nil
                changed = true
            }
            // A failed read is not evidence that the partner removed the memory.
            let steps = [saveDetails, savePlace, saveNote, removePhotos, addPhotos]
            for step in steps {
                guard let current = try await storedVisibleRecord(edit.base.snapshot.memoryID) else {
                    notice = .memoryRemoved
                    return await failedEditResult(edit, changed: changed)
                }
                let result = await step(edit, current, currentUserID)
                changed = changed || result.savedChanges
                if result.hasFailed {
                    return await failedEditResult(edit, changed: changed)
                }
            }
            await load()
            return .saved
        } catch {
            report("Reading a memory for editing failed", error, notice: .editFailed)
            return await failedEditResult(edit, changed: changed)
        }
    }

    private func failedEditResult(_ edit: MemoryEdit, changed: Bool) async -> MemorySaveResult {
        await load()
        let queued = queuedCacheWrite.flatMap {
            $0.snapshot.memoryID == edit.base.snapshot.memoryID ? $0 : nil
        }
        guard changed || queued != nil else { return .failed }
        let savedRecord = try? await storedVisibleRecord(edit.base.snapshot.memoryID)
        return .partial(savedRecord: queued ?? savedRecord)
    }

    /// Deletes (hides) a memory for both partners. Hidden immediately on the device and
    /// removed on the server by the same revision-checked path. A memory that is
    /// already gone (the partner deleted it first) counts as deleted.
    func deleteMemory(_ record: MemoryRecord) async {
        guard let currentUserID else { return }

        do {
            _ = try await memoryService.hideMemory(
                ownerUserID: currentUserID,
                memoryID: record.snapshot.memoryID,
                expectedRevision: record.snapshot.revision,
                operation: operationProvider.makeOperation()
            )
        } catch MemoryDataServiceError.missingMemory {
            await load()
            return
        } catch {
            logFailure("Deleting a memory failed", error)
            notice = .deleteFailed
            return
        }

        PaeoniaHaptics.destructiveActionConfirmed()
        await load()
        syncInBackground()
    }

    /// Adds a memory photo to the person's photo library, asking for add-only access the
    /// first time.
    func savePhotoToLibrary(mediaAssetID: UUID) async {
        guard let data = await imageProvider?.imageData(for: mediaAssetID) else {
            notice = .photoSaveFailed
            return
        }
        switch await photoSaver.saveImage(data) {
        case .saved:
            notice = .photoSaved
        case .permissionDenied:
            notice = .photoSaveDenied
        case .failed:
            notice = .photoSaveFailed
        }
    }

    func dismissNotice() {
        notice = nil
    }
}

extension MemoriesViewModel {
    // MARK: - Helpers

    /// Runs one local write. On failure it logs, shows `notice`, and returns false.
    func perform(
        _ context: String,
        notice failureNotice: MemoriesNotice,
        _ write: () async throws -> Void
    ) async -> Bool {
        do {
            try await write()
            return true
        } catch {
            report(context, error, notice: failureNotice)
            return false
        }
    }

    /// Shows the right notice for a failed local write and logs it.
    func report(_ context: String, _ error: Error, notice failureNotice: MemoriesNotice) {
        if let queued = error as? QueuedMemoryCacheWriteFailure {
            queuedCacheWrite = queued.record
        }
        switch error as? MemoryDataServiceError {
        case .missingMemory:
            notice = .memoryRemoved
        case .titleTooLong, .noteTooLong:
            notice = .textTooLong
        default:
            logFailure(context, error)
            notice = failureNotice
        }
    }

    /// The stored record, if the memory still exists and isn't waiting to be deleted.
    func storedVisibleRecord(_ memoryID: UUID) async throws -> MemoryRecord? {
        guard let currentUserID,
              let record = try await memoryService.loadCachedMemory(ownerUserID: currentUserID, memoryID: memoryID),
              record.snapshot.isVisible,
              record.syncStatus != .pendingDelete
        else { return nil }
        return record
    }

    /// Queued writes are already durable locally, so the UI never waits on sync. Flush
    /// in the background, then reload so the server's canonical copy replaces the
    /// optimistic one once it lands.
    func syncInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await localChangeSyncHandler?()
            await load()
        }
    }

    func logFailure(_ context: String, _ error: Error) {
        #if DEBUG
        logger.error("\(context, privacy: .public): \(String(describing: error))")
        #endif
    }
}
