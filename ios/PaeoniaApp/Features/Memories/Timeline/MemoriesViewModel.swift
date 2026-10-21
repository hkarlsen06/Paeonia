import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// What the edit form asks to save. `base` is the memory as it was when the form opened.
struct MemoryEdit {
    let base: MemoryRecord
    let title: String
    let date: String
    let note: String
    let newPhotos: [Data]
    let removedMedia: [MemoryMediaSnapshot]
    let place: MemoryPlace?
}

@MainActor
@Observable
final class MemoriesViewModel {
    let memoryService: any MemoryDataServicing
    let operationProvider: any SyncClientOperationProviding
    private let photoUploads: MemoryPhotoUploads
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
    /// True while a new memory or an edit is being saved. A second save is refused
    /// until it finishes, so a double tap (or reopening the form mid-save) can't
    /// create the same memory twice.
    private(set) var isSaving = false
    var notice: MemoriesNotice?
    /// Set by a comment push (`PaeoniaDeepLink.memory` with `showsComments`) to the memory whose
    /// comments should open. The memory's detail screen clears it once it shows them.
    var commentsRequestedMemoryID: UUID?

    /// The in-progress new-memory form. It lives here, not in the sheet or the screen,
    /// so a swipe-down or the tab being torn down keeps the work. Changes are saved per
    /// user on the device and restored when the user's session loads. A successful save
    /// or a deliberate discard clears it.
    var draft = MemoryDraft()
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
        self.coupleID = coupleID

        guard self.currentUserID != currentUserID else { return }
        // Text typed for the previous user is saved to that user before switching.
        flushDraft()
        self.currentUserID = currentUserID
        timeline = []
        hasLoadedOnce = false
        photoUploads.reset()
        draft = currentUserID.flatMap { draftStore.draft(for: $0) } ?? MemoryDraft()

        guard currentUserID != nil else { return }

        await load()
        // Show what's on the device first, then send any queued writes. The live
        // feed brings in the partner's changes and `observeStoreChanges` reloads.
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

        loadGeneration &+= 1
        let generation = loadGeneration
        let records = (try? await memoryService.loadCachedMemories(
            ownerUserID: currentUserID,
            includeHidden: false
        )) ?? []
        guard generation == loadGeneration, currentUserID == self.currentUserID else { return }

        timeline = MemoryTimeline.grouped(records)
        hasLoadedOnce = true
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
            photos,
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

        photoUploads.forget(photos, coupleID: coupleID)
        PaeoniaHaptics.memorySaved()
        updateDraft(MemoryDraft())
        await load()
        syncInBackground()
        return true
    }

    /// Saves the edit form for an existing memory. A title or date the person didn't
    /// touch keeps whatever is current now, so a change the partner made while the
    /// form was open isn't undone. Steps that already went through are skipped when the
    /// person retries after a failure. Returns whether everything was saved.
    func saveEdits(_ edit: MemoryEdit) async -> Bool {
        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving, let currentUserID, !title.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }

        // Read the stored copy, not the timeline, which can lag a delete by a moment.
        // Checking first also avoids uploading photos for a memory that is gone.
        guard let latest = await storedVisibleRecord(edit.base.snapshot.memoryID) else {
            notice = .memoryRemoved
            await load()
            return false
        }

        var changed = false
        defer {
            if changed {
                PaeoniaHaptics.memorySaved()
                syncInBackground()
            }
        }
        let steps = [saveDetails, savePlace, saveNote, removePhotos, addPhotos]
        for step in steps {
            // Each step reads the record the previous step left behind.
            let current = await storedVisibleRecord(latest.snapshot.memoryID) ?? latest
            switch await step(edit, current, currentUserID) {
            case .unchanged:
                continue
            case .saved:
                changed = true
            case .failed:
                await load()
                return false
            }
        }
        await load()
        return true
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

// MARK: - Edit steps

// Internal, not private, so `MemoriesViewModel+Place.swift` can use the shared steps.
extension MemoriesViewModel {
    enum StepResult {
        case unchanged
        case saved
        case failed
    }

