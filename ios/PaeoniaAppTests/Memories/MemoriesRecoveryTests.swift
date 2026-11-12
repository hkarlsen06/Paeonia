import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct MemoriesRecoveryTests {
    @Test func failedReloadKeepsTheTimelineAndOpenMemory() async throws {
        let env = makeEnvironment()
        await env.model.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.model.createMemory(title: "Lake", date: "2026-06-30", note: "Cold water", photos: [])
        let record = try #require(env.model.timeline.flatMap(\.memories).first)
        await env.service.setReadFailure(true)

        await env.model.load()

        #expect(env.model.record(for: record.snapshot.memoryID) == record)
        #expect(env.model.hasLoadedOnce)
        #expect(env.model.loadFailure != nil)
        let result = await env.model.saveEdits(edit(record, title: "New title"))
        #expect(!result.isSaved)
        #expect(env.model.notice != .memoryRemoved)
        #expect(env.model.record(for: record.snapshot.memoryID) == record)

        await env.service.setReadFailure(false)
        await env.model.load()
        #expect(env.model.loadFailure == nil)
        #expect(env.model.record(for: record.snapshot.memoryID) == record)
    }

    @Test func failedFirstReadDoesNotConfirmAnEmptyCollection() async {
        let env = makeEnvironment()
        await env.service.setReadFailure(true)
        await env.model.configure(currentUserID: env.userID, coupleID: env.coupleID)

        #expect(!env.model.hasLoadedOnce)
        #expect(env.model.loadFailure != nil)
        await env.service.setReadFailure(false)
        await env.model.load()
        #expect(env.model.hasLoadedOnce)
        #expect(env.model.loadFailure == nil)
    }

    @Test func partialSaveReturnsTheSavedBaselineAndRetriesOnlyRemainingPhotos() async throws {
        let env = makeEnvironment(uploader: MemoryTestMediaUploader(failingCalls: [1]))
        await env.model.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.model.createMemory(title: "Lake", date: "2026-06-30", note: "First", photos: [])
        let record = try #require(env.model.timeline.flatMap(\.memories).first)
        let photo = MemoryDraftPhoto(data: makeMemoryTestImageData(color: .blue), accessibilityText: "Our lake")
        let draft = MemoryDraft(title: "Our trip", note: "Cold water", photos: [photo])
        let result = await env.model.saveEdits(edit(record, title: draft.title, note: draft.note, photos: [photo.data]))

        guard case .partial(let saved) = result else {
            Issue.record("The editor must disclose the durable part of the edit")
            return
        }
        let baseline = try #require(saved)
        #expect(baseline.snapshot.title == "Our trip")
        #expect(baseline.snapshot.ownNote?.body == "Cold water")
        #expect(baseline.snapshot.visibleMediaAssetIDs.isEmpty)
        let savedDraft = draft.savedBaseline(from: baseline)
        #expect(savedDraft.title == draft.title)
        #expect(savedDraft.note == draft.note)
        #expect(savedDraft.photos.isEmpty)
        #expect(draft.photos == [photo])

        let retry = await env.model.saveEdits(edit(
            baseline, title: draft.title, note: draft.note, photos: [photo.data]
        ))
        #expect(retry.isSaved)
        #expect(env.model.record(for: record.snapshot.memoryID)?.snapshot.visibleMediaAssetIDs.count == 1)
        let detailWrites = try await env.pending.inFlightOperations(ownerUserID: env.userID, kind: .updateMemory)
        #expect(detailWrites.count == 1)
    }

    @Test func partialSaveRebasesUntouchedFieldsWithoutOverwritingThePartnerOnRetry() async throws {
        let env = makeEnvironment(uploader: MemoryTestMediaUploader(failingCalls: [1]))
        await env.model.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.model.createMemory(title: "Trip", date: "2026-06-30", note: "First", photos: [])
        let original = try #require(env.model.timeline.flatMap(\.memories).first)
        try await env.store.saveRemote([.fixture(
            ownerUserID: env.userID, memoryID: original.snapshot.memoryID, coupleID: env.coupleID,
            title: "Partner's title", revision: 2, ownNoteRevision: 1,
            syncUpdatedAt: Date(timeIntervalSince1970: 500)
        )], ownerUserID: env.userID, mergePolicy: .overwriteLocalChanges)
        var draft = MemoryDraft(
            title: "Trip", date: try #require(MemoryTimeline.pickerDate(forLocalDate: "2026-06-30")),
            note: "New note", photos: [MemoryDraftPhoto(data: makeMemoryTestImageData(color: .blue))]
        )
        let result = await env.model.saveEdits(edit(
            original, title: draft.title, note: draft.note, photos: draft.photos.map(\.data)
        ))
        guard case .partial(let saved) = result, let saved else {
            Issue.record("Expected a partial save after the upload failed")
            return
        }
        draft.rebaseUntouchedFields(from: original, to: saved)
        #expect(draft.title == "Partner's title")
        #expect(draft.note == "New note")
        #expect(draft.photos.count == 1)
        let retry = await env.model.saveEdits(edit(
            saved, title: draft.title, note: draft.note, photos: draft.photos.map(\.data)
        ))
        #expect(retry.isSaved)
        #expect(env.model.record(for: original.snapshot.memoryID)?.snapshot.title == "Partner's title")
    }

    @Test func removingOnePhotoBeforeAnotherFailsStillReportsPartialSave() async throws {
        let env = makeEnvironment(uploader: MemoryTestMediaUploader())
        await env.model.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.model.createMemory(
            title: "Lake", date: "2026-06-30", note: "First",
            photos: [makeMemoryTestImageData(color: .blue), makeMemoryTestImageData(color: .red)]
        )
        let record = try #require(env.model.timeline.flatMap(\.memories).first)
        await env.service.failRemoval(call: 2)
        var change = edit(record, title: "Lake", note: "First")
        change = MemoryEdit(
            base: record, title: change.title, date: change.date, note: change.note,
            newPhotos: [], removedMedia: record.snapshot.media, place: record.snapshot.place
        )
        let result = await env.model.saveEdits(change)

        guard case .partial(let baseline) = result else {
            Issue.record("A removed photo cannot be undone by discarding the remaining edit")
            return
        }
        #expect(baseline?.snapshot.media.filter(\.isVisible).count == 1)
        #expect(env.model.record(for: record.snapshot.memoryID)?.snapshot.media.filter(\.isVisible).count == 1)
    }

    @Test func failedDraftWriteRetainsAttachmentsUntilRetryPersistsAllOfThem() async throws {
        let store = FailingMemoryDraftStore()
        let env = makeEnvironment(draftStore: store)
        await env.model.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let photos = [MemoryDraftPhoto(data: Data([1]), accessibilityText: "Lake"), MemoryDraftPhoto(data: Data([2]))]
        store.failsWrites = true
        env.model.updateDraft(MemoryDraft(title: "Trip", photos: photos))
        env.model.flushDraft()

        #expect(env.model.draft.photos == photos)
        #expect(env.model.draftNeedsSaving)
        #expect(env.model.draftFailure == .write)
        store.failsWrites = false
        env.model.saveDraftNow()
        #expect(!env.model.draftNeedsSaving)
        #expect(env.model.draftFailure == nil)

        let reopened = makeEnvironment(draftStore: store)
        await reopened.model.configure(currentUserID: env.userID, coupleID: env.coupleID)
        #expect(reopened.model.draft.photos.map(\.data) == photos.map(\.data))
        #expect(reopened.model.draft.photos.map(\.accessibilityText) == photos.map(\.accessibilityText))
    }

    @Test(arguments: [false, true])
    func queuedEditSurvivesCacheFailureAndRetriesWithoutAnotherOperation(addingPhoto: Bool) async throws {
        let store = FailingMemoryRecordStore()
        let pending = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(memoryStore: store, pendingOperationStore: pending)
        let userID = UUID()
        let model = MemoriesViewModel(
            memoryService: service, operationProvider: MemoryTestOperationProvider(),
            mediaUploader: MemoryTestMediaUploader(), imageProvider: nil, draftStore: makeIsolatedMemoryDraftStore()
        )
        await model.configure(currentUserID: userID, coupleID: UUID())
        #expect(await model.createMemory(title: "Original", date: "2026-06-30", note: "Cold water", photos: []))
        let original = try #require(model.timeline.flatMap(\.memories).first)
        await store.failWrites(true)
        let title = addingPhoto ? "Original" : "Replacement"
        let photos = addingPhoto ? [makeMemoryTestImageData(color: .blue)] : []
        let kind: SyncPendingOperationKind = addingPhoto ? .attachMemoryMedia : .updateMemory
        let result = await model.saveEdits(edit(original, title: title, photos: photos))
        guard case .partial(let saved) = result else {
            Issue.record("Discard must disclose the edit already in the outbox")
            return
        }
        let queued = try #require(saved)
        #expect(queued.snapshot.title == title)
        let operations = try await pending.inFlightOperations(ownerUserID: userID, kind: kind)
        #expect(operations.count == 1)
        #expect(queued.pendingOperationID == operations.first?.operation.id)
        #expect(await !model.saveEdits(edit(queued, title: title, photos: photos)).isSaved)
        await store.failWrites(false)
        #expect(await model.saveEdits(edit(queued, title: title, photos: photos)).isSaved)
        let retried = try await pending.inFlightOperations(ownerUserID: userID, kind: kind)
        #expect(retried.map(\.operation.id) == operations.map(\.operation.id))
        #expect(model.record(for: original.snapshot.memoryID)?.snapshot.title == title)
        #expect(model.record(for: original.snapshot.memoryID)?.snapshot.media.count == (addingPhoto ? 1 : 0))
    }

    private func edit(
        _ record: MemoryRecord, title: String, note: String = "Cold water", photos: [Data] = []
    ) -> MemoryEdit {
        MemoryEdit(
            base: record, title: title, date: record.snapshot.memoryDate, note: note,
            newPhotos: photos, removedMedia: [], place: record.snapshot.place
        )
    }

    private func makeEnvironment(
        uploader: (any MemoryMediaUploading)? = nil, draftStore: (any MemoryDraftStoring)? = nil
    ) -> Environment {
        let pending = InMemoryPendingSyncOperationRepository()
        let store = InMemoryMemoryRecordRepository()
        let service = GatedMemoryDataService(base: MemoryDataService(
            memoryStore: store, pendingOperationStore: pending
        ))
        let model = MemoriesViewModel(
            memoryService: service, operationProvider: MemoryTestOperationProvider(),
            mediaUploader: uploader, imageProvider: nil, draftStore: draftStore ?? makeIsolatedMemoryDraftStore()
        )
        return Environment(model: model, service: service, pending: pending, store: store)
    }

    private struct Environment {
        let model: MemoriesViewModel
        let service: GatedMemoryDataService
        let pending: InMemoryPendingSyncOperationRepository
        let store: InMemoryMemoryRecordRepository
        let userID = UUID()
        let coupleID = UUID()
    }
}