    /// Sends the title and date. A field the person didn't touch keeps its current
    /// value. If the partner's change lands on this phone while this runs, the edit is
    /// worked out again from the newer record instead of undoing that change.
    func saveDetails(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        var current = latest
        for _ in 0..<3 {
            guard let change = detailChange(edit, current) else { return .unchanged }
            do {
                _ = try await memoryService.updateMemory(
                    ownerUserID: userID,
                    memoryID: current.snapshot.memoryID,
                    expectedRevision: current.snapshot.revision,
                    title: change.title,
                    memoryDate: change.date,
                    operation: operationProvider.makeOperation()
                )
                return .saved
            } catch MemoryDataServiceError.staleRevision {
                guard let fresh = await storedVisibleRecord(current.snapshot.memoryID) else {
                    notice = .memoryRemoved
                    return .failed
                }
                current = fresh
            } catch {
                report("Saving memory details failed", error, notice: .editFailed)
                return .failed
            }
        }
        notice = .editFailed
        return .failed
    }

    /// The title and date to send, or nil when they already match `current`.
    func detailChange(_ edit: MemoryEdit, _ current: MemoryRecord) -> (title: String, date: String)? {
        let base = edit.base.snapshot
        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = title != (base.title ?? "") ? title : (current.snapshot.title ?? title)
        let nextDate = edit.date != base.memoryDate ? edit.date : current.snapshot.memoryDate
        guard nextTitle != current.snapshot.title || nextDate != current.snapshot.memoryDate else {
            return nil
        }
        return (nextTitle, nextDate)
    }

    func saveNote(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        let note = edit.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseNote = edit.base.snapshot.ownNote?.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !note.isEmpty, note != baseNote, note != latest.snapshot.ownNote?.body else {
            return .unchanged
        }
        let saved = await perform("Saving a memory note failed", notice: .noteFailed) {
            _ = try await self.memoryService.upsertMemoryNote(
                ownerUserID: userID,
                memoryID: latest.snapshot.memoryID,
                expectedRevision: latest.snapshot.ownNote?.revision,
                body: note,
                operation: self.operationProvider.makeOperation()
            )
        }
        return saved ? .saved : .failed
    }

    func removePhotos(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        let stillVisible = Set(latest.snapshot.media.filter(\.isVisible).map(\.memoryMediaID))
        let toRemove = edit.removedMedia.filter { stillVisible.contains($0.memoryMediaID) }
        guard !toRemove.isEmpty else { return .unchanged }
        for media in toRemove {
            let removed = await perform("Removing a memory photo failed", notice: .editFailed) {
                _ = try await self.memoryService.removeMemoryMedia(
                    ownerUserID: userID,
                    memoryID: latest.snapshot.memoryID,
                    memoryMediaID: media.memoryMediaID,
                    operation: self.operationProvider.makeOperation()
                )
            }
            guard removed else { return .failed }
        }
        return .saved
    }

    func addPhotos(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        guard !edit.newPhotos.isEmpty else { return .unchanged }
        let coupleID = latest.snapshot.coupleID
        guard let uploaded = await photoUploads.upload(
            edit.newPhotos,
            coupleID: coupleID,
            ownerUserID: userID,
            startingSortOrder: (latest.snapshot.media.map(\.sortOrder).max() ?? 0) + 1
        ) else {
            notice = .photoUploadFailed
            return .failed
        }
        let attached = await perform("Attaching photos to a memory failed", notice: .photoUploadFailed) {
            _ = try await self.memoryService.attachMemoryMedia(
                ownerUserID: userID,
                memoryID: latest.snapshot.memoryID,
                optimisticMedia: uploaded,
                operation: self.operationProvider.makeOperation()
            )
        }
        guard attached else { return .failed }
        photoUploads.forget(edit.newPhotos, coupleID: coupleID)
        return .saved
    }

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
    func storedVisibleRecord(_ memoryID: UUID) async -> MemoryRecord? {
        guard let currentUserID,
              let record = try? await memoryService.loadCachedMemory(ownerUserID: currentUserID, memoryID: memoryID),
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