@MainActor
private final class FailingMemoryDraftStore: MemoryDraftStoring {
    let base = makeIsolatedMemoryDraftStore()
    var failsWrites = false

    func draft(for userID: UUID) throws -> MemoryDraft? { try base.draft(for: userID) }
    func setDraft(_ draft: MemoryDraft, for userID: UUID) throws {
        if failsWrites { throw CocoaError(.fileWriteOutOfSpace) }
        try base.setDraft(draft, for: userID)
    }
    func clearDraft(for userID: UUID) { base.clearDraft(for: userID) }
}

private actor FailingMemoryRecordStore {
    let base = InMemoryMemoryRecordRepository()
    var failsWrites = false
    func failWrites(_ value: Bool) { failsWrites = value }
    func saveLocal(_ record: MemoryRecord) async throws {
        if failsWrites { throw CocoaError(.fileWriteOutOfSpace) }
        try await base.saveLocal(record)
    }
    func load(ownerUserID: UUID, includeHidden: Bool) async throws -> [MemoryRecord] {
        try await base.load(ownerUserID: ownerUserID, includeHidden: includeHidden)
    }
    func load(ownerUserID: UUID, memoryID: UUID) async throws -> MemoryRecord? {
        try await base.load(ownerUserID: ownerUserID, memoryID: memoryID)
    }
    func saveRemote(_ rows: [MemoryRemoteRow], ownerUserID: UUID, mergePolicy: MemoryRemoteMergePolicy) async throws {
        try await base.saveRemote(rows, ownerUserID: ownerUserID, mergePolicy: mergePolicy)
    }
    func remove(ownerUserID: UUID, memoryID: UUID) async throws {
        await base.remove(ownerUserID: ownerUserID, memoryID: memoryID)
    }
}

extension FailingMemoryRecordStore: MemoryRecordPersisting {}
